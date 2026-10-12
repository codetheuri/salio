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

  /// Server-issued position in the change sequence, used for pulling.
  ///
  /// This replaces the old timestamp watermark. A clock could advance past
  /// records belonging to a write that had started but not yet committed on the
  /// server, hiding them permanently; a cursor only ever moves as far as records
  /// actually received.
  static const String _keySyncCursor = 'salio_sync_cursor';

  /// Local high-water mark for pushing: the newest `updated_at` this device has
  /// successfully sent. Separate from the pull cursor because one tracks our own
  /// outgoing edits and the other tracks the server's position.
  static const String _keyLastPushedAt = 'salio_last_pushed_at';

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
  ///
  /// Superseded by [saveSyncCursor]. A clock cannot safely mark sync progress:
  /// it can advance past a server write that had begun but not yet committed,
  /// hiding those records permanently. Retained only so an upgrading install can
  /// still read any value it left behind.
  @Deprecated('Use saveSyncCursor; a timestamp watermark loses concurrent writes')
  Future<void> saveLastSyncTime(DateTime time) async {
    try {
      await _storage.write(key: _keyLastSync, value: time.toIso8601String());
    } catch (e) {
      Logger.e('Failed to save last sync time.', e);
    }
  }

  /// Retrieves the timestamp of the last successful synchronization. Returns null if never synced.
  @Deprecated('Use getSyncCursor; a timestamp watermark loses concurrent writes')
  Future<DateTime?> getLastSyncTime() async {
    try {
      final str = await _storage.read(key: _keyLastSync);
      if (str != null) return DateTime.parse(str);
    } catch (e) {
      Logger.e('Failed to read last sync time.', e);
    }
    return null;
  }
  
  /// Saves the server-issued sync cursor.
  Future<void> saveSyncCursor(int cursor) async {
    try {
      await _storage.write(key: _keySyncCursor, value: cursor.toString());
    } catch (e) {
      Logger.e('Failed to save sync cursor.', e);
    }
  }

  /// Returns the sync cursor, or 0 when this device has never synced.
  Future<int> getSyncCursor() async {
    try {
      final str = await _storage.read(key: _keySyncCursor);
      if (str != null) return int.tryParse(str) ?? 0;
    } catch (e) {
      Logger.e('Failed to read sync cursor.', e);
    }
    return 0;
  }

  /// Saves the newest local `updated_at` successfully pushed to the server.
  Future<void> saveLastPushedAt(DateTime time) async {
    try {
      await _storage.write(key: _keyLastPushedAt, value: time.toIso8601String());
    } catch (e) {
      Logger.e('Failed to save last push time.', e);
    }
  }

  /// Returns the last successful push watermark, or null if never pushed.
  Future<DateTime?> getLastPushedAt() async {
    try {
      final str = await _storage.read(key: _keyLastPushedAt);
      if (str != null) return DateTime.parse(str);
    } catch (e) {
      Logger.e('Failed to read last push time.', e);
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
