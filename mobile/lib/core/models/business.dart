// lib/core/models/business.dart

/// Represents the central Shop or Retail operation.
class Business {
  final String id;
  final String name;
  final String? type;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Business({
    required this.id,
    required this.name,
    this.type,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Business.fromMap(Map<String, dynamic> map) {
    return Business(
      id: map['id'] as String,
      name: map['name'] as String,
      type: map['type'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'type': type,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  Business copyWith({
    String? id,
    String? name,
    String? type,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Business(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
