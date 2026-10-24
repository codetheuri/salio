import 'package:drift/drift.dart';

import '../database/app_database.dart';
import '../money/money.dart';
import '../quantity/quantity.dart';

/// Records as server-v2's sync endpoints send and receive them
/// (`internal/syncengine/dto.go`). Times are UTC ISO-8601; money and
/// quantities are decimal strings.
///
/// Reading is forgiving in the same way the server is (B14): fields this
/// app does not know are ignored, so a newer server can add one without
/// breaking older phones.
abstract final class Wire {
  static String time(DateTime t) => t.toUtc().toIso8601String();

  static DateTime parseTime(Object? v) => DateTime.parse(v! as String).toUtc();

  static DateTime? parseTimeOrNull(Object? v) =>
      v == null ? null : parseTime(v);

  /// Customer fields a push can name in `changed_fields`.
  static const customerFields = {
    'name',
    'phone',
    'notes',
    'is_deleted',
    'credit_limit',
  };

  static Map<String, Object?> customer(CustomerRow c) {
    final changed = c.changedFields.isEmpty
        ? const <String>[]
        : c.changedFields.split(',');
    return {
      'id': c.id,
      'name': c.name,
      'phone': ?c.phone,
      'notes': ?c.notes,
      'created_by': c.createdBy,
      'created_at': time(c.createdAt),
      'updated_at': time(c.updatedAt),
      'is_deleted': c.isDeleted,
      // Empty means a new record: the whole of it is this phone's.
      if (changed.isNotEmpty) 'changed_fields': changed,
      // Sent only when this phone changed it, so a push can never clear a
      // limit the owner set elsewhere.
      if (changed.contains('credit_limit'))
        'credit_limit': c.creditLimitCents == null
            ? null
            : Money.toWire(c.creditLimitCents!),
    };
  }

  static Map<String, Object?> entry(LedgerEntryRow e) => {
    'id': e.id,
    'customer_id': e.customerId,
    'user_id': e.userId,
    'type': e.type,
    'amount': Money.toWire(e.amountCents),
    'description': ?e.description,
    'transaction_date': time(e.transactionDate),
    'created_at': time(e.createdAt),
    'updated_at': time(e.updatedAt),
    'is_deleted': e.isDeleted,
    'payment_method': ?e.paymentMethod,
    'reference': ?e.reference,
    if (e.dueDate != null) 'due_date': time(e.dueDate!),
  };

  /// A pulled customer, as a synced row.
  static CustomersCompanion customerFromServer(Map<String, dynamic> j) =>
      CustomersCompanion.insert(
        id: j['id'] as String,
        name: j['name'] as String,
        phone: Value(j['phone'] as String?),
        notes: Value(j['notes'] as String?),
        createdBy: j['created_by'] as String,
        createdAt: parseTime(j['created_at']),
        updatedAt: parseTime(j['updated_at']),
        isDeleted: Value(j['is_deleted'] as bool? ?? false),
        creditLimitCents: Value(
          j['credit_limit'] == null
              ? null
              : Money.parse(j['credit_limit'] as String),
        ),
        syncState: SyncState.synced,
      );

  /// A pulled ledger entry, as a synced row.
  static LedgerEntriesCompanion entryFromServer(Map<String, dynamic> j) =>
      LedgerEntriesCompanion.insert(
        id: j['id'] as String,
        customerId: j['customer_id'] as String,
        userId: j['user_id'] as String,
        type: j['type'] as String,
        amountCents: Money.parse(j['amount'] as String),
        description: Value(j['description'] as String?),
        transactionDate: parseTime(j['transaction_date']),
        createdAt: parseTime(j['created_at']),
        updatedAt: parseTime(j['updated_at']),
        isDeleted: Value(j['is_deleted'] as bool? ?? false),
        paymentMethod: Value(j['payment_method'] as String?),
        reference: Value(j['reference'] as String?),
        dueDate: Value(parseTimeOrNull(j['due_date'])),
        saleId: Value(j['sale_id'] as String?),
        syncState: SyncState.synced,
      );

  static Map<String, Object?> sale(SaleRow s) => {
    'id': s.id,
    'customer_id': ?s.customerId,
    'user_id': s.userId,
    'product_name': s.productName,
    'quantity': Quantity.toWire(s.quantity),
    'amount': Money.toWire(s.amountCents),
    'payment_method': s.paymentMethod,
    'reference': ?s.reference,
    if (s.dueDate != null) 'due_date': time(s.dueDate!),
    'notes': ?s.notes,
    'sale_date': time(s.saleDate),
    'created_at': time(s.createdAt),
    'updated_at': time(s.updatedAt),
    'is_deleted': s.isDeleted,
  };

  /// A stock note. Its purchase order is the server's to set, so it is
  /// never sent.
  static Map<String, Object?> stockRequest(StockRequestRow r) => {
    'id': r.id,
    'user_id': r.userId,
    'product_name': r.productName,
    'needed_on': time(r.neededOn),
    'notes': ?r.notes,
    'created_at': time(r.createdAt),
    'updated_at': time(r.updatedAt),
    'is_deleted': r.isDeleted,
  };

  static Map<String, Object?> supplier(SupplierRow s) => {
    'id': s.id,
    'name': s.name,
    'phone': ?s.phone,
    'notes': ?s.notes,
    'created_by': s.createdBy,
    'created_at': time(s.createdAt),
    'updated_at': time(s.updatedAt),
    'is_deleted': s.isDeleted,
  };

  static Map<String, Object?> supplierEntry(SupplierEntryRow e) => {
    'id': e.id,
    'supplier_id': e.supplierId,
    'user_id': e.userId,
    'type': e.type,
    'amount': Money.toWire(e.amountCents),
    'description': e.description,
    'transaction_date': time(e.transactionDate),
    if (e.dueDate != null) 'due_date': time(e.dueDate!),
    'payment_method': ?e.paymentMethod,
    'reference': ?e.reference,
    'created_at': time(e.createdAt),
    'updated_at': time(e.updatedAt),
    'is_deleted': e.isDeleted,
  };

  static SalesCompanion saleFromServer(Map<String, dynamic> j) =>
      SalesCompanion.insert(
        id: j['id'] as String,
        customerId: Value(j['customer_id'] as String?),
        userId: j['user_id'] as String,
        productName: j['product_name'] as String,
        quantity: Quantity.parse(j['quantity'] as String),
        amountCents: Money.parse(j['amount'] as String),
        paymentMethod: j['payment_method'] as String,
        reference: Value(j['reference'] as String?),
        dueDate: Value(parseTimeOrNull(j['due_date'])),
        notes: Value(j['notes'] as String?),
        saleDate: parseTime(j['sale_date']),
        createdAt: parseTime(j['created_at']),
        updatedAt: parseTime(j['updated_at']),
        isDeleted: Value(j['is_deleted'] as bool? ?? false),
        syncState: SyncState.synced,
      );

  static StockRequestsCompanion stockRequestFromServer(
    Map<String, dynamic> j,
  ) => StockRequestsCompanion.insert(
    id: j['id'] as String,
    userId: j['user_id'] as String,
    productName: j['product_name'] as String,
    neededOn: parseTime(j['needed_on']),
    notes: Value(j['notes'] as String?),
    purchaseOrderId: Value(j['purchase_order_id'] as String?),
    createdAt: parseTime(j['created_at']),
    updatedAt: parseTime(j['updated_at']),
    isDeleted: Value(j['is_deleted'] as bool? ?? false),
    syncState: SyncState.synced,
  );

  static SuppliersCompanion supplierFromServer(Map<String, dynamic> j) =>
      SuppliersCompanion.insert(
        id: j['id'] as String,
        name: j['name'] as String,
        phone: Value(j['phone'] as String?),
        notes: Value(j['notes'] as String?),
        createdBy: j['created_by'] as String,
        createdAt: parseTime(j['created_at']),
        updatedAt: parseTime(j['updated_at']),
        isDeleted: Value(j['is_deleted'] as bool? ?? false),
        syncState: SyncState.synced,
      );

  static SupplierEntriesCompanion supplierEntryFromServer(
    Map<String, dynamic> j,
  ) => SupplierEntriesCompanion.insert(
    id: j['id'] as String,
    supplierId: j['supplier_id'] as String,
    userId: j['user_id'] as String,
    type: j['type'] as String,
    amountCents: Money.parse(j['amount'] as String),
    description: j['description'] as String? ?? '',
    transactionDate: parseTime(j['transaction_date']),
    dueDate: Value(parseTimeOrNull(j['due_date'])),
    paymentMethod: Value(j['payment_method'] as String?),
    reference: Value(j['reference'] as String?),
    purchaseOrderId: Value(j['purchase_order_id'] as String?),
    createdAt: parseTime(j['created_at']),
    updatedAt: parseTime(j['updated_at']),
    isDeleted: Value(j['is_deleted'] as bool? ?? false),
    syncState: SyncState.synced,
  );
}
