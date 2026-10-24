import 'package:drift/drift.dart';

import '../database/app_database.dart';
import 'wire.dart';

/// One kind of synced record, as the sync engine moves it: its table, how
/// it travels, and what happens when the server's copy meets a change this
/// phone has not sent yet.
///
/// The engine itself is written once for all six; what differs between
/// them is here.
class SyncKind<D extends DataClass> {
  /// The name in push and pull bodies and in conflicts: `customers`,
  /// `transactions`, …
  final String wire;
  final TableInfo<Table, D> Function(AppDatabase db) table;

  /// A record from the server, as a synced row. Its local version is left
  /// out, so storing it over an existing row keeps that row's.
  final Insertable<D> Function(Map<String, dynamic> json) decode;

  /// Records the others point to. Every pending one goes before any record
  /// of the other kinds, so nothing reaches the server ahead of what it
  /// points to.
  final bool isParent;

  /// The column naming the parent, and the parent's kind: a record refused
  /// because the server lacked its parent waits until the parent is in.
  final ({String column, String kind, String reason})? parent;

  /// An SQL condition for pending records this phone never sends.
  final String? neverSent;

  /// Extra `SET` clauses when a version is accepted.
  final String onAccepted;

  /// Pending records go oldest first by this column.
  final String sendOrder;

  // Private, and reached through the methods below, which take any row:
  // the list of kinds is typed `SyncKind<DataClass>`, and reading a field
  // whose function type takes a `D` through that type fails at run time.
  final String Function(D row) _id;
  final int Function(D row) _version;
  final Map<String, Object?> Function(D row) _encode;
  final Insertable<D>? Function(D local, Map<String, dynamic> server)? _merge;

  SyncKind({
    required this.wire,
    required this.table,
    required this._id,
    required this._version,
    required this._encode,
    required this.decode,
    Insertable<D>? Function(D local, Map<String, dynamic> server)? mergePending,
    this.isParent = false,
    this.parent,
    this.neverSent,
    this.onAccepted = '',
    this.sendOrder = 'created_at',
  }) : _merge = mergePending;

  String tableName(AppDatabase db) => table(db).actualTableName;

  Future<D> read(AppDatabase db, Map<String, dynamic> data) async =>
      table(db).map(data);

  String idOf(DataClass row) => _id(row as D);
  int versionOf(DataClass row) => _version(row as D);
  Map<String, Object?> encodeRow(DataClass row) => _encode(row as D);

  /// The server's copy arriving for a record still pending here. Returns
  /// the row to store, or null to keep this phone's as it is until it is
  /// pushed.
  Insertable<D>? mergePending(DataClass local, Map<String, dynamic> server) =>
      _merge?.call(local as D, server);
}

/// The six kinds, in the order a push sends them: parents first.
final syncKinds = <SyncKind<DataClass>>[
  SyncKind<CustomerRow>(
    wire: 'customers',
    table: (db) => db.customers,
    id: (r) => r.id,
    version: (r) => r.localVersion,
    encode: Wire.customer,
    decode: Wire.customerFromServer,
    mergePending: (local, server) =>
        mergeCustomer(local, Wire.customerFromServer(server)),
    isParent: true,
    onAccepted: ", changed_fields = ''",
    sendOrder: 'updated_at',
  ),
  SyncKind<SupplierRow>(
    wire: 'suppliers',
    table: (db) => db.suppliers,
    id: (r) => r.id,
    version: (r) => r.localVersion,
    encode: Wire.supplier,
    decode: Wire.supplierFromServer,
    isParent: true,
    sendOrder: 'updated_at',
  ),
  SyncKind<SaleRow>(
    wire: 'sales',
    table: (db) => db.sales,
    id: (r) => r.id,
    version: (r) => r.localVersion,
    encode: Wire.sale,
    decode: Wire.saleFromServer,
    parent: (
      column: 'customer_id',
      kind: 'customers',
      reason: 'unknown_customer',
    ),
  ),
  SyncKind<LedgerEntryRow>(
    wire: 'transactions',
    table: (db) => db.ledgerEntries,
    id: (r) => r.id,
    version: (r) => r.localVersion,
    encode: Wire.entry,
    decode: Wire.entryFromServer,
    parent: (
      column: 'customer_id',
      kind: 'customers',
      reason: 'unknown_customer',
    ),
    // A credit sale's debt belongs to the server, which makes it from the
    // sale; the phone never sends it.
    neverSent: 'sale_id IS NOT NULL',
  ),
  SyncKind<SupplierEntryRow>(
    wire: 'supplier_transactions',
    table: (db) => db.supplierEntries,
    id: (r) => r.id,
    version: (r) => r.localVersion,
    encode: Wire.supplierEntry,
    decode: Wire.supplierEntryFromServer,
    parent: (
      column: 'supplier_id',
      kind: 'suppliers',
      reason: 'unknown_supplier',
    ),
  ),
  SyncKind<StockRequestRow>(
    wire: 'stock_requests',
    table: (db) => db.stockRequests,
    id: (r) => r.id,
    version: (r) => r.localVersion,
    encode: Wire.stockRequest,
    decode: Wire.stockRequestFromServer,
    sendOrder: 'updated_at',
  ),
];

SyncKind<DataClass> syncKind(String wire) =>
    syncKinds.firstWhere((k) => k.wire == wire);

/// A customer pending on this phone, updated from the server's copy: the
/// fields this phone edited keep its values, the rest take the server's.
/// A new record not yet accepted keeps all of its own.
CustomersCompanion mergeCustomer(CustomerRow local, CustomersCompanion server) {
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
