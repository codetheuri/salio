import 'dart:convert';
import '../../core/network/api_client.dart';
import '../../core/utils/exceptions.dart';
import 'auth_repository.dart';

/// HttpAuthRepository implements AuthRepository by making real network calls
/// to the Go backend. 
class HttpAuthRepository implements AuthRepository {
  final ApiClient _apiClient;

  HttpAuthRepository({ApiClient? apiClient}) 
      : _apiClient = apiClient ?? ApiClient();

  @override
  Future<String> login(String phone, String password) async {
    final response = await _apiClient.post('/auth/login', {
      'phone': phone,
      'password': password,
    });

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body);
      // The Go backend returns the token in a data envelope
      return body['data']['token'] as String;
    } else {
      _throwDetailedError(response.body);
      throw Exception('Unreachable');
    }
  }

  @override
  Future<String> registerBusiness(String businessName, String ownerName, String phone, String password) async {
    final response = await _apiClient.post('/auth/register-business', {
      'business_name': businessName,
      'owner_name': ownerName,
      'phone': phone,
      'password': password,
    });

    if (response.statusCode == 201) {
      final body = jsonDecode(response.body);
      return body['data']['token'] as String;
    } else {
      _throwDetailedError(response.body);
      throw Exception('Unreachable');
    }
  }

  @override
  Future<String> joinBusiness(String inviteCode, String name, String phone, String password) async {
    final response = await _apiClient.post('/auth/join', {
      'invite_code': inviteCode,
      'name': name,
      'phone': phone,
      'password': password,
    });

    if (response.statusCode == 201) {
      final body = jsonDecode(response.body);
      return body['data']['token'] as String;
    } else {
      _throwDetailedError(response.body);
      throw Exception('Unreachable');
    }
  }

  /// Parses the standardized Go backend error envelope and throws a clean message.
  void _throwDetailedError(String responseBody) {
    try {
      final data = jsonDecode(responseBody);
      final errorPayload = data['error'];
      if (errorPayload != null) {
        final message = errorPayload['message'] as String?;
        if (message != null) {
          throw Exception(message);
        }
      }
    } catch (e) {
      // If parsing fails, just throw a generic error
      if (e is Exception && !e.toString().contains('FormatException')) {
        rethrow;
      }
    }
    throw Exception('An unexpected error occurred.');
  }
}
