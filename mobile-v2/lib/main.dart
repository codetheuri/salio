import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import 'app/app.dart';
import 'core/logging/app_logging.dart';

final _log = Logger('app');

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  setUpLogging();
  // Errors nobody caught: logged, so they reach crash reporting once it
  // exists, instead of vanishing.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    _log.severe('Flutter error', details.exception, details.stack);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    _log.severe('Uncaught error', error, stack);
    return true;
  };
  runApp(const ProviderScope(child: SalioApp()));
}
