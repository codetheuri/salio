// lib/features/auth/auth_repository.dart

/// Abstract interface for Authentication.
/// In Phase 1, we will use a Mock implementation of this since the Go backend isn't built yet.
/// In Phase 2, we will swap it out for an `HttpAuthRepository` without touching the UI.
abstract class AuthRepository {
  /// Simulates logging in and returns a JWT token.
  Future<String> login(String phone, String password);
  
  /// Simulates registering a new business and returns a JWT token.
  Future<String> registerBusiness(String businessName, String ownerName, String phone, String password);

  /// Joins an existing business using an invite code and returns a JWT token.
  Future<String> joinBusiness(String inviteCode, String name, String phone, String password);
}
