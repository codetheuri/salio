import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/sync/sync_engine.dart';
import '../../../core/sync/sync_kinds.dart';

/// What the user can do about an issue.
enum IssueAction {
  /// A note that the server undid a change; nothing to decide.
  dismiss,

  /// Drop this phone's version: put back the server's copy, or remove a
  /// record the server never had.
  discard,

  /// A customer added on two phones: move this phone's entries to the one
  /// the server already has, and drop this copy.
  useExisting,
}

/// One issue, with what is needed to describe its record.
class SyncIssueView {
  final SyncIssueRow issue;

  /// The record's name: a customer's or supplier's name, a sale's or stock
  /// note's product, an entry's customer. Null once the record is gone.
  final String? name;

  /// The record's amount, for entries and sales.
  final int? amountCents;

  /// `debt`, `payment`, `bill`: the kind of entry, when it is one.
  final String? entryType;

  /// For a duplicate customer, the customer the server already has, when
  /// this phone has received it.
  final String? existingCustomerId;

  const SyncIssueView(
    this.issue, {
    this.name,
    this.amountCents,
    this.entryType,
    this.existingCustomerId,
  });

  String get table => issue.recordTable;
  String get reason => issue.reason;

  /// A note, as opposed to a record kept aside.
  bool get isNotice => ConflictReasons.notices.contains(reason);

  bool get isWaiting => ConflictReasons.waits.contains(reason);

  List<IssueAction> get actions => [
    if (isNotice) IssueAction.dismiss,
    if (existingCustomerId != null) IssueAction.useExisting,
    if (!isNotice) IssueAction.discard,
  ];
}

/// The "Needs attention" list, and what the user can do about each issue
/// (docs/10, §4.3). Every action is one transaction, like any other write.
class SyncIssueRepository {
  final AppDatabase db;

  SyncIssueRepository(this.db);

  Stream<int> watchCount() => db
      .customSelect(
        'SELECT COUNT(*) AS n FROM sync_issues',
        readsFrom: {db.syncIssues},
      )
      .watchSingle()
      .map((r) => r.read<int>('n'));

  /// Every issue, newest first, with its record described.
  Stream<List<SyncIssueView>> watchAll() =>
      (db.select(db.syncIssues)..orderBy([
            (i) => OrderingTerm.desc(i.createdAt),
            (i) => OrderingTerm.desc(i.id),
          ]))
          .watch()
          .asyncMap((issues) async => [for (final i in issues) await _view(i)]);

  Future<SyncIssueView> _view(SyncIssueRow issue) async {
    final id = issue.recordId;
    switch (issue.recordTable) {
      case 'customers':
        final c = await _customer(id);
        return SyncIssueView(
          issue,
          name: c?.name,
          existingCustomerId: issue.reason == 'duplicate' && c != null
              ? await _sameNumber(c)
              : null,
        );
      case 'transactions':
        final e = await (db.select(
          db.ledgerEntries,
        )..where((r) => r.id.equals(id))).getSingleOrNull();
        return SyncIssueView(
          issue,
          name: e == null ? null : (await _customer(e.customerId))?.name,
          amountCents: e?.amountCents,
          entryType: e?.type,
        );
      case 'sales':
        final s = await (db.select(
          db.sales,
        )..where((r) => r.id.equals(id))).getSingleOrNull();
        return SyncIssueView(
          issue,
          name: s?.productName,
          amountCents: s?.amountCents,
        );
      case 'suppliers':
        final s = await (db.select(
          db.suppliers,
        )..where((r) => r.id.equals(id))).getSingleOrNull();
        return SyncIssueView(issue, name: s?.name);
      case 'supplier_transactions':
        final e = await (db.select(
          db.supplierEntries,
        )..where((r) => r.id.equals(id))).getSingleOrNull();
        final s = e == null
            ? null
            : await (db.select(
                db.suppliers,
              )..where((r) => r.id.equals(e.supplierId))).getSingleOrNull();
        return SyncIssueView(
          issue,
          name: s?.name,
          amountCents: e?.amountCents,
          entryType: e?.type,
        );
      case 'stock_requests':
        final r = await (db.select(
          db.stockRequests,
        )..where((r) => r.id.equals(id))).getSingleOrNull();
        return SyncIssueView(issue, name: r?.productName);
    }
    return SyncIssueView(issue);
  }

  Future<CustomerRow?> _customer(String id) => (db.select(
    db.customers,
  )..where((c) => c.id.equals(id))).getSingleOrNull();

  /// The customer the server already has with this one's phone number,
  /// once this phone has received it.
  Future<String?> _sameNumber(CustomerRow c) async {
    final phone = c.phone;
    if (phone == null) return null;
    final other =
        await (db.select(db.customers)
              ..where(
                (o) =>
                    o.phone.equals(phone) &
                    o.id.equals(c.id).not() &
                    o.isDeleted.equals(false) &
                    o.syncState.equalsValue(SyncState.synced),
              )
              ..limit(1))
            .getSingleOrNull();
    return other?.id;
  }

  /// "OK" on a note.
  Future<void> dismiss(SyncIssueRow issue) =>
      (db.delete(db.syncIssues)..where((i) => i.id.equals(issue.id))).go();

  /// "Discard mine": the server's copy goes back in, or, for a record the
  /// server never had, the record goes.
  Future<void> discard(SyncIssueRow issue) => db.transaction(() async {
    final kind = syncKind(issue.recordTable);
    final table = kind.table(db);
    final copy = issue.serverCopy;
    if (copy != null) {
      await db
          .into(table)
          .insertOnConflictUpdate(
            kind.decode(jsonDecode(copy) as Map<String, dynamic>),
          );
      // Not in the copy, so set here: the row is now the server's.
      await db.customUpdate(
        'UPDATE ${kind.tableName(db)} SET sync_state = ?1'
        '${kind.onAccepted} WHERE id = ?2',
        variables: [
          Variable.withInt(SyncState.synced.index),
          Variable.withString(issue.recordId),
        ],
        updates: {table},
      );
    } else {
      await db.customUpdate(
        'DELETE FROM ${kind.tableName(db)} WHERE id = ?1 AND sync_state != ?2',
        variables: [
          Variable.withString(issue.recordId),
          Variable.withInt(SyncState.synced.index),
        ],
        updates: {table},
        updateKind: UpdateKind.delete,
      );
    }
    await _clear(issue.recordTable, issue.recordId);
    // A discarded credit sale takes the debt this phone made for it.
    await db.followSales();
  });

  /// "Use the existing customer": this phone's entries and sales for the
  /// refused copy move to [existingId] and go again, and the copy goes.
  Future<void> useExisting(SyncIssueRow issue, String existingId) =>
      db.transaction(() async {
        final copyId = issue.recordId;
        for (final t in <TableInfo<Table, DataClass>>[
          db.ledgerEntries,
          db.sales,
        ]) {
          final moved = await db.customWriteReturning(
            'UPDATE ${t.actualTableName} SET customer_id = ?1, '
            'sync_state = ?2, local_version = local_version + 1 '
            'WHERE customer_id = ?3 AND sync_state != ?4 RETURNING id',
            variables: [
              Variable.withString(existingId),
              Variable.withInt(SyncState.pending.index),
              Variable.withString(copyId),
              Variable.withInt(SyncState.synced.index),
            ],
            updates: {t},
          );
          final wire = t == db.sales ? 'sales' : 'transactions';
          for (final row in moved) {
            await _clear(wire, row.read<String>('id'));
          }
        }
        await (db.delete(db.customers)..where(
              (c) =>
                  c.id.equals(copyId) &
                  c.syncState.equalsValue(SyncState.synced).not(),
            ))
            .go();
        await _clear('customers', copyId);
        await db.followSales();
      });

  Future<void> _clear(String table, String id) => (db.delete(
    db.syncIssues,
  )..where((i) => i.recordTable.equals(table) & i.recordId.equals(id))).go();
}
