// Data and fakes for widget tests: a seeded in-memory database, a fixed
// session, and a network that is always offline.

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:salio/core/database/app_database.dart';
import 'package:salio/core/network/api_client.dart';
import 'package:salio/core/network/api_exception.dart';
import 'package:salio/core/session/account_store.dart';
import 'package:salio/core/session/permissions.dart';
import 'package:salio/core/session/session.dart';
import 'package:salio/core/session/session_controller.dart';
import 'package:salio/features/stock/data/purchase_order_api.dart';

/// A customer the layout tests open, with a long name and a large balance.
const longCustomerId = '0197a000-0000-7000-8000-00000000000a';

/// Their first entry: a long description, overdue, recorded by staff.
const longEntryId = '0197a000-0000-7000-8000-000000000001';

/// The member of staff who recorded it, with a long name.
const staffUserId = '0197a000-0000-7000-8000-0000000000u2';

/// M4: a credit sale to the long customer, a supplier the shop owes, one
/// of their bills, a stock note and a purchase order, all with the longest
/// names and amounts the screens must fit.
const longSaleId = '0197a000-0000-7000-8000-0000000005a1';
const longSupplierId = '0197a000-0000-7000-8000-0000000005b1';
const longSupplierEntryId = '0197a000-0000-7000-8000-0000000005c1';
const longNoteId = '0197a000-0000-7000-8000-0000000005d1';
const longOrderId = '0197a000-0000-7000-8000-0000000005e1';
const longProduct =
    'Duodip pour-on acaricide 20ml for cattle, sheep and goats (orange)';

Session sessionFor(Role role) => Session(
  Account(
    userId: '0197a000-0000-7000-8000-0000000000u1',
    businessId: '0197a000-0000-7000-8000-0000000000b1',
    name: role == Role.owner ? 'Amina Wanjiku Mwangi' : 'Juma Otieno',
    phone: '0712345678',
    role: role,
    businessName: 'Mama Amina General Store and Agrovet',
    lastUsedAt: DateTime.utc(2026, 10, 19),
  ),
  'token',
);

/// A session controller that is already signed in, or signed out.
class FixedSession extends SessionController {
  final Session? session;

  FixedSession(this.session);

  @override
  Future<Session?> build() async => session;

  @override
  Future<void> signOut() async => state = const AsyncData(null);

  @override
  Future<void> endedByServer(String reason) async {
    final current = state.value;
    if (current == null) return;
    state = AsyncData(Session(current.account, null, endedReason: reason));
  }
}

/// An in-memory database with customers whose names and amounts push the
/// layout: very long, very large, zero, an advance, unsent.
Future<AppDatabase> seededDatabase() async {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  // Streams close at once when a screen stops listening, instead of on a
  // timer that a widget test's fake clock would never fire.
  final db = AppDatabase(
    DatabaseConnection(
      NativeDatabase.memory(),
      closeStreamsSynchronously: true,
    ),
  );
  final t = DateTime.utc(2026, 10, 14, 7, 15);
  Future<void> customer(String id, String name, String? phone) => db
      .into(db.customers)
      .insert(
        CustomersCompanion.insert(
          id: id,
          name: name,
          phone: Value(phone),
          createdBy: 'u1',
          createdAt: t,
          updatedAt: t,
          syncState: SyncState.synced,
        ),
      );
  var n = 0;
  Future<void> entry(
    String customerId,
    String type,
    int cents,
    String description, {
    SyncState state = SyncState.synced,
    DateTime? due,
    String userId = 'u1',
  }) => db
      .into(db.ledgerEntries)
      .insert(
        LedgerEntriesCompanion.insert(
          id: '0197a000-0000-7000-8000-${(++n).toString().padLeft(12, '0')}',
          customerId: customerId,
          userId: userId,
          type: type,
          amountCents: cents,
          description: Value(description),
          dueDate: Value(due),
          transactionDate: t.add(Duration(hours: n)),
          createdAt: t,
          updatedAt: t,
          syncState: state,
        ),
      );

  await customer(
    longCustomerId,
    'Bartholomew Kipchumba Arap Kiprotich Wanyonyi',
    '+254712345678',
  );
  await entry(
    longCustomerId,
    'debt',
    123456789,
    'Two bags of fertiliser, three litres of cooking oil and a crate of '
        'sodas, to be paid at the end of the month',
    due: DateTime.utc(2026, 10, 1),
    userId: staffUserId,
  );
  // Over a limit, so the account card shows its longest lines.
  await (db.update(db.customers)..where((c) => c.id.equals(longCustomerId)))
      .write(const CustomersCompanion(creditLimitCents: Value(10000000)));
  await db
      .into(db.staffMembers)
      .insert(
        StaffMembersCompanion.insert(
          id: staffUserId,
          name: 'Wanjiru Nyambura Kamau-Odhiambo',
          role: 'staff',
          isActive: true,
        ),
      );
  await entry(longCustomerId, 'payment', 50000, 'M-Pesa');
  await entry(
    longCustomerId,
    'debt',
    1500,
    'Matches',
    state: SyncState.pending,
  );
  await customer('0197a000-0000-7000-8000-00000000000b', 'Akinyi', null);
  await customer(
    '0197a000-0000-7000-8000-00000000000c',
    'Otieno',
    '+254700111222',
  );
  await entry('0197a000-0000-7000-8000-00000000000c', 'payment', 20000, 'Cash');
  // One issue of each sort the Needs attention screen words differently,
  // on records with the longest names: a refused payment, a duplicate
  // customer the phone can merge, notes the server undid a change, a
  // record waiting for its customer, and one no longer on the phone.
  const duplicate = '0197a000-0000-7000-8000-00000000000d';
  await customer(duplicate, 'Otieno', '+254700111222');
  await (db.update(db.customers)..where((c) => c.id.equals(duplicate))).write(
    const CustomersCompanion(syncState: Value(SyncState.refused)),
  );
  await entry(
    longCustomerId,
    'payment',
    99999999,
    'M-Pesa',
    state: SyncState.refused,
  );
  Future<void> issue(String table, String id, String reason) => db
      .into(db.syncIssues)
      .insert(
        SyncIssuesCompanion.insert(
          recordTable: table,
          recordId: id,
          reason: reason,
          createdAt: t,
        ),
      );
  await issue(
    'transactions',
    '0197a000-0000-7000-8000-${n.toString().padLeft(12, '0')}',
    'duplicate',
  );
  await issue('customers', duplicate, 'duplicate');
  await issue('customers', longCustomerId, 'has_balance');
  await issue(
    'transactions',
    '0197a000-0000-7000-8000-000000000001',
    'forbidden',
  );
  await issue(
    'transactions',
    '0197a000-0000-7000-8000-000000000003',
    'unknown_customer',
  );
  await issue('sales', 'gone', 'invalid');

  for (var i = 0; i < 12; i++) {
    final id =
        '0197a000-0000-7000-8000-0000000001${i.toString().padLeft(2, '0')}';
    await customer(
      id,
      'Customer number $i',
      '+2547000001${i.toString().padLeft(2, '0')}',
    );
    await entry(id, 'debt', 1000 * (i + 1), 'Bread');
  }
  await _seedM4(db);
  return db;
}

/// Sales are dated from now, since the sales list shows the last 30 days.
Future<void> _seedM4(AppDatabase db) async {
  final now = DateTime.now().toUtc();
  var n = 0;
  Future<void> sale(
    String method,
    int cents,
    DateTime at, {
    String? id,
    String? customerId,
    String product = 'Sugar 2kg',
    String? reference,
    bool voided = false,
    SyncState state = SyncState.synced,
    String userId = 'u1',
  }) => db
      .into(db.sales)
      .insert(
        SalesCompanion.insert(
          id:
              id ??
              '0197a000-0000-7000-8000-0000000006${(++n).toString().padLeft(2, '0')}',
          customerId: Value(customerId),
          userId: userId,
          productName: product,
          quantity: 12500,
          amountCents: cents,
          paymentMethod: method,
          reference: Value(reference),
          dueDate: Value(
            method == 'credit' ? DateTime.utc(2026, 12, 31) : null,
          ),
          notes: Value(
            method == 'credit'
                ? 'To be collected by his son on Saturday with the rest'
                : null,
          ),
          saleDate: at,
          createdAt: at,
          updatedAt: at,
          isDeleted: Value(voided),
          syncState: state,
        ),
      );
  await sale(
    'credit',
    987654321,
    now.subtract(const Duration(minutes: 30)),
    id: longSaleId,
    customerId: longCustomerId,
    product: longProduct,
    userId: staffUserId,
  );
  await sale(
    'mpesa',
    150000,
    now.subtract(const Duration(hours: 1)),
    reference: 'SJK4X7Y2PQ',
    customerId: '0197a000-0000-7000-8000-00000000000c',
  );
  await sale(
    'cash',
    25000,
    now.subtract(const Duration(hours: 2)),
    state: SyncState.pending,
  );
  await sale(
    'bank',
    1200000,
    now.subtract(const Duration(hours: 3)),
    reference: 'FT2610240001234',
    voided: true,
  );
  await sale('cash', 9900, now.subtract(const Duration(days: 1, hours: 2)));
  await sale('cash', 4500, now.subtract(const Duration(days: 9)));

  final t = DateTime.utc(2026, 10, 14, 7, 15);
  await db
      .into(db.suppliers)
      .insert(
        SuppliersCompanion.insert(
          id: longSupplierId,
          name: 'Elgon Kenya Agricultural Supplies and Distributors, Ruiru',
          phone: const Value('+254722000111'),
          notes: const Value(
            'Delivers on Tuesdays and Fridays. Ask for Wambui at the counter.',
          ),
          createdBy: 'u1',
          createdAt: t,
          updatedAt: t,
          syncState: SyncState.synced,
        ),
      );
  await db
      .into(db.suppliers)
      .insert(
        SuppliersCompanion.insert(
          id: '0197a000-0000-7000-8000-0000000005b2',
          name: 'Twiga',
          createdBy: 'u1',
          createdAt: t,
          updatedAt: t,
          syncState: SyncState.pending,
        ),
      );
  Future<void> supplierEntry(
    String id,
    String type,
    int cents,
    String description, {
    String? method,
    String? reference,
  }) => db
      .into(db.supplierEntries)
      .insert(
        SupplierEntriesCompanion.insert(
          id: id,
          supplierId: longSupplierId,
          userId: staffUserId,
          type: type,
          amountCents: cents,
          description: description,
          transactionDate: t,
          dueDate: Value(type == 'bill' ? DateTime.utc(2026, 11, 30) : null),
          paymentMethod: Value(method),
          reference: Value(reference),
          createdAt: t,
          updatedAt: t,
          syncState: SyncState.synced,
        ),
      );
  await supplierEntry(
    longSupplierEntryId,
    'bill',
    876543210,
    'Invoice 4471: 20 bags of DAP 50kg, 12 cartons of Duodip 20ml and '
        '6 knapsack sprayers, delivered to the back store',
  );
  await supplierEntry(
    '0197a000-0000-7000-8000-0000000005c2',
    'payment',
    50000000,
    'Part payment for invoice 4471',
    method: 'mpesa',
    reference: 'SJK4X7Y2PQ',
  );

  Future<void> note(String id, String product, {String? orderId}) => db
      .into(db.stockRequests)
      .insert(
        StockRequestsCompanion.insert(
          id: id,
          userId: staffUserId,
          productName: product,
          neededOn: DateTime.utc(2026, 10, 12),
          notes: const Value('Customers asking for it every day this week'),
          purchaseOrderId: Value(orderId),
          createdAt: t,
          updatedAt: t,
          syncState: SyncState.synced,
        ),
      );
  await note(longNoteId, longProduct);
  await note('0197a000-0000-7000-8000-0000000005d2', 'Omo 500g');
  await note(
    '0197a000-0000-7000-8000-0000000005d3',
    'DAP 50kg',
    orderId: longOrderId,
  );
}

/// Purchase orders as the server would answer, without a server: the
/// harness is offline. Records what was placed and cancelled.
class FakePurchaseOrderApi extends PurchaseOrderApi {
  final placed = <String>[];
  final cancelled = <String>[];

  /// When set, every call fails with it, as with no signal.
  ApiException? failure;

  FakePurchaseOrderApi()
    : super(
        ApiClient(
          origin: Uri.parse('http://offline.invalid'),
          token: () => null,
          appHeader: 'test',
          adapter: OfflineAdapter(),
        ),
      );

  static final longOrder = PurchaseOrder(
    id: longOrderId,
    reference: 'PO-0107',
    supplierName: 'Elgon Kenya Agricultural Supplies and Distributors, Ruiru',
    supplierPhone: '+254722000111',
    notes: 'Deliver to the back store before noon, and call Amina on arrival',
    cancelled: false,
    orderedOn: DateTime.utc(2026, 10, 14),
    lines: const [
      OrderLine(productName: longProduct, quantity: 1250000),
      OrderLine(productName: 'DAP 50kg', quantity: 20000, stockRequestId: 'x'),
    ],
  );

  final _orders = <PurchaseOrder>[
    longOrder,
    PurchaseOrder(
      id: '0197a000-0000-7000-8000-0000000005e2',
      reference: 'PO-0106',
      supplierName: 'Twiga',
      cancelled: true,
      orderedOn: DateTime.utc(2026, 10, 2),
      lines: const [OrderLine(productName: 'Omo 500g', quantity: 24000)],
    ),
  ];

  void _check() {
    final f = failure;
    if (f != null) throw f;
  }

  @override
  Future<List<PurchaseOrder>> list() async {
    _check();
    return List.of(_orders);
  }

  @override
  Future<PurchaseOrder> get(String id) async {
    _check();
    return _orders.firstWhere(
      (o) => o.id == id,
      orElse: () => throw const ApiException(ApiFailure.notFound),
    );
  }

  @override
  Future<PurchaseOrder> place({
    required String id,
    required String supplierName,
    String supplierPhone = '',
    String notes = '',
    required List<OrderLine> lines,
  }) async {
    placed.add(id);
    _check();
    final existing = _orders.where((o) => o.id == id).firstOrNull;
    if (existing != null) return existing;
    final order = PurchaseOrder(
      id: id,
      reference: 'PO-${(108 + _orders.length).toString().padLeft(4, '0')}',
      supplierName: supplierName.trim(),
      cancelled: false,
      orderedOn: DateTime.utc(2026, 10, 24),
      lines: lines,
    );
    _orders.insert(0, order);
    return order;
  }

  @override
  Future<void> cancel(String id) async {
    cancelled.add(id);
    _check();
  }

  @override
  Future<List<int>> pdf(String id) async {
    _check();
    return '%PDF-1.4 test'.codeUnits;
  }
}

/// No network: every request fails as it does with no signal.
class OfflineAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) => throw DioException.connectionError(
    requestOptions: options,
    reason: 'offline in tests',
  );

  @override
  void close({bool force = false}) {}
}
