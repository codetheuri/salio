import 'package:drift/drift.dart';

import 'tables.dart';

export 'tables.dart';

part 'app_database.g.dart';

/// One signed-in account's data. Each account has its own file
/// (`accounts/<user id>.db`), opened by `databaseProvider`.
@DriftDatabase(
  tables: [Customers, LedgerEntries, SyncMeta, PushBatches, SyncIssues],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      // The lists filter on these, and sync looks up pending rows.
      await customStatement(
        'CREATE INDEX ledger_entries_customer ON ledger_entries (customer_id, is_deleted)',
      );
      await customStatement(
        'CREATE INDEX customers_sync_state ON customers (sync_state)',
      );
      await customStatement(
        'CREATE INDEX ledger_entries_sync_state ON ledger_entries (sync_state)',
      );
    },
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
