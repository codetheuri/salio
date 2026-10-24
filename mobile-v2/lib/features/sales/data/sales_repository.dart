import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/time/server_clock.dart';
import '../../ledger/domain/payment_reference.dart';
import '../domain/sale_debt.dart';

/// How a sale was paid. Credit puts the amount on a customer's account.
enum SaleMethod {
  cash,
  mpesa,
  bank,
  credit;

  /// The server's name for it (`payment_method`).
  String get wire => name;

  /// The payment method whose reference rule applies; none for credit.
  PaymentMethod? get payment => switch (this) {
    cash => PaymentMethod.cash,
    mpesa => PaymentMethod.mpesa,
    bank => PaymentMethod.bank,
    credit => null,
  };

  static SaleMethod of(String wire) => SaleMethod.values.byName(wire);
}

/// A sale with the name of the customer it was for, if any.
class SaleWithCustomer {
  final SaleRow sale;
  final String? customerName;

  const SaleWithCustomer(this.sale, this.customerName);
}

/// Reads and records sales. A sale is never edited: a mistake is voided
/// and sold again (domain invariant 2).
class SalesRepository {
  final AppDatabase db;
  final ServerClock clock;

  /// Who is signed in: the sale's `user_id`.
  final String userId;

  SalesRepository(this.db, this.clock, this.userId);

  /// Records a sale on this phone, dated by the server's clock, and returns
  /// its id. The checks are the server's (`sales.Validate`), so a sale the
  /// form lets through is not refused on sync:
  /// - a product, a quantity and an amount above zero;
  /// - a credit sale needs a customer, may have a due date, and has no
  ///   reference;
  /// - any other sale has no due date, and its reference follows the
  ///   payment rule.
  ///
  /// A credit sale also puts its debt on the customer's account at once,
  /// with the id and words the server will give it ([SaleDebt]).
  Future<String> record({
    required String productName,
    required int quantity,
    required int amountCents,
    required SaleMethod method,
    String? customerId,
    String reference = '',
    DateTime? dueDate,
    String notes = '',
  }) {
    final product = productName.trim();
    if (product.isEmpty) {
      throw ArgumentError.value(productName, 'productName', 'is required');
    }
    if (quantity <= 0) {
      throw ArgumentError.value(quantity, 'quantity', 'must be above 0');
    }
    if (amountCents <= 0) {
      throw ArgumentError.value(amountCents, 'amountCents', 'must be above 0');
    }
    final credit = method == SaleMethod.credit;
    if (credit && customerId == null) {
      throw ArgumentError.value(customerId, 'customerId', 'credit needs one');
    }
    if (!credit && dueDate != null) {
      throw ArgumentError.value(dueDate, 'dueDate', 'only on credit');
    }
    String? stored;
    if (!credit) {
      final ref = PaymentReference.check(method.payment!, reference);
      if (ref.problem != null) {
        throw ArgumentError.value(reference, 'reference', ref.problem!.name);
      }
      stored = ref.stored;
    }
    final due = dueDate == null
        ? null
        : DateTime.utc(dueDate.year, dueDate.month, dueDate.day);

    return db.transaction(() async {
      final now = clock.now();
      final id = const Uuid().v7();
      await db
          .into(db.sales)
          .insert(
            SalesCompanion.insert(
              id: id,
              customerId: Value(customerId),
              userId: userId,
              productName: product,
              quantity: quantity,
              amountCents: amountCents,
              paymentMethod: method.wire,
              reference: Value(stored),
              dueDate: Value(due),
              notes: Value(notes.trim().isEmpty ? null : notes.trim()),
              saleDate: now,
              createdAt: now,
              updatedAt: now,
              syncState: SyncState.pending,
            ),
          );
      if (credit) {
        await db
            .into(db.ledgerEntries)
            .insert(
              LedgerEntriesCompanion.insert(
                id: SaleDebt.idFor(id),
                customerId: customerId!,
                userId: userId,
                type: 'debt',
                amountCents: amountCents,
                description: Value(SaleDebt.description(product, quantity)),
                transactionDate: now,
                createdAt: now,
                updatedAt: now,
                dueDate: Value(due),
                saleId: Value(id),
                syncState: SyncState.pending,
              ),
            );
      }
      return id;
    });
  }

  /// Voids a sale (owners; the server refuses anyone else), and with it
  /// the debt a credit sale put on the customer, as the server does. The
  /// sale stays in the list, crossed out.
  Future<void> voidSale(String id) => db.transaction(() async {
    final sale = await (db.select(
      db.sales,
    )..where((s) => s.id.equals(id))).getSingle();
    if (sale.isDeleted) return;
    final now = clock.now();
    await (db.update(db.sales)..where((s) => s.id.equals(id))).write(
      SalesCompanion(
        isDeleted: const Value(true),
        updatedAt: Value(now),
        syncState: const Value(SyncState.pending),
        localVersion: Value(sale.localVersion + 1),
      ),
    );
    // The debt is the server's to void; this phone's copy goes now so the
    // balance is right offline, and the server's arrives on the next pull.
    await (db.update(
      db.ledgerEntries,
    )..where((e) => e.saleId.equals(id))).write(
      LedgerEntriesCompanion(
        isDeleted: const Value(true),
        updatedAt: Value(now),
        syncState: const Value(SyncState.pending),
      ),
    );
  });

  /// Sales from [since] on, newest first, voided ones included, each with
  /// its customer's name.
  Stream<List<SaleWithCustomer>> watchSince(DateTime since) {
    final q =
        db.select(db.sales).join([
            leftOuterJoin(
              db.customers,
              db.customers.id.equalsExp(db.sales.customerId),
            ),
          ])
          ..where(db.sales.saleDate.isBiggerOrEqualValue(since))
          ..orderBy([
            OrderingTerm.desc(db.sales.saleDate),
            OrderingTerm.desc(db.sales.createdAt),
          ]);
    return q.watch().map(
      (rows) => [
        for (final r in rows)
          SaleWithCustomer(
            r.readTable(db.sales),
            r.readTableOrNull(db.customers)?.name,
          ),
      ],
    );
  }

  Stream<SaleWithCustomer?> watchSale(String id) {
    final q = db.select(db.sales).join([
      leftOuterJoin(
        db.customers,
        db.customers.id.equalsExp(db.sales.customerId),
      ),
    ])..where(db.sales.id.equals(id));
    return q.watchSingleOrNull().map(
      (r) => r == null
          ? null
          : SaleWithCustomer(
              r.readTable(db.sales),
              r.readTableOrNull(db.customers)?.name,
            ),
    );
  }

  /// Products this shop has sold, most recent first, for the product box
  /// to suggest: spelt the same way every time, reports group cleanly.
  Future<List<String>> recentProducts({int limit = 200}) async {
    final rows = await db
        .customSelect(
          'SELECT product_name, MAX(sale_date) AS last FROM sales '
          'WHERE is_deleted = 0 GROUP BY product_name '
          'ORDER BY last DESC LIMIT ?1',
          variables: [Variable.withInt(limit)],
          readsFrom: {db.sales},
        )
        .get();
    return [for (final r in rows) r.read<String>('product_name')];
  }
}
