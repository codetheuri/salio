import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

/// Sends the app's log records to the console in development. Code logs
/// through `Logger('name')` and never calls a reporting service directly,
/// so crash reporting, when it is chosen (docs/10, §13), is added here, in
/// one place: warnings as breadcrumbs, errors as events.
///
/// What goes into a message matters: never names, phone numbers or amounts,
/// only record IDs (docs/10, §9.3).
void setUpLogging() {
  Logger.root.level = kReleaseMode ? Level.INFO : Level.ALL;
  Logger.root.onRecord.listen((record) {
    if (kReleaseMode) return;
    final error = record.error == null ? '' : ' ${record.error}';
    debugPrint(
      '${record.level.name} ${record.loggerName}: ${record.message}$error',
    );
  });
}
