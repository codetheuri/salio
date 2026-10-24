// The update bar, in each state, under the screens where space is tightest:
// a list with a + button, a form with its Save bar, and sign-in. Every size,
// both text sizes, both languages (docs/10, §5). The bar adds height under
// the screen, so a screen that fits alone must still fit with it.
//
//   flutter test test/layout/update_bar_layout_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salio/core/session/permissions.dart';
import 'package:salio/features/app_update/data/app_update_service.dart';
import 'package:salio/features/app_update/presentation/app_update_controller.dart';

import '../support/fake_app_update.dart';
import '../support/fixtures.dart';
import 'harness.dart';

/// A state of the bar, and how to reach it.
class _BarState {
  final FakeAppUpdateService Function() service;
  final Future<void> Function(AppUpdateController c) reach;

  /// Text that must be on screen once reached.
  final String shows;

  const _BarState(this.service, this.reach, this.shows);
}

final _states = <String, _BarState>{
  'offer': _BarState(
    () => FakeAppUpdateService(latest: releaseForTests()),
    (c) async {},
    'Update',
  ),
  'ready': _BarState(
    () => FakeAppUpdateService(latest: releaseForTests())..wifi = true,
    (c) async {},
    'Restart',
  ),
  'required': _BarState(
    () =>
        FakeAppUpdateService(latest: releaseForTests(build: 12, minBuild: 11)),
    (c) async {},
    'Update',
  ),
  'permission': _BarState(
    () => FakeAppUpdateService(
      latest: releaseForTests(),
      installer: FakeInstaller(allowed: false),
    ),
    (c) => c.update(),
    'Allow',
  ),
  'failed': _BarState(
    () =>
        FakeAppUpdateService(latest: releaseForTests())
          ..downloadError = const UpdateException(UpdateFailure.damaged),
    (c) => c.update(),
    'Try again',
  ),
};

const _routes = <(Role?, String)>[
  (Role.owner, '/customers'),
  (Role.owner, '/customers/new'),
  (Role.staff, '/customers/$longCustomerId'),
  (null, '/sign-in'),
];

void main() {
  setUpAll(loadFonts);

  for (final state in _states.entries) {
    for (final (role, route) in _routes) {
      testWidgets('${state.key} bar under ${role?.name ?? 'signed-out'} '
          '$route lays out everywhere', (tester) async {
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
                updates: state.value.service(),
              );
              try {
                final c = app.container.read(appUpdateProvider.notifier);
                await c.check(manual: true);
                await state.value.reach(c);
                for (var i = 0; i < 4; i++) {
                  await tester.pump(const Duration(milliseconds: 250));
                }
                // The action must be on screen and tappable, in English;
                // Swahili is checked by the layout only.
                if (locale.languageCode == 'en') {
                  final action = find.widgetWithText(
                    FilledButton,
                    state.value.shows,
                  );
                  if (action.hitTestable().evaluate().isEmpty) {
                    problems.add(
                      '${size.key} @${scale}x: "${state.value.shows}" '
                      'not tappable',
                    );
                  }
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
