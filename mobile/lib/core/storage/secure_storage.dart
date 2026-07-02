import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../utils/logger.dart';
import '../utils/exceptions.dart';

/// A secure storage service for handling sensitive data like JWTs.
/// 
/// Enterprise-grade practices used here:
/// 1. No magic strings (keys are private constants).
/// 2. Platform-specific options included for best security practices.
/// 3. Graceful error handling using custom exceptions and a centralized logger.
class SecureStorageService {
  static const _storage = FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock,
    ),
  );

  static const String _keyJwtToken = 'salio_jwt_token';
  static const String _keyLastSync = 'salio_last_sync';

  /// Saves the JWT token securely to the device's hardware-backed keystore.
  Future<void> saveToken(String token) async {
    try {
      await _storage.write(key: _keyJwtToken, value: token);
      Logger.i('JWT token saved securely.');
    } catch (e, stackTrace) {
      Logger.e('Failed to securely save JWT token.', e, stackTrace);
      throw SecureStorageException('Failed to save authentication token.', originalError: e, stackTrace: stackTrace);
    }
  }

  /// Retrieves the JWT token if it exists. Returns null if not found.
  Future<String?> getToken() async {
    try {
      return await _storage.read(key: _keyJwtToken);
    } catch (e, stackTrace) {
      Logger.e('Failed to read JWT token from secure storage.', e, stackTrace);
      return null; 
    }
  }

  /// Deletes the JWT token (used during logout).
  Future<void> deleteToken() async {
    try {
      await _storage.delete(key: _keyJwtToken);
      Logger.i('JWT token deleted securely.');
    } catch (e, stackTrace) {
      Logger.e('Failed to securely delete JWT token.', e, stackTrace);
      throw SecureStorageException('Failed to delete authentication token.', originalError: e, stackTrace: stackTrace);
    }
  }

  /// Saves the timestamp of the last successful synchronization.
  Future<void> saveLastSyncTime(DateTime time) async {
    try {
      await _storage.write(key: _keyLastSync, value: time.toIso8601String());
    } catch (e) {
      Logger.e('Failed to save last sync time.', e);
    }
  }

  /// Retrieves the timestamp of the last successful synchronization. Returns null if never synced.
  Future<DateTime?> getLastSyncTime() async {
    try {
      final str = await _storage.read(key: _keyLastSync);
      if (str != null) return DateTime.parse(str);
    } catch (e) {
      Logger.e('Failed to read last sync time.', e);
    }
    return null;
  }
  
  /// Clears all secure storage (useful for full app reset or hard logout).
  Future<void> clearAll() async {
     try {
       await _storage.deleteAll();
       Logger.i('All secure storage cleared.');
     } catch(e, stackTrace) {
       Logger.e('Failed to clear secure storage.', e, stackTrace);
       throw SecureStorageException('Failed to clear secure storage.', originalError: e, stackTrace: stackTrace);
     }
  }
}
