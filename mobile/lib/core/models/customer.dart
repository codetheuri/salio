// lib/core/models/customer.dart

/// Represents a buyer who owes money to the Business.
class Customer {
  final String id;
  final String businessId; // Crucial for multi-tenant isolation
  final String name;
  final String? phone;
  final String? notes;
  final String createdBy; // The ID of the User who added them
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isDeleted;

  const Customer({
    required this.id,
    required this.businessId,
    required this.name,
    this.phone,
    this.notes,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    this.isDeleted = false,
  });

  factory Customer.fromMap(Map<String, dynamic> map) {
    // Gracefully handle SQLite (int) and JSON API (bool)
    final isDelRaw = map['is_deleted'];
    bool isDel = false;
    if (isDelRaw is bool) {
      isDel = isDelRaw;
    } else if (isDelRaw is int) {
      isDel = isDelRaw == 1;
    }

    return Customer(
      id: map['id'] as String,
      businessId: map['business_id'] as String,
      name: map['name'] as String,
      phone: map['phone'] as String?,
      notes: map['notes'] as String?,
      createdBy: map['created_by'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      isDeleted: isDel,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'business_id': businessId,
      'name': name,
      'phone': phone,
      'notes': notes,
      'created_by': createdBy,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'is_deleted': isDeleted ? 1 : 0, // SQLite needs 0 or 1
    };
  }

  Map<String, dynamic> toJsonMap() {
    return {
      'id': id,
      'business_id': businessId,
      'name': name,
      'phone': phone,
      'notes': notes,
      'created_by': createdBy,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'is_deleted': isDeleted, // Go API needs true or false
    };
  }

  Customer copyWith({
    String? id,
    String? businessId,
    String? name,
    String? phone,
    String? notes,
    String? createdBy,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isDeleted,
  }) {
    return Customer(
      id: id ?? this.id,
      businessId: businessId ?? this.businessId,
      name: name ?? this.name,
      phone: phone ?? this.phone, // Note: this doesn't clear phone if null is passed, but works for our simple edit case
      notes: notes ?? this.notes,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }
}

/// A Data Transfer Object (DTO) specifically for our Dashboard view 
/// so we don't have to calculate balance manually in the UI layer.
class CustomerWithBalance {
  final Customer customer;
  final double balance;

  const CustomerWithBalance({
    required this.customer,
    required this.balance,
  });
}
