// A credit sale's debt, as this phone made it, follows its sale through
// every outcome of a sync until the server's own copy replaces it
// (AppDatabase.followSales, docs/10 M4).

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salio/core/database/app_database.dart';
import 'package:salio/core/time/server_clock.dart';
import 'package:salio/features/sales/data/sales_repository.dart';
import 'package:salio/features/sales/domain/sale_debt.dart';

void main() {
  late AppDatabase db;
  late SalesRepository sales;
  const customer = 'c1';

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase(NativeDatabase.memory());
    sales = SalesRepository(db, ServerClock(), 'u1');
    final t = DateTime.utc(2026, 10, 24);
    await db
        .into(db.customers)
        .insert(
          CustomersCompanion.insert(
            id: customer,
            name: 'Otieno',
            createdBy: 'u1',
            createdAt: t,
            updatedAt: t,
            syncState: SyncState.synced,
          ),
        );
  });
  tearDown(() => db.close());

  Future<String> creditSale() => sales.record(
    productName: 'DAP 50kg',
    quantity: 2000,
    amountCents: 700000,
    method: SaleMethod.credit,
    customerId: customer,
  );

  Future<LedgerEntryRow?> debtOf(String saleId) => (db.select(
    db.ledgerEntries,
  )..where((e) => e.id.equals(SaleDebt.idFor(saleId)))).getSingleOrNull();

  Future<void> setSale(String id, SalesCompanion change) =>
      (db.update(db.sales)..where((s) => s.id.equals(id))).write(change);

  test('a cash sale makes no debt', () async {
    final id = await sales.record(
      productName: 'Soap',
      quantity: 1000,
      amountCents: 5000,
      method: SaleMethod.cash,
    );
    expect(await debtOf(id), isNull);
  });

  test('accepted by the server, the debt stops waiting', () async {
    final id = await creditSale();
    expect((await debtOf(id))!.syncState, SyncState.pending);
    await setSale(id, const SalesCompanion(syncState: Value(SyncState.synced)));
    await db.followSales();
    expect((await debtOf(id))!.syncState, SyncState.synced);
  });

  test('refused, the debt shows refused; discarded, it goes', () async {
    final id = await creditSale();
    await setSale(
      id,
      const SalesCompanion(syncState: Value(SyncState.refused)),
    );
    await db.followSales();
    expect((await debtOf(id))!.syncState, SyncState.refused);

    await (db.delete(db.sales)..where((s) => s.id.equals(id))).go();
    await db.followSales();
    expect(await debtOf(id), isNull);
  });

  test('a void the server undid brings the debt back', () async {
    final id = await creditSale();
    await setSale(id, const SalesCompanion(syncState: Value(SyncState.synced)));
    await db.followSales();
    await sales.voidSale(id);
    expect((await debtOf(id))!.isDeleted, isTrue);

    // The server refused the void (not an owner) and its copy came back.
    await setSale(
      id,
      const SalesCompanion(
        isDeleted: Value(false),
        syncState: Value(SyncState.synced),
      ),
    );
    await db.followSales();
    final debt = (await debtOf(id))!;
    expect(debt.isDeleted, isFalse);
    expect(debt.syncState, SyncState.synced);
  });

  test('a sale moved to another customer takes its debt along', () async {
    final id = await creditSale();
    await setSale(id, const SalesCompanion(customerId: Value('c2')));
    await db.followSales();
    expect((await debtOf(id))!.customerId, 'c2');
  });

  test('the server\'s own copy is left alone', () async {
    final id = await creditSale();
    // The server's copy arrived: synced, with its own words.
    await (db.update(
      db.ledgerEntries,
    )..where((e) => e.saleId.equals(id))).write(
      const LedgerEntriesCompanion(
        description: Value('Sale: DAP 50kg x 2'),
        syncState: Value(SyncState.synced),
      ),
    );
    await setSale(id, const SalesCompanion(isDeleted: Value(true)));
    await db.followSales();
    expect(
      (await debtOf(id))!.isDeleted,
      isFalse,
      reason: 'the server voids its own copy, and sends it',
    );
  });
}
