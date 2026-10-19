import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:logging/logging.dart';
import 'package:uuid/uuid.dart';

import '../database/app_database.dart';
import '../network/api_client.dart';
import '../time/server_clock.dart';
import 'wire.dart';

final _log = Logger('sync');

/// What one sync did.
class SyncReport {
  final int pushed;
  final int pulled;
  final int conflicts;

  const SyncReport({this.pushed = 0, this.pulled = 0, this.conflicts = 0});
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
class SyncEngine {
  final AppDatabase db;
  final ApiClient api;
  final ServerClock clock;

  /// Records per pull page, of each kind. M2 makes it adapt to the network.
  final int pageSize;

  SyncEngine(this.db, this.api, this.clock, {this.pageSize = 200});

  /// At most this many records, or [maxBatchBytes] of JSON, per push. At
  /// 100 kbps, 64 KB uploads in about 5 seconds.
  static const maxBatchRecords = 200;
  static const maxBatchBytes = 64 * 1024;

  static const _cursorKey = 'cursor';
  static const _clockKey = 'clock_offset_ms';
  static const lastSyncKey = 'last_sync_at';

  Future<SyncReport>? _running;

  /// Pushes everything pending, then pulls until up to date. One sync at a
  /// time: a call while one runs gets that one's result.
  Future<SyncReport> sync() =>
      _running ??= _run().whenComplete(() => _running = null);

  Future<SyncReport> _run() async {
    final saved = await db.readMeta(_clockKey);
    if (saved != null) clock.offset = Duration(milliseconds: int.parse(saved));

    var pushed = 0;
    var conflicts = 0;
    while (true) {
      final result = await _pushOneBatch();
      if (result == null) break;
      pushed += result.applied;
      conflicts += result.conflicts;
    }
    final pulled = await _pullAll();

    await db.writeMeta(_clockKey, clock.offset.inMilliseconds.toString());
    await db.writeMeta(lastSyncKey, Wire.time(clock.now()));
    _log.info('synced: pushed $pushed, pulled $pulled, conflicts $conflicts');
    return SyncReport(pushed: pushed, pulled: pulled, conflicts: conflicts);
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

  /// Collects pending records into a batch and saves it, in one transaction.
  /// Customers go before entries, because an entry needs its customer on the
  /// server first.
  Future<PushBatchRow?> _freeze() => db.transaction(() async {
    final customers =
        await (db.select(db.customers)
              ..where((c) => c.syncState.equalsValue(SyncState.pending))
              ..orderBy([(c) => OrderingTerm.asc(c.updatedAt)])
              ..limit(maxBatchRecords))
            .get();
    final entries =
        await (db.select(db.ledgerEntries)
              ..where(
                (e) =>
                    e.syncState.equalsValue(SyncState.pending) &
                    // A credit sale's debt belongs to the server, which makes
                    // it from the sale; the phone never sends it.
                    e.saleId.isNull(),
              )
              ..orderBy([(e) => OrderingTerm.asc(e.createdAt)])
              ..limit(maxBatchRecords))
            .get();

    final wireCustomers = <Map<String, Object?>>[];
    final wireEntries = <Map<String, Object?>>[];
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

    for (final c in customers) {
      final json = Wire.customer(c);
      if (!fits(json)) break;
      wireCustomers.add(json);
      records.add({
        'table': 'customers',
        'id': c.id,
        'version': c.localVersion,
      });
    }
    // Entries only when every pending customer made it in, so no entry
    // travels ahead of its customer.
    if (wireCustomers.length == customers.length) {
      for (final e in entries) {
        final json = Wire.entry(e);
        if (!fits(json)) break;
        wireEntries.add(json);
        records.add({
          'table': 'transactions',
          'id': e.id,
          'version': e.localVersion,
        });
      }
    }
    if (records.isEmpty) return null;

    final batch = PushBatchRow(
      operationId: const Uuid().v7(),
      body: '',
      records: jsonEncode(records),
      createdAt: clock.now(),
      attempts: 0,
    );
    final frozen = batch.copyWith(
      body: jsonEncode({
        'operation_id': batch.operationId,
        if (wireCustomers.isNotEmpty) 'customers': wireCustomers,
        if (wireEntries.isNotEmpty) 'transactions': wireEntries,
      }),
    );
    await db.into(db.pushBatches).insert(frozen);
    return frozen;
  });

  /// Conflict reasons where the server kept its own copy and the phone should
  /// take it. Anything else means the record was not accepted at all.
  static const _serverWins = {'stale_write', 'immutable', 'already_voided'};

  /// Marks what the server accepted, records what it refused, and drops the
  /// batch, in one transaction.
  Future<({int applied, int conflicts})> _settle(
    PushBatchRow batch,
    Map<String, dynamic> view,
  ) => db.transaction(() async {
    final conflicts = <String, List<Map<String, dynamic>>>{};
    for (final c
        in (view['conflicts'] as List<dynamic>).cast<Map<String, dynamic>>()) {
      conflicts.putIfAbsent('${c['table']}/${c['id']}', () => []).add(c);
    }

    var applied = 0;
    for (final r
        in (jsonDecode(batch.records) as List<dynamic>)
            .cast<Map<String, dynamic>>()) {
      final table = r['table'] as String;
      final id = r['id'] as String;
      final version = r['version'] as int;
      final refusals = conflicts['$table/$id'] ?? const [];
      final refused = refusals.any((c) => !_serverWins.contains(c['reason']));

      for (final c in refusals) {
        await db
            .into(db.syncIssues)
            .insert(
              SyncIssuesCompanion.insert(
                recordTable: table,
                recordId: id,
                field: Value(c['field'] as String?),
                reason: c['reason'] as String,
                detail: Value(c['detail'] as String?),
                createdAt: clock.now(),
              ),
            );
      }
      if (refusals.isEmpty) applied++;

      final state = refused ? SyncState.refused : SyncState.synced;
      // Only the version that was sent. A record edited since stays pending
      // and goes in the next batch.
      if (table == 'customers') {
        await (db.update(db.customers)
              ..where((c) => c.id.equals(id) & c.localVersion.equals(version)))
            .write(
              CustomersCompanion(
                syncState: Value(state),
                changedFields: const Value(''),
              ),
            );
      } else {
        await (db.update(db.ledgerEntries)
              ..where((e) => e.id.equals(id) & e.localVersion.equals(version)))
            .write(LedgerEntriesCompanion(syncState: Value(state)));
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

  /// Pulls pages until the server says nothing more is waiting. Returns how
  /// many records arrived.
  Future<int> _pullAll() async {
    var cursor = int.parse(await db.readMeta(_cursorKey) ?? '0');
    var received = 0;
    while (true) {
      final sentAt = clock.deviceNow();
      final page =
          await api.get(
                '/sync/pull',
                query: {'cursor': cursor, 'limit': pageSize},
              )
              as Map<String, dynamic>;
      clock.observe(
        Wire.parseTime(page['server_time']),
        sentAt,
        clock.deviceNow(),
      );

      if (page['resync_required'] == true) {
        // Offline longer than the server keeps deletions. Start again from
        // zero; pending records are kept. M2 also removes the rows the
        // server no longer has, without emptying the screens first.
        _log.warning('resync required from cursor $cursor');
        cursor = 0;
        await db.writeMeta(_cursorKey, '0');
        continue;
      }

      final next = page['next_cursor'] as int;
      received += await db.transaction(() async {
        final count = await _applyPage(page);
        await db.writeMeta(_cursorKey, next.toString());
        return count;
      });
      cursor = next;
      if (page['has_more'] != true) return received;
    }
  }

  Future<int> _applyPage(Map<String, dynamic> page) async {
    final customers = (page['customers'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    final entries = (page['transactions'] as List<dynamic>)
        .cast<Map<String, dynamic>>();

    for (final json in customers) {
      final incoming = Wire.customerFromServer(json);
      final local = await (db.select(
        db.customers,
      )..where((c) => c.id.equals(incoming.id.value))).getSingleOrNull();
      if (local == null) {
        await db.into(db.customers).insert(incoming);
      } else if (local.syncState == SyncState.synced) {
        await db
            .update(db.customers)
            .replace(
              incoming.copyWith(localVersion: Value(local.localVersion)),
            );
      } else {
        await db.update(db.customers).replace(_mergeCustomer(local, incoming));
      }
    }

    for (final json in entries) {
      final incoming = Wire.entryFromServer(json);
      final local = await (db.select(
        db.ledgerEntries,
      )..where((e) => e.id.equals(incoming.id.value))).getSingleOrNull();
      if (local == null) {
        await db.into(db.ledgerEntries).insert(incoming);
      } else if (local.syncState == SyncState.synced) {
        await db
            .update(db.ledgerEntries)
            .replace(
              incoming.copyWith(localVersion: Value(local.localVersion)),
            );
      }
      // Pending here: an entry, or a void of one, this phone has not sent
      // yet. It stays as it is until the push.
    }
    return customers.length + entries.length;
  }

  /// A customer pending on this phone, updated from the server's copy: the
  /// fields this phone edited keep its values, the rest take the server's.
  /// A new record not yet accepted keeps all of its own.
  static CustomersCompanion _mergeCustomer(
    CustomerRow local,
    CustomersCompanion server,
  ) {
    final mine = local.changedFields.isEmpty
        ? Wire.customerFields
        : local.changedFields.split(',').toSet();
    final row = local.toCompanion(true);
    return row.copyWith(
      name: mine.contains('name') ? row.name : server.name,
      phone: mine.contains('phone') ? row.phone : server.phone,
      notes: mine.contains('notes') ? row.notes : server.notes,
      isDeleted: mine.contains('is_deleted') ? row.isDeleted : server.isDeleted,
      creditLimitCents: mine.contains('credit_limit')
          ? row.creditLimitCents
          : server.creditLimitCents,
      createdBy: server.createdBy,
      createdAt: server.createdAt,
    );
  }
}
