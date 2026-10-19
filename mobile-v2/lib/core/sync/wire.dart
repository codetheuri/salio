import 'package:drift/drift.dart';

import '../database/app_database.dart';
import '../money/money.dart';

/// Records as server-v2's sync endpoints send and receive them
/// (`internal/syncengine/dto.go`). Times are UTC ISO-8601; money is a
/// decimal string.
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
}
