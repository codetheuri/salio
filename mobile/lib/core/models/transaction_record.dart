// lib/core/models/transaction_record.dart

/// Represents a single debt or payment.
/// Note: We name it TransactionRecord because "Transaction" is a reserved 
/// word in sqflite (used for database transactions). 
/// Naming collisions are a common cause of hard-to-find bugs.
class TransactionRecord {
  final String id;
  final String businessId; // Crucial for multi-tenant isolation
  final String customerId; // Which customer does this apply to?
  final String userId;     // Which staff member recorded this?
  final String type;       // 'debt' or 'payment'
  final double amount;
  final String? description;
  final String transactionDate; // yyyy-MM-dd
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isDeleted;

  const TransactionRecord({
    required this.id,
    required this.businessId,
    required this.customerId,
    required this.userId,
    required this.type,
    required this.amount,
    this.description,
    required this.transactionDate,
    required this.createdAt,
    required this.updatedAt,
    this.isDeleted = false,
  });

  factory TransactionRecord.fromMap(Map<String, dynamic> map) {
    // Gracefully handle SQLite (int) and JSON API (bool)
    final isDelRaw = map['is_deleted'];
    bool isDel = false;
    if (isDelRaw is bool) {
      isDel = isDelRaw;
    } else if (isDelRaw is int) {
      isDel = isDelRaw == 1;
    }

    return TransactionRecord(
      id: map['id'] as String,
      businessId: map['business_id'] as String,
      customerId: map['customer_id'] as String,
      userId: map['user_id'] as String,
      type: map['type'] as String,
      // SQLite stores reals, but we cast to num first to safely handle ints or doubles
      amount: (map['amount'] as num).toDouble(), 
      description: map['description'] as String?,
      transactionDate: map['transaction_date'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      isDeleted: isDel,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'business_id': businessId,
      'customer_id': customerId,
      'user_id': userId,
      'type': type,
      'amount': amount,
      'description': description,
      'transaction_date': transactionDate,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'is_deleted': isDeleted ? 1 : 0, // SQLite needs 0 or 1
    };
  }

  Map<String, dynamic> toJsonMap() {
    return {
      'id': id,
      'business_id': businessId,
      'customer_id': customerId,
      'user_id': userId,
      'type': type,
      'amount': amount,
      'description': description,
      'transaction_date': transactionDate,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'is_deleted': isDeleted, // Go API needs true or false
    };
  }
}
