import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;

import 'permissions.dart';

/// An account that has signed in on this phone.
class Account {
  final String userId;
  final String businessId;
  final String name;
  final String phone;
  final Role role;

  /// Null until the business has been read once from the server.
  final String? businessName;
  final DateTime lastUsedAt;

  const Account({
    required this.userId,
    required this.businessId,
    required this.name,
    required this.phone,
    required this.role,
    required this.lastUsedAt,
    this.businessName,
  });

  Account copyWith({String? businessName, DateTime? lastUsedAt}) => Account(
    userId: userId,
    businessId: businessId,
    name: name,
    phone: phone,
    role: role,
    businessName: businessName ?? this.businessName,
    lastUsedAt: lastUsedAt ?? this.lastUsedAt,
  );

  Map<String, Object?> toJson() => {
    'user_id': userId,
    'business_id': businessId,
    'name': name,
    'phone': phone,
    'role': role.name,
    'business_name': businessName,
    'last_used_at': lastUsedAt.toUtc().toIso8601String(),
  };

  factory Account.fromJson(Map<String, dynamic> json) => Account(
    userId: json['user_id'] as String,
    businessId: json['business_id'] as String,
    name: json['name'] as String,
    phone: json['phone'] as String,
    role: Role.values.byName(json['role'] as String),
    businessName: json['business_name'] as String?,
    lastUsedAt: DateTime.parse(json['last_used_at'] as String),
  );
}

/// Where secrets go. Android's secure storage on phones; a map in tests.
abstract interface class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class DeviceSecretStore implements SecretStore {
  static const _storage = FlutterSecureStorage();

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class MemorySecretStore implements SecretStore {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

/// The accounts on this phone, which one is in use, and each one's token.
///
/// The list is a small JSON file beside the account databases; tokens stay
/// in secure storage (docs/10, §4.2). Each account's records are in its own
/// file, `accounts/<user id>.db`, which [databasePath] names.
class AccountStore {
  final Directory root;
  final SecretStore secrets;

  AccountStore(this.root, this.secrets);

  File get _file => File(p.join(root.path, 'accounts.json'));

  String databasePath(String userId) =>
      p.join(root.path, 'accounts', '$userId.db');

  Future<({String? current, List<Account> accounts})> load() async {
    if (!_file.existsSync()) return (current: null, accounts: <Account>[]);
    final json = jsonDecode(await _file.readAsString()) as Map<String, dynamic>;
    return (
      current: json['current'] as String?,
      accounts: [
        for (final a in json['accounts'] as List<dynamic>)
          Account.fromJson(a as Map<String, dynamic>),
      ],
    );
  }

  /// Adds or replaces [account] and makes it the one in use.
  Future<void> use(Account account) async {
    final state = await load();
    await _save(account.userId, [
      account,
      ...state.accounts.where((a) => a.userId != account.userId),
    ]);
  }

  /// No account in use: the sign-in screen shows. Every file stays.
  Future<void> leave() async {
    final state = await load();
    await _save(null, state.accounts);
  }

  Future<String?> token(String userId) => secrets.read(_tokenKey(userId));

  Future<void> saveToken(String userId, String token) =>
      secrets.write(_tokenKey(userId), token);

  Future<void> deleteToken(String userId) => secrets.delete(_tokenKey(userId));

  static String _tokenKey(String userId) => 'token.$userId';

  /// Written to a temporary file and renamed over the old one, so a crash
  /// mid-write leaves the previous list rather than half of one.
  Future<void> _save(String? current, List<Account> accounts) async {
    await root.create(recursive: true);
    final tmp = File('${_file.path}.tmp');
    await tmp.writeAsString(
      jsonEncode({
        'current': current,
        'accounts': [for (final a in accounts) a.toJson()],
      }),
      flush: true,
    );
    await tmp.rename(_file.path);
  }
}
