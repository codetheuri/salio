import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:logging/logging.dart';
import 'package:uuid/uuid.dart';

import '../database/app_database.dart';
import '../network/api_client.dart';
import '../network/api_exception.dart';
import '../time/server_clock.dart';
import 'sync_kinds.dart';
import 'wire.dart';

final _log = Logger('sync');

/// What one sync did.
class SyncReport {
  final int pushed;
  final int pulled;
  final int conflicts;

  /// A full resync finished during this sync.
  final bool resynced;

  const SyncReport({
    this.pushed = 0,
    this.pulled = 0,
    this.conflicts = 0,
    this.resynced = false,
  });
}

/// What the phone does with each conflict reason (docs/10, §4.3).
abstract final class ConflictReasons {
  /// The server kept its own copy, and the phone takes it without a word:
  /// a newer edit won, or the entry had already changed elsewhere.
  static const silent = {'stale_write', 'immutable', 'already_voided'};

  /// The server kept its own copy, and the phone takes it with a short
  /// note, because the user's change was undone.
  static const notices = {'forbidden', 'has_balance', 'already_ordered'};

  /// Refused because what the record points to is not on the server yet.
  /// It waits, and goes again once that record is accepted.
  static const waits = {'unknown_customer', 'unknown_supplier'};

  /// Whether the server took its own copy over this phone's. Every reason
  /// not listed, including any a newer server adds, refuses the record: it
  /// is kept aside for the user, never silently dropped.
  static bool serverWins(String reason) =>
      silent.contains(reason) || notices.contains(reason);
}

/// Moves changes between this phone's database and server-v2 (docs/10,
/// §4.3). The rules that keep records from being lost or doubled:
///
/// - A push batch is **frozen** before it is sent: its operation_id and its
///   exact body are saved, and a retry sends that same body. The server
///   replays its first answer to a repeated operation_id, so the answer
///   always matches the records sent.
/// - A record edited while its batch is in flight stays pending: a batch
///   remembers each record's local version, and only that version is marked
///   synced.
/// - A pulled page and the cursor after it are saved in **one transaction**,
///   so the cursor can never move past rows that were not saved. That is how
///   v1 lost records for good.
/// - Records still pending on this phone keep their local changes when a
///   pull brings the server's copy.
/// - A conflict takes the server's copy, which comes with the answer (B2),
///   or keeps the record aside for the user; nothing is dropped silently.
/// - A resync pulls everything again without emptying the screens first,
///   then removes what the server no longer has.
class SyncEngine {
  final AppDatabase db;
  final ApiClient api;
  final ServerClock clock;

  /// Records per pull page, of each kind, to start with. It doubles while
  /// pages arrive quickly, up to [maxPageSize], and halves after a timeout:
  /// the server stops writing an answer after 60 seconds, so a large page
  /// on 2G might never arrive.
  final int pageSize;
  final int maxPageSize;
  static const minPageSize = 25;

  /// A page that arrives within this long lets the next one be bigger.
  static const quickPage = Duration(seconds: 5);

  /// Timeouts in a row, each at a smaller page, before a pull gives up.
  static const maxPullTimeouts = 3;

  int _page;

  SyncEngine(
    this.db,
    this.api,
    this.clock, {
    this.pageSize = 200,
    this.maxPageSize = 2000,
  }) : _page = pageSize;

  int _bounded(int n) => n.clamp(
    maxPageSize < minPageSize ? maxPageSize : minPageSize,
    maxPageSize,
  );

  /// The page size the next pull starts at.
  int get currentPageSize => _page;

  /// At most this many records, or [maxBatchBytes] of JSON, per push. At
  /// 100 kbps, 64 KB uploads in about 5 seconds.
  static const maxBatchRecords = 200;
  static const maxBatchBytes = 64 * 1024;

  static const _cursorKey = 'cursor';
  static const _clockKey = 'clock_offset_ms';
  static const _resyncKey = 'resync';
  static const _accessKey = 'access';
  static const lastSyncKey = 'last_sync_at';

  Future<SyncReport>? _running;

  /// Pushes everything pending, then pulls until up to date. One sync at a
  /// time: a call while one runs gets that one's result.
  ///
  /// [access] names what the server lets this user read (the role, for
  /// now). When it differs from the last sync's, everything is pulled
  /// again: an owner who becomes staff must lose the supplier records, and
  /// staff made owner must receive them.
  Future<SyncReport> sync({String? access}) =>
      _running ??= _run(access).whenComplete(() => _running = null);

  Future<SyncReport> _run(String? access) async {
    final saved = await db.readMeta(_clockKey);
    if (saved != null) clock.offset = Duration(milliseconds: int.parse(saved));
    if (access != null) await _noteAccess(access);

    var pushed = 0;
    var conflicts = 0;
    while (true) {
      final result = await _pushOneBatch();
      if (result == null) break;
      pushed += result.applied;
      conflicts += result.conflicts;
    }
    final pull = await _pullAll();

    await db.writeMeta(_clockKey, clock.offset.inMilliseconds.toString());
    await db.writeMeta(lastSyncKey, Wire.time(clock.now()));
    _log.info(
      'synced: pushed $pushed, pulled ${pull.received}, conflicts $conflicts'
      '${pull.resynced ? ', resynced' : ''}',
    );
    return SyncReport(
      pushed: pushed,
      pulled: pull.received,
      conflicts: conflicts,
      resynced: pull.resynced,
    );
  }

  Future<void> _noteAccess(String access) async {
    final before = await db.readMeta(_accessKey);
    if (before == access) return;
    await db.transaction(() async {
      if (before != null) {
        _log.info('access changed from $before to $access: resyncing');
        await _startResync();
      }
      await db.writeMeta(_accessKey, access);
    });
  }

  // --- Push ---------------------------------------------------------------

  /// Sends the frozen batch, freezing one first if none is waiting. Null when
  /// nothing is pending.
  Future<({int applied, int conflicts})?> _pushOneBatch() async {
    final batch =
        await (db.select(db.pushBatches)
              ..orderBy([(b) => OrderingTerm.asc(b.createdAt)])
              ..limit(1))
            .getSingleOrNull() ??
        await _freeze();
    if (batch == null) return null;

    await (db.update(db.pushBatches)
          ..where((b) => b.operationId.equals(batch.operationId)))
        .write(PushBatchesCompanion(attempts: Value(batch.attempts + 1)));

    final sentAt = clock.deviceNow();
    // The saved text, not a re-encoding of it: byte for byte what was frozen.
    final view =
        await api.post('/sync/push', batch.body) as Map<String, dynamic>;
    clock.observe(
      Wire.parseTime(view['server_time']),
      sentAt,
      clock.deviceNow(),
    );
    return _settle(batch, view);
  }

  /// Pending rows of one kind, oldest first.
  Future<List<DataClass>> _pending(SyncKind<DataClass> kind) async {
    final rows = await db
        .customSelect(
          'SELECT * FROM ${kind.tableName(db)} WHERE sync_state = ?'
          '${kind.neverSent == null ? '' : ' AND NOT (${kind.neverSent})'} '
          'ORDER BY ${kind.sendOrder} LIMIT $maxBatchRecords',
          variables: [Variable.withInt(SyncState.pending.index)],
        )
        .get();
    return [for (final r in rows) await kind.read(db, r.data)];
  }

  /// Collects pending records into a batch and saves it, in one transaction.
  /// Customers and suppliers go before what points to them.
  Future<PushBatchRow?> _freeze() => db.transaction(() async {
    await _releaseWaiting();

    final body = <String, List<Map<String, Object?>>>{};
    final records = <Map<String, Object?>>[];
    var bytes = 0;
    bool fits(Map<String, Object?> json) {
      final size = utf8.encode(jsonEncode(json)).length;
      if (records.isNotEmpty &&
          (records.length >= maxBatchRecords || bytes + size > maxBatchBytes)) {
        return false;
      }
      bytes += size;
      return true;
    }

    // Records of the other kinds only when every pending parent made it
    // in, so nothing travels ahead of what it points to.
    var parentsIn = true;
    for (final kind in syncKinds) {
      if (!kind.isParent && !parentsIn) break;
      final pending = await _pending(kind);
      var taken = 0;
      for (final row in pending) {
        final json = kind.encodeRow(row);
        if (!fits(json)) break;
        body.putIfAbsent(kind.wire, () => []).add(json);
        records.add({
          'table': kind.wire,
          'id': kind.idOf(row),
          'version': kind.versionOf(row),
        });
        taken++;
      }
      if (kind.isParent && taken < pending.length) parentsIn = false;
    }
    if (records.isEmpty) return null;

    final operationId = const Uuid().v7();
    final batch = PushBatchRow(
      operationId: operationId,
      body: jsonEncode({'operation_id': operationId, ...body}),
      records: jsonEncode(records),
      createdAt: clock.now(),
      attempts: 0,
    );
    await db.into(db.pushBatches).insert(batch);
    return batch;
  });

  /// Records refused because their parent was not on the server go again
  /// once the parent is accepted.
  Future<void> _releaseWaiting() async {
    for (final kind in syncKinds) {
      final parent = kind.parent;
      if (parent == null) continue;
      final table = kind.tableName(db);
      final parentTable = syncKind(parent.kind).tableName(db);
      final waiting =
          'SELECT record_id FROM sync_issues '
          "WHERE record_table = '${kind.wire}' AND reason = '${parent.reason}'";
      final released = await db.customWriteReturning(
        'UPDATE $table SET sync_state = ?1 '
        'WHERE sync_state = ?2 AND id IN ($waiting) '
        'AND ${parent.column} IN '
        '(SELECT id FROM $parentTable WHERE sync_state = ?3) '
        'RETURNING id',
        variables: [
          Variable.withInt(SyncState.pending.index),
          Variable.withInt(SyncState.refused.index),
          Variable.withInt(SyncState.synced.index),
        ],
        updates: {kind.table(db)},
      );
      for (final row in released) {
        await _clearIssues(kind.wire, row.read<String>('id'));
      }
    }
  }

  Future<void> _clearIssues(String table, String id) => (db.delete(
    db.syncIssues,
  )..where((i) => i.recordTable.equals(table) & i.recordId.equals(id))).go();

  /// Marks what the server accepted, records what it refused, stores the
  /// server's copies, and drops the batch, in one transaction.
  Future<({int applied, int conflicts})> _settle(
    PushBatchRow batch,
    Map<String, dynamic> view,
  ) => db.transaction(() async {
    final conflicts = <String, List<Map<String, dynamic>>>{};
    for (final c
        in (view['conflicts'] as List<dynamic>).cast<Map<String, dynamic>>()) {
      conflicts.putIfAbsent('${c['table']}/${c['id']}', () => []).add(c);
    }
    // The server's copy of each conflicting record (B2). An older server
    // sends none: the phone then keeps its own until that record changes.
    final current = view['current'] is Map<String, dynamic>
        ? view['current'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final copies = <String, Map<String, dynamic>>{
      for (final kind in syncKinds)
        for (final json
            in (current[kind.wire] as List<dynamic>? ?? const [])
                .cast<Map<String, dynamic>>())
          '${kind.wire}/${json['id']}': json,
    };

    var applied = 0;
    for (final r
        in (jsonDecode(batch.records) as List<dynamic>)
            .cast<Map<String, dynamic>>()) {
      final table = r['table'] as String;
      final id = r['id'] as String;
      final version = r['version'] as int;
      final kind = syncKind(table);
      final refusals = conflicts['$table/$id'] ?? const [];
      final refused = refusals.any(
        (c) => !ConflictReasons.serverWins(c['reason'] as String),
      );

      // A new answer for this record replaces what was said before.
      await _clearIssues(table, id);
      for (final c in refusals) {
        final reason = c['reason'] as String;
        if (ConflictReasons.silent.contains(reason)) {
          _log.info('$table/$id: $reason ${c['field'] ?? ''} ${c['detail']}');
          continue;
        }
        final copy = copies['$table/$id'];
        await db
            .into(db.syncIssues)
            .insert(
              SyncIssuesCompanion.insert(
                recordTable: table,
                recordId: id,
                field: Value(c['field'] as String?),
                reason: reason,
                detail: Value(c['detail'] as String?),
                serverCopy: Value(
                  refused && copy != null ? jsonEncode(copy) : null,
                ),
                createdAt: clock.now(),
              ),
            );
      }
      if (refusals.isEmpty) applied++;

      final state = refused ? SyncState.refused : SyncState.synced;
      // Only the version that was sent. A record edited since stays pending
      // and goes in the next batch.
      await db.customUpdate(
        'UPDATE ${kind.tableName(db)} SET sync_state = ?1'
        '${state == SyncState.synced ? kind.onAccepted : ''} '
        'WHERE id = ?2 AND local_version = ?3',
        variables: [
          Variable.withInt(state.index),
          Variable.withString(id),
          Variable.withInt(version),
        ],
        updates: {kind.table(db)},
      );
    }

    // After the states, so an accepted record takes the copy outright and
    // one edited since keeps its new changes on top.
    for (final kind in syncKinds) {
      for (final json
          in (current[kind.wire] as List<dynamic>? ?? const [])
              .cast<Map<String, dynamic>>()) {
        await _store(kind, json);
      }
    }

    await (db.delete(
      db.pushBatches,
    )..where((b) => b.operationId.equals(batch.operationId))).go();
    if (view['replayed'] == true) {
      _log.info('push ${batch.operationId} was a replay of an earlier send');
    }
    return (applied: applied, conflicts: conflicts.length);
  });

  // --- Pull ---------------------------------------------------------------

  /// Pulls pages until the server says nothing more is waiting.
  Future<({int received, bool resynced})> _pullAll() async {
    var cursor = int.parse(await db.readMeta(_cursorKey) ?? '0');
    var resyncing = await db.readMeta(_resyncKey) == '1';
    var received = 0;
    var resynced = false;
    var timeouts = 0;
    while (true) {
      final sentAt = clock.deviceNow();
      final Map<String, dynamic> page;
      try {
        page =
            await api.get(
                  '/sync/pull',
                  query: {'cursor': cursor, 'limit': _page},
                )
                as Map<String, dynamic>;
      } on ApiException catch (e) {
        if (e.kind != ApiFailure.timeout) rethrow;
        // Smaller pages until one fits through the connection.
        _page = _bounded(_page ~/ 2);
        if (++timeouts >= maxPullTimeouts) rethrow;
        _log.info('pull timed out; trying pages of $_page');
        continue;
      }
      final receivedAt = clock.deviceNow();
      clock.observe(Wire.parseTime(page['server_time']), sentAt, receivedAt);
      final took = receivedAt.difference(sentAt);
      timeouts = 0;
      if (took < quickPage) {
        _page = _bounded(_page * 2);
      }

      if (page['resync_required'] == true) {
        // Offline longer than the server keeps deletions: what was deleted
        // meanwhile can no longer be described, so everything comes again.
        _log.warning('resync required from cursor $cursor');
        await db.transaction(_startResync);
        cursor = 0;
        resyncing = true;
        continue;
      }

      final next = page['next_cursor'] as int;
      final more = page['has_more'] == true;
      received += await db.transaction(() async {
        final count = await _applyPage(page, markSeen: resyncing);
        await db.writeMeta(_cursorKey, next.toString());
        if (resyncing && !more) await _finishResync();
        return count;
      });
      cursor = next;
      if (!more) {
        resynced = resyncing;
        return (received: received, resynced: resynced);
      }
    }
  }

  /// Begins pulling everything again. Nothing is removed yet: the screens
  /// keep showing what they have while the pages arrive.
  Future<void> _startResync() async {
    await db.delete(db.resyncSeen).go();
    await db.writeMeta(_cursorKey, '0');
    await db.writeMeta(_resyncKey, '1');
  }

  /// The last page of a resync is in: synced records it did not bring are
  /// ones the server no longer has, or no longer shows this user. Records
  /// not yet accepted stay.
  Future<void> _finishResync() async {
    for (final kind in syncKinds) {
      final removed = await db.customUpdate(
        'DELETE FROM ${kind.tableName(db)} WHERE sync_state = ?1 AND id NOT IN '
        '(SELECT record_id FROM resync_seen WHERE record_table = ?2)',
        variables: [
          Variable.withInt(SyncState.synced.index),
          Variable.withString(kind.wire),
        ],
        updates: {kind.table(db)},
        updateKind: UpdateKind.delete,
      );
      if (removed > 0) _log.info('resync removed $removed ${kind.wire}');
    }
    await db.delete(db.resyncSeen).go();
    await db.writeMeta(_resyncKey, '0');
  }

  Future<int> _applyPage(
    Map<String, dynamic> page, {
    required bool markSeen,
  }) async {
    var count = 0;
    for (final kind in syncKinds) {
      // A list this app does not know, or one the server leaves out (an
      // older server, or suppliers for staff), is simply absent.
      final rows = (page[kind.wire] as List<dynamic>? ?? const [])
          .cast<Map<String, dynamic>>();
      for (final json in rows) {
        await _store(kind, json);
        if (markSeen) {
          await db
              .into(db.resyncSeen)
              .insertOnConflictUpdate(
                ResyncSeenRow(
                  recordTable: kind.wire,
                  recordId: json['id'] as String,
                ),
              );
        }
      }
      count += rows.length;
    }
    return count;
  }

  /// Stores the server's copy of a record. A record pending or refused here
  /// keeps this phone's changes until they are pushed or resolved.
  Future<void> _store(
    SyncKind<DataClass> kind,
    Map<String, dynamic> json,
  ) async {
    final local = await db
        .customSelect(
          'SELECT * FROM ${kind.tableName(db)} WHERE id = ?',
          variables: [Variable.withString(json['id'] as String)],
          readsFrom: {kind.table(db)},
        )
        .getSingleOrNull();
    final table = kind.table(db);
    if (local == null ||
        local.read<int>('sync_state') == SyncState.synced.index) {
      // Its local version is not in the copy, so an existing row keeps its.
      await db.into(table).insertOnConflictUpdate(kind.decode(json));
      return;
    }
    if (local.read<int>('sync_state') == SyncState.refused.index) return;
    final merged = kind.mergePending(await kind.read(db, local.data), json);
    if (merged != null) await db.into(table).insertOnConflictUpdate(merged);
  }
}
