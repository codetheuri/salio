// Layout check for every main screen, for each role, on every screen size,
// at normal and the largest text, in English and Swahili (docs/10, §5). It
// runs the real app and fails on any layout error, such as a row or column
// that overflows, naming the file and line.
//
//   flutter test test/layout
//
// To also save screenshots (phone and tablet landscape, largest text) to
// test/layout/screenshots/:
//
//   flutter test test/layout --update-goldens --dart-define=SCREENSHOTS=true

import 'package:flutter_test/flutter_test.dart';
import 'package:salio/app/app.dart';

import 'harness.dart';

const _screenshots = bool.fromEnvironment('SCREENSHOTS');

void main() {
  setUpAll(loadFonts);

  for (final role in routesByRole.keys) {
    for (final route in routesByRole[role]!) {
      testWidgets('${role.name} $route lays out everywhere', (tester) async {
        final problems = <String>[];

        for (final locale in locales) {
          for (final size in screenSizes.entries) {
            for (final scale in textScales) {
              setView(
                tester,
                size.value.size,
                scale: scale,
                systemBottom: size.value.systemBottom,
              );
              final app = await AppUnderTest.open(
                tester,
                role: role,
                route: route,
                locale: locale,
              );
              try {
                expect(app.location, route, reason: 'opened another screen');
                if (_screenshots &&
                    scale == maxTextScale &&
                    (size.key == 'phone' || size.key == 'tablet-landscape')) {
                  await expectLater(
                    find.byType(SalioApp),
                    matchesGoldenFile(
                      'screenshots/${role.name}${route.replaceAll('/', '_')}'
                      '_${locale.languageCode}_${size.key}.png',
                    ),
                  );
                }
              } finally {
                await app.close();
              }
              for (final e in app.errors.toSet()) {
                problems.add(
                  '${locale.languageCode} ${size.key} @${scale}x: $e',
                );
              }
            }
          }
        }

        resetView(tester);
        expect(problems, isEmpty, reason: problems.join('\n'));
      });
    }
  }
}
