// Every upgrade path between saved schema versions (docs/10, §4.2). The
// helpers in generated/ come from `dart run drift_dev make-migrations`,
// which also adds a case here for each new version; the data checks below
// are written by hand.

import 'package:drift/drift.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salio/core/database/app_database.dart';

import 'generated/schema.dart';
import 'generated/schema_v1.dart' as v1;
import 'generated/schema_v2.dart' as v2;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  group('the schema after each upgrade equals a fresh install', () {
    const versions = GeneratedHelper.versions;
    for (final (i, fromVersion) in versions.indexed) {
      group('from $fromVersion', () {
        for (final toVersion in versions.skip(i + 1)) {
          test('to $toVersion', () async {
            final schema = await verifier.schemaAt(fromVersion);
            final db = AppDatabase(schema.newConnection());
            await verifier.migrateAndValidate(db, toVersion);
            await db.close();
          });
        }
      });
    }
  });

  // What matters most in an upgrade: records not yet sent, a frozen push
  // and the sync position all come through, or the update loses work.
  test('1 to 2 keeps unsent records, the frozen push and the cursor', () async {
    const at = '2026-10-20T08:00:00.000Z';
    const customer = v1.CustomersData(
      id: 'c1',
      createdAt: at,
      updatedAt: at,
      isDeleted: 0,
      syncState: 1,
      localVersion: 2,
      name: 'Wanjiku',
      phone: '0712000001',
      createdBy: 'u1',
      changedFields: 'phone',
    );
    const entry = v1.LedgerEntriesData(
      id: 'e1',
      createdAt: at,
      updatedAt: at,
      isDeleted: 0,
      syncState: 1,
      localVersion: 0,
      customerId: 'c1',
      userId: 'u1',
      type: 'debt',
      amountCents: 150000,
      description: 'DAP 50kg',
      transactionDate: at,
    );
    const cursor = v1.SyncMetaData(key: 'cursor', value: '42');
    const batch = v1.PushBatchesData(
      operationId: 'op1',
      body: '{"operation_id":"op1"}',
      records: '[]',
      createdAt: at,
      attempts: 1,
    );
    const issue = v1.SyncIssuesData(
      id: 1,
      recordTable: 'customers',
      recordId: 'c1',
      reason: 'duplicate',
      createdAt: at,
    );

    await verifier.testWithDataIntegrity(
      oldVersion: 1,
      newVersion: 2,
      createOld: v1.DatabaseAtV1.new,
      createNew: v2.DatabaseAtV2.new,
      openTestedDatabase: AppDatabase.new,
      createItems: (batchOf, old) {
        batchOf.insert(old.customers, customer);
        batchOf.insert(old.ledgerEntries, entry);
        batchOf.insert(old.syncMeta, cursor);
        batchOf.insert(old.pushBatches, batch);
        batchOf.insert(old.syncIssues, issue);
      },
      validateItems: (db) async {
        expect(await db.select(db.customers).get(), [
          v2.CustomersData.fromJson(customer.toJson()),
        ]);
        expect(await db.select(db.ledgerEntries).get(), [
          v2.LedgerEntriesData.fromJson(entry.toJson()),
        ]);
        expect(await db.select(db.syncMeta).get(), [
          v2.SyncMetaData.fromJson(cursor.toJson()),
        ]);
        expect(await db.select(db.pushBatches).get(), [
          v2.PushBatchesData.fromJson(batch.toJson()),
        ]);
        // The new column is empty for issues raised before it existed.
        expect(await db.select(db.syncIssues).get(), [
          v2.SyncIssuesData.fromJson({...issue.toJson(), 'serverCopy': null}),
        ]);
        expect(await db.select(db.sales).get(), isEmpty);
      },
    );
  });
}
