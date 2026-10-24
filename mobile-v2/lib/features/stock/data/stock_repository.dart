import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/time/server_clock.dart';
import '../../../core/time/shop_time.dart';

/// Stock notes: "Duodip 20ml ran out". Noted offline the moment somebody
/// sees an empty shelf, and synced like a debt. A note not yet on a
/// purchase order may be edited or removed; once ordered, only cancelling
/// the order frees it (the server's `stock.CheckEditable`).
class StockRepository {
  final AppDatabase db;
  final ServerClock clock;
  final ShopTime shopTime;
  final String userId;

  StockRepository(this.db, this.clock, this.shopTime, this.userId);

  /// Notes not yet on an order: the shop's draft order, oldest first, so
  /// what ran out first is ordered first.
  Stream<List<StockRequestRow>> watchToOrder() =>
      (db.select(db.stockRequests)
            ..where((r) => r.isDeleted.not() & r.purchaseOrderId.isNull())
            ..orderBy([
              (r) => OrderingTerm.asc(r.neededOn),
              (r) => OrderingTerm.asc(r.createdAt),
            ]))
          .watch();

  Stream<StockRequestRow?> watchNote(String id) => (db.select(
    db.stockRequests,
  )..where((r) => r.id.equals(id))).watchSingleOrNull();

  /// Notes a product that ran out [neededOn]: the shop's today when not
  /// given, by the server's clock. Returns its id.
  Future<String> add({
    required String productName,
    DateTime? neededOn,
    String notes = '',
  }) async {
    final product = _product(productName);
    final now = clock.now();
    final id = const Uuid().v7();
    await db
        .into(db.stockRequests)
        .insert(
          StockRequestsCompanion.insert(
            id: id,
            userId: userId,
            productName: product,
            neededOn: neededOn == null ? shopTime.day(now) : _day(neededOn),
            notes: Value(notes.trim().isEmpty ? null : notes.trim()),
            createdAt: now,
            updatedAt: now,
            syncState: SyncState.pending,
          ),
        );
    return id;
  }

  /// Changes a note that is not on an order.
  Future<void> update(
    String id, {
    required String productName,
    required DateTime neededOn,
    String notes = '',
  }) => _change(
    id,
    StockRequestsCompanion(
      productName: Value(_product(productName)),
      neededOn: Value(_day(neededOn)),
      notes: Value(notes.trim().isEmpty ? null : notes.trim()),
    ),
  );

  /// Removes a note that is not on an order: a tombstone, so the removal
  /// reaches every phone (domain invariant 4).
  Future<void> remove(String id) =>
      _change(id, const StockRequestsCompanion(isDeleted: Value(true)));

  Future<void> _change(String id, StockRequestsCompanion change) =>
      db.transaction(() async {
        final row = await (db.select(
          db.stockRequests,
        )..where((r) => r.id.equals(id))).getSingle();
        if (row.purchaseOrderId != null) {
          throw StateError('a note on a purchase order cannot change');
        }
        await (db.update(
          db.stockRequests,
        )..where((r) => r.id.equals(id))).write(
          change.copyWith(
            updatedAt: Value(clock.now()),
            syncState: const Value(SyncState.pending),
            localVersion: Value(row.localVersion + 1),
          ),
        );
      });

  static String _product(String name) {
    final t = name.trim();
    if (t.isEmpty) throw ArgumentError.value(name, 'productName', 'required');
    return t;
  }

  /// A calendar day, held as UTC midnight, as due dates are.
  static DateTime _day(DateTime d) => DateTime.utc(d.year, d.month, d.day);
}
