// lib/core/utils/exceptions.dart

/// Base exception for all Salio app exceptions.
/// This allows us to catch any app-specific error gracefully in the UI.
abstract class SalioException implements Exception {
  final String message;
  final dynamic originalError;
  final StackTrace? stackTrace;

  const SalioException(this.message, {this.originalError, this.stackTrace});

  @override
  String toString() => 'SalioException: $message';
}

/// Thrown when there is an issue reading/writing to the secure hardware storage
class SecureStorageException extends SalioException {
  const SecureStorageException(String message, {dynamic originalError, StackTrace? stackTrace})
      : super(message, originalError: originalError, stackTrace: stackTrace);
}

/// Thrown when local SQLite database operations fail
class SalioDatabaseException extends SalioException {
  const SalioDatabaseException(String message, {dynamic originalError, StackTrace? stackTrace})
      : super(message, originalError: originalError, stackTrace: stackTrace);
}
