// Shared set-up for the layout tests: runs the real app as an owner or a
// member of staff, in English or Swahili. Adapted from DairyGo's
// test/layout/harness.dart.

import 'dart:io';
import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:salio/app/app.dart';
import 'package:salio/app/router/app_router.dart';
import 'package:salio/app/shell/app_sections.dart';
import 'package:salio/core/session/current_user.dart';
import 'package:salio/core/session/permissions.dart';

/// Every main screen a role can open.
Map<Role, List<String>> get routesByRole => {
  for (final role in Role.values)
    role: [
      for (final s in AppSection.values)
        if (s.visibleTo(SessionUser.ofRole('Test', role))) s.path,
    ],
};

const locales = [Locale('en'), Locale('sw')];

/// Logical screen sizes (docs/10, §5), with the bottom area the system
/// draws over where a size needs one.
class ScreenSize {
  final Size size;
  final double systemBottom;

  const ScreenSize(this.size, {this.systemBottom = 0});
}

const screenSizes = <String, ScreenSize>{
  'phone-small': ScreenSize(Size(320, 640)),
  'phone': ScreenSize(Size(360, 800)),
  'phone-large': ScreenSize(Size(430, 932)),
  'phone-landscape': ScreenSize(Size(800, 360)),
  'foldable': ScreenSize(Size(673, 841)),
  // A cheap phone with the older 3-button navigation bar.
  'small-3-button': ScreenSize(Size(360, 640), systemBottom: 48),
  'tablet': ScreenSize(Size(800, 1280)),
  'tablet-landscape': ScreenSize(Size(1280, 800)),
};

/// Normal text, and the largest the app allows ([maxTextScale]).
const textScales = [1.0, maxTextScale];

/// Loads the app's bundled Roboto and the Material icons, so text is
/// measured as on a phone. Without this every letter is a square box and
/// the tests would report overflows that phones never show.
Future<void> loadFonts() async {
  Future<void> load(String family, List<String> paths) async {
    final loader = FontLoader(family);
    for (final path in paths) {
      final file = File(path);
      if (file.existsSync()) {
        loader.addFont(
          Future.value(ByteData.sublistView(file.readAsBytesSync())),
        );
      }
    }
    await loader.load();
  }

  await load('Roboto', [
    for (final w in ['Regular', 'Medium', 'Bold']) 'assets/fonts/Roboto-$w.ttf',
  ]);
  final flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? '';
  await load('MaterialIcons', [
    '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  ]);
}

/// Sets the test window to [size] at [scale] text, with [systemBottom] dp
/// of navigation bar. Reset with [resetView].
void setView(
  WidgetTester tester,
  Size size, {
  double scale = 1,
  double systemBottom = 0,
  double dpr = 2,
}) {
  tester.view.devicePixelRatio = dpr;
  tester.view.physicalSize = size * dpr;
  final padding = FakeViewPadding(bottom: systemBottom * dpr);
  tester.view.padding = padding;
  tester.view.viewPadding = padding;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
}

void resetView(WidgetTester tester) {
  tester.view.reset();
  tester.platformDispatcher.clearTextScaleFactorTestValue();
}

/// An open app for one role on one route. Collects layout errors raised after
/// navigating. Call [close] when done.
class AppUnderTest {
  final WidgetTester tester;
  final ProviderContainer container;
  final List<String> errors = [];
  final FlutterExceptionHandler? _previousHandler;

  AppUnderTest._(this.tester, this.container, this._previousHandler);

  static Future<AppUnderTest> open(
    WidgetTester tester, {
    required Role role,
    required String route,
    Locale locale = const Locale('en'),
  }) async {
    PackageInfo.setMockInitialValues(
      appName: 'Salio',
      packageName: 'ke.co.urizon.salio.dev',
      version: '2.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
    final container = ProviderContainer(
      overrides: [
        currentUserProvider.overrideWithValue(SessionUser.ofRole('Test', role)),
      ],
    );
    container.read(appLocaleProvider.notifier).set(locale);

    final app = AppUnderTest._(tester, container, FlutterError.onError);
    FlutterError.onError = (details) {
      // The error's first line plus the widget's source location.
      final where =
          RegExp(
            r'file:///\S*/lib/(\S+\.dart:\d+)',
          ).firstMatch(details.toString())?.group(1) ??
          '?';
      app.errors.add(
        '${details.exceptionAsString().split('\n').first}  [$where]',
      );
    };

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const SalioApp()),
    );
    container.read(appRouterProvider).go(route);
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    return app;
  }

  /// Where the router is now.
  String get location =>
      container.read(appRouterProvider).state.matchedLocation;

  Future<void> close() async {
    FlutterError.onError = _previousHandler;
    await tester.pumpWidget(const SizedBox.shrink());
    // Flush timers, such as a snack bar's.
    await tester.pump(const Duration(seconds: 5));
    container.dispose();
  }
}
