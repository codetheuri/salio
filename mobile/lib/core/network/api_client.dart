import 'dart:convert';
import 'package:http/http.dart' as http;
import '../storage/secure_storage.dart';
import '../utils/logger.dart';

/// ApiClient acts as a wrapper around the `http` package.
/// It automatically injects the JWT token from Secure Storage into all requests,
/// ensuring the user remains authenticated.
class ApiClient {
  // baseUrl points to the Go backend.
  // We use 127.0.0.1 because you are running the Flutter Linux Desktop app, not the Android Emulator.
  // We can also override this during build with --dart-define=API_URL=http://...
  static const String baseUrl = String.fromEnvironment('API_URL', defaultValue: 'http://127.0.0.1:8080/v1');

  final SecureStorageService _secureStorage;

  ApiClient({SecureStorageService? secureStorage}) 
      : _secureStorage = secureStorage ?? SecureStorageService();

  Future<Map<String, String>> _getHeaders() async {
    final token = await _secureStorage.getToken();
    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'ngrok-skip-browser-warning': 'true', // Bypasses the HTML warning page on free Ngrok accounts
    };
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  Future<http.Response> get(String endpoint, {Map<String, String>? queryParams}) async {
    final headers = await _getHeaders();
    var uri = Uri.parse('$baseUrl$endpoint');
    
    if (queryParams != null && queryParams.isNotEmpty) {
      uri = uri.replace(queryParameters: queryParams);
    }
    
    Logger.i('GET $uri');
    return await http.get(uri, headers: headers);
  }

  Future<http.Response> post(String endpoint, Map<String, dynamic> body) async {
    final headers = await _getHeaders();
    final uri = Uri.parse('$baseUrl$endpoint');
    
    Logger.i('POST $uri');
    return await http.post(uri, headers: headers, body: jsonEncode(body));
  }

  Future<http.Response> put(String endpoint, Map<String, dynamic> body) async {
    final headers = await _getHeaders();
    final uri = Uri.parse('$baseUrl$endpoint');
    
    Logger.i('PUT $uri');
    return await http.put(uri, headers: headers, body: jsonEncode(body));
  }

  Future<http.Response> delete(String endpoint) async {
    final headers = await _getHeaders();
    final uri = Uri.parse('$baseUrl$endpoint');
    
    Logger.i('DELETE $uri');
    return await http.delete(uri, headers: headers);
  }
}
