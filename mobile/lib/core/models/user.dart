// lib/core/models/user.dart

/// Represents a staff member or owner who logs into the app.
class User {
  final String id;
  final String businessId; // The shop this user belongs to
  final String name;
  final String? phone;
  final String role; // 'owner' or 'staff'
  final DateTime createdAt;
  final DateTime updatedAt;

  const User({
    required this.id,
    required this.businessId,
    required this.name,
    this.phone,
    required this.role,
    required this.createdAt,
    required this.updatedAt,
  });

  factory User.fromMap(Map<String, dynamic> map) {
    return User(
      id: map['id'] as String,
      businessId: map['business_id'] as String,
      name: map['name'] as String,
      phone: map['phone'] as String?,
      role: map['role'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'business_id': businessId,
      'name': name,
      'phone': phone,
      'role': role,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}
