import '../../../core/network/api_client.dart';
import '../../../core/session/account_store.dart';
import '../../../core/session/permissions.dart';

/// Sign-in and the business profile, from server-v2's business module.
class AuthApi {
  final ApiClient api;

  AuthApi(this.api);

  /// Signs in by phone and password. Returns the token and the account.
  Future<({String token, Account account})> signIn({
    required String phone,
    required String password,
    required DateTime now,
  }) async {
    final data =
        await api.post('/auth/login', {'phone': phone, 'password': password})
            as Map<String, dynamic>;
    final user = data['user'] as Map<String, dynamic>;
    return (
      token: data['token'] as String,
      account: Account(
        userId: user['id'] as String,
        businessId: user['business_id'] as String,
        name: user['name'] as String,
        phone: user['phone'] as String,
        role: Role.values.byName(user['role'] as String),
        lastUsedAt: now,
      ),
    );
  }

  /// The shop's name, for the app bar.
  Future<String> businessName() async {
    final data = await api.get('/business') as Map<String, dynamic>;
    return data['name'] as String;
  }
}
