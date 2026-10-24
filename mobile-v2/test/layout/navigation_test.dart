// How the shell behaves: which navigation each width gets, what each role
// can reach, and the text-size ceiling.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salio/app/app.dart';
import 'package:salio/core/session/permissions.dart';

import 'harness.dart';

void main() {
  setUpAll(loadFonts);

  testWidgets('a phone gets the bottom bar, a tablet the rail', (tester) async {
    addTearDown(() => resetView(tester));

    setView(tester, const Size(360, 800));
    var app = await AppUnderTest.open(tester, role: Role.owner, route: '/home');
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.byType(NavigationDestination), findsNWidgets(5));
    await app.close();

    setView(tester, const Size(800, 1280));
    app = await AppUnderTest.open(tester, role: Role.owner, route: '/home');
    expect(find.byType(NavigationBar), findsNothing);
    final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
    expect(rail.destinations, hasLength(7), reason: 'owners see Suppliers');
    expect(rail.extended, isFalse);
    await app.close();

    setView(tester, const Size(1280, 800));
    app = await AppUnderTest.open(tester, role: Role.owner, route: '/home');
    expect(
      tester.widget<NavigationRail>(find.byType(NavigationRail)).extended,
      isTrue,
      reason: 'labels beside icons from 1200 dp',
    );
    await app.close();
  });

  testWidgets('staff never see Suppliers', (tester) async {
    addTearDown(() => resetView(tester));

    setView(tester, const Size(800, 1280));
    var app = await AppUnderTest.open(tester, role: Role.staff, route: '/home');
    expect(
      tester.widget<NavigationRail>(find.byType(NavigationRail)).destinations,
      hasLength(6),
    );
    expect(find.text('Suppliers'), findsNothing);
    await app.close();

    // Opened directly, for example from an old link: back to Home.
    app = await AppUnderTest.open(
      tester,
      role: Role.staff,
      route: '/suppliers',
    );
    expect(app.location, '/home');
    await app.close();
  });

  testWidgets('on a phone, More lists what the bar has no room for', (
    tester,
  ) async {
    addTearDown(() => resetView(tester));
    setView(tester, const Size(360, 800));

    var app = await AppUnderTest.open(tester, role: Role.owner, route: '/more');
    expect(find.widgetWithText(ListTile, 'Suppliers'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Reports'), findsOneWidget);
    await tester.tap(find.widgetWithText(ListTile, 'Reports'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(app.location, '/reports');
    await app.close();

    app = await AppUnderTest.open(tester, role: Role.staff, route: '/more');
    expect(find.widgetWithText(ListTile, 'Suppliers'), findsNothing);
    expect(find.widgetWithText(ListTile, 'Reports'), findsOneWidget);
    await app.close();
  });

  testWidgets('Swahili labels the bar in Swahili', (tester) async {
    addTearDown(() => resetView(tester));
    setView(tester, const Size(360, 800));
    final app = await AppUnderTest.open(
      tester,
      role: Role.owner,
      route: '/home',
      locale: const Locale('sw'),
    );
    for (final label in ['Nyumbani', 'Wateja', 'Mauzo', 'Bidhaa', 'Zaidi']) {
      expect(find.text(label), findsWidgets, reason: label);
    }
    await app.close();
  });

  testWidgets('text grows with the phone setting, up to the ceiling', (
    tester,
  ) async {
    addTearDown(() => resetView(tester));
    setView(tester, const Size(360, 800), scale: 2);
    final app = await AppUnderTest.open(
      tester,
      role: Role.owner,
      route: '/home',
    );
    final context = tester.element(find.byType(Scaffold).first);
    expect(MediaQuery.textScalerOf(context).scale(10), 10 * maxTextScale);
    await app.close();
  });

  testWidgets('the bottom bar stays above a 3-button navigation bar', (
    tester,
  ) async {
    addTearDown(() => resetView(tester));
    for (final scale in textScales) {
      setView(tester, const Size(320, 640), scale: scale, systemBottom: 48);
      final app = await AppUnderTest.open(
        tester,
        role: Role.owner,
        route: '/home',
      );
      expect(
        tester.getRect(find.byType(NavigationBar)).bottom,
        lessThanOrEqualTo(640 - 48),
      );
      await app.close();
    }
  });
}
