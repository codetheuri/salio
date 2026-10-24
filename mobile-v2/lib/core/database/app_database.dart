import 'package:drift/drift.dart';

import 'app_database.steps.dart';
import 'tables.dart';

export 'tables.dart';

part 'app_database.g.dart';

/// One signed-in account's data. Each account has its own file
/// (`accounts/<user id>.db`), opened by `databaseProvider`.
@DriftDatabase(
  tables: [
    Customers,
    LedgerEntries,
    Sales,
    StockRequests,
    Suppliers,
    SupplierEntries,
    SyncMeta,
    PushBatches,
    SyncIssues,
    ResyncSeen,
    StaffMembers,
    ReportCache,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    // Each step is tested from every older version (test/database/).
    onUpgrade: stepByStep(
      from1To2: (m, schema) async {
        // The other four kinds of record (docs/10, M2).
        await m.createTable(schema.sales);
        await m.createTable(schema.stockRequests);
        await m.createTable(schema.suppliers);
        await m.createTable(schema.supplierEntries);
        await m.createTable(schema.resyncSeen);
        await m.addColumn(schema.syncIssues, schema.syncIssues.serverCopy);
        for (final index in [
          schema.salesCustomer,
          schema.salesSyncState,
          schema.stockRequestsSyncState,
          schema.suppliersSyncState,
          schema.supplierEntriesSupplier,
          schema.supplierEntriesSyncState,
        ]) {
          await m.create(index);
        }
      },
      from2To3: (m, schema) async {
        // Who recorded each entry, by name (docs/10, M3).
        await m.createTable(schema.staffMembers);
      },
      from3To4: (m, schema) async {
        // The last copy of each report, for reading offline (docs/10, M5).
        await m.createTable(schema.reportCache);
      },
    ),
  );

  Future<String?> readMeta(String key) async {
    final row = await (select(
      syncMeta,
    )..where((m) => m.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Future<void> writeMeta(String key, String value) => into(
    syncMeta,
  ).insertOnConflictUpdate(SyncMetaRow(key: key, value: value));

  /// Keeps this phone's copy of each credit sale's debt in step with its
  /// sale (docs/10, M4).
  ///
  /// The phone makes a credit sale's debt itself so the balance moves at
  /// once, but never sends it: the server makes its own from the sale, with
  /// the same id. Until the server's copy replaces it, the phone's copy:
  /// - goes when its sale does (a sale the server refused and the user
  ///   discarded);
  /// - is voided, restored or moved with its sale, as the server would;
  /// - takes the sale's sync state, so a refused sale's debt shows refused,
  ///   and an accepted sale's debt stops waiting: the server now holds the
  ///   same row.
  ///
  /// A debt the server has already sent (synced) is the server's, and is
  /// left alone.
  Future<void> followSales() async {
    const mine = 'sale_id IS NOT NULL AND sync_state != ?1';
    final synced = Variable.withInt(SyncState.synced.index);
    await customUpdate(
      'DELETE FROM ledger_entries WHERE $mine '
      'AND sale_id NOT IN (SELECT id FROM sales)',
      variables: [synced],
      updates: {ledgerEntries},
      updateKind: UpdateKind.delete,
    );
    await customUpdate(
      'UPDATE ledger_entries SET '
      'is_deleted = s.is_deleted, '
      'customer_id = COALESCE(s.customer_id, ledger_entries.customer_id), '
      'sync_state = CASE s.sync_state WHEN ?1 THEN ?1 WHEN ?2 THEN ?2 '
      'ELSE ?3 END '
      'FROM sales s WHERE s.id = ledger_entries.sale_id '
      'AND ledger_entries.sale_id IS NOT NULL '
      'AND ledger_entries.sync_state != ?1 '
      'AND (ledger_entries.is_deleted != s.is_deleted '
      'OR ledger_entries.customer_id != COALESCE(s.customer_id, '
      'ledger_entries.customer_id) '
      'OR ledger_entries.sync_state != CASE s.sync_state WHEN ?1 THEN ?1 '
      'WHEN ?2 THEN ?2 ELSE ?3 END)',
      variables: [
        synced,
        Variable.withInt(SyncState.refused.index),
        Variable.withInt(SyncState.pending.index),
      ],
      updates: {ledgerEntries},
    );
  }
}
