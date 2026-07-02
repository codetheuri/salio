import 'package:flutter/foundation.dart';

/// A production-ready logger.
/// In debug mode, this prints to the console.
/// In production, this can be wired up to Crashlytics, Sentry, or Datadog
/// without having to change logging code anywhere else in the app.
class Logger {
  /// Logs an error with optional stack trace and original error details.
  static void e(String message, [dynamic error, StackTrace? stackTrace]) {
    if (kDebugMode) {
      print('🔴 ERROR: $message');
      if (error != null) print('Error Details: $error');
      if (stackTrace != null) print('StackTrace:\n$stackTrace');
    } else {
      // TODO (Phase 2): Send to Crashlytics/Sentry in production
      // FirebaseCrashlytics.instance.recordError(error, stackTrace, reason: message);
    }
  }

  /// Logs a warning.
  static void w(String message) {
    if (kDebugMode) {
      print('🟠 WARN: $message');
    }
  }

  /// Logs general info.
  static void i(String message) {
    if (kDebugMode) {
      print('🔵 INFO: $message');
    }
  }
}
