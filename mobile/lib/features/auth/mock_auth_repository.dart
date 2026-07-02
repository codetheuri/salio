import 'dart:convert';
import 'auth_repository.dart';

/// A mock implementation of AuthRepository to allow us to build and test
/// the fully functional app offline before the Go backend is ready.
class MockAuthRepository implements AuthRepository {
  @override
  Future<String> login(String phone, String password) async {
    // Simulate network delay
    await Future.delayed(const Duration(seconds: 2));
    
    if (phone == '0700000000' && password == 'password') {
       // Returns a fake but structurally valid JWT
       return _createFakeJwt('business_123', 'user_456', 'owner');
    }
    
    // In a real app we'd throw an ApiException, for now a standard Exception works for the mock
    throw Exception('Invalid phone or password. Hint: try 0700000000 / password');
  }

  @override
  Future<String> registerBusiness(String businessName, String ownerName, String phone, String password) async {
    await Future.delayed(const Duration(seconds: 2));
    return _createFakeJwt('new_business_789', 'new_user_101', 'owner');
  }

  @override
  Future<String> joinBusiness(String inviteCode, String name, String phone, String password) async {
    await Future.delayed(const Duration(seconds: 2));
    if (inviteCode.length != 6) throw Exception('Invalid invite code');
    return _createFakeJwt('existing_business_123', 'new_staff_102', 'staff');
  }

  /// Helper to generate a base64 encoded string that looks exactly like a real JWT.
  /// This allows our `jwt_decoder` package to parse it successfully.
  String _createFakeJwt(String businessId, String userId, String role) {
    final header = base64Url.encode(utf8.encode('{"alg":"HS256","typ":"JWT"}'));
    final payload = base64Url.encode(utf8.encode(
      '{"business_id":"$businessId","user_id":"$userId","role":"$role","exp":9999999999}'
    ));
    final signature = base64Url.encode(utf8.encode('fake_signature'));
    
    // Strip trailing padding characters which base64Url adds but JWTs omit
    return '$header.$payload.$signature'.replaceAll('=', '');
  }
}
