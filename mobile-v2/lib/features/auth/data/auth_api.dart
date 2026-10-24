import '../../../core/network/api_client.dart';
import '../../../core/session/account_store.dart';
import '../../../core/session/permissions.dart';

/// The user's own profile, as the server holds it now.
typedef Profile = ({String name, Role role, List<String>? permissions});

/// Signing in, registering a shop, joining one, and the profile, from
/// server-v2's business module. Phone numbers go as typed: the server stores
/// them in one form (B15), so any form signs in.
class AuthApi {
  final ApiClient api;

  AuthApi(this.api);

  /// Signs in by phone and password. Returns the token and the account.
  Future<({String token, Account account})> signIn({
    required String phone,
    required String password,
    required DateTime now,
  }) async => _signedIn(
    await api.post('/auth/login', {'phone': phone, 'password': password}),
    now,
  );

  /// Registers a new shop with its owner, and signs them in.
  Future<({String token, Account account})> register({
    required String businessName,
    required String name,
    required String phone,
    required String password,
    required DateTime now,
  }) async => _signedIn(
    await api.post('/auth/register-business', {
      'business_name': businessName,
      'name': name,
      'phone': phone,
      'password': password,
    }),
    now,
  );

  /// Joins a shop as staff with the owner's invite code, and signs in.
  Future<({String token, Account account})> join({
    required String code,
    required String name,
    required String phone,
    required String password,
    required DateTime now,
  }) async => _signedIn(
    await api.post('/auth/join', {
      'code': code,
      'name': name,
      'phone': phone,
      'password': password,
    }),
    now,
  );

  /// Who the server says this user is now: their role and permissions can
  /// change on another phone.
  Future<Profile> me() async {
    final user = await api.get('/users/me') as Map<String, dynamic>;
    return (
      name: user['name'] as String,
      role: Role.values.byName(user['role'] as String),
      permissions: _permissions(user),
    );
  }

  /// The shop's name and time zone.
  Future<({String name, String timeZone})> business() async {
    final data = await api.get('/business') as Map<String, dynamic>;
    return (
      name: data['name'] as String,
      timeZone: data['time_zone'] as String? ?? 'Africa/Nairobi',
    );
  }

  static ({String token, Account account}) _signedIn(
    Object? data,
    DateTime now,
  ) {
    final body = data! as Map<String, dynamic>;
    final user = body['user'] as Map<String, dynamic>;
    return (
      token: body['token'] as String,
      account: Account(
        userId: user['id'] as String,
        businessId: user['business_id'] as String,
        name: user['name'] as String,
        phone: user['phone'] as String,
        role: Role.values.byName(user['role'] as String),
        permissions: _permissions(user),
        lastUsedAt: now,
      ),
    );
  }

  /// Null from a server older than B5, which does not send them.
  static List<String>? _permissions(Map<String, dynamic> user) =>
      (user['permissions'] as List<dynamic>?)?.cast<String>().toList()?..sort();
}
