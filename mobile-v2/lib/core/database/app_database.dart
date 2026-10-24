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
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  @override
  int get schemaVersion => 3;

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
}
