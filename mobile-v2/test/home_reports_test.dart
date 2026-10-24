// The flows of M5 through the real screens, on the seeded database: Home's
// figures, today's money by role, the Today list with Call and Remind, the
// + button, and reports read online, kept for offline, and saved as PDFs.
// How each screen fits every size is the layout tests' job; that Home's
// figures equal the server's summary is live scenario 14's.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salio/core/database/app_database.dart';
import 'package:salio/core/network/api_exception.dart';
import 'package:salio/core/session/permissions.dart';
import 'package:salio/features/reports/data/report_repository.dart';
import 'package:salio/features/sales/presentation/customer_picker.dart';

import 'layout/harness.dart';
import 'support/fixtures.dart';

void main() {
  setUpAll(loadFonts);

  /// [real] also lets real time pass, for one-off database reads and files.
  Future<void> settle(WidgetTester tester, {bool real = false}) async {
    if (real) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
    }
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> flow(
    WidgetTester tester,
    String route,
    Future<void> Function(AppUnderTest app) body, {
    Role? role = Role.owner,
    FakeReportRepository Function(AppDatabase db)? reports,
  }) async {
    addTearDown(() => resetView(tester));
    setView(tester, const Size(360, 2400));
    final app = await AppUnderTest.open(
      tester,
      role: role,
      route: route,
      reports: reports,
    );
    try {
      await settle(tester, real: true);
      await body(app);
      expect(app.errors, isEmpty);
    } finally {
      await app.close();
    }
  }

  testWidgets('the owner\'s Home: the book, the quiet list, who took what', (
    tester,
  ) async {
    await flow(tester, '/home', (app) async {
      expect(find.text('The book'), findsOne);
      expect(find.text('Quiet for 30 days'), findsOne);
      expect(
        find.text('Mzee Kamau wa Kiambu Road, near the old posho mill'),
        findsWidgets,
        reason: 'owes, and nothing for 60 days',
      );
      // Today's sales were recorded by a member of staff, by name.
      expect(find.text('Wanjiru Nyambura Kamau-Odhiambo'), findsOne);
      expect(find.textContaining('You took'), findsNothing);
      expect(find.text('The shop owes suppliers'), findsOne);
    });
  });

  testWidgets('staff see what they took, not who took what, nor suppliers', (
    tester,
  ) async {
    await flow(tester, '/home', role: Role.staff, (app) async {
      expect(find.textContaining('You took'), findsOne);
      expect(find.text('Wanjiru Nyambura Kamau-Odhiambo'), findsNothing);
      expect(find.text('The shop owes suppliers'), findsNothing);
    });
  });

  testWidgets('the Today list calls and reminds, from the shop\'s own phone', (
    tester,
  ) async {
    await flow(tester, '/home', (app) async {
      const name = 'Bartholomew Kipchumba Arap Kiprotich Wanyonyi';
      expect(find.text('To collect today'), findsOne);
      final call = find.byTooltip('Call $name');
      await tester.ensureVisible(call);
      await tester.tap(call);
      await settle(tester);
      expect(app.launched.single, Uri.parse('tel:+254712345678'));

      await tester.tap(find.byTooltip('Remind $name'));
      await settle(tester);
      await tester.tap(find.text('Remind on WhatsApp'));
      await settle(tester);
      final link = app.launched.last;
      expect(link.host, 'wa.me');
      expect(link.path, '/254712345678');
      final text = link.queryParameters['text']!;
      expect(text, contains(name));
      expect(text, contains('Mama Amina General Store and Agrovet'));
      expect(text, contains('due since'));
    });
  });

  testWidgets('the + button: a debt, for a customer chosen first', (
    tester,
  ) async {
    await flow(tester, '/home', (app) async {
      await tester.tap(find.byTooltip('Record a debt, payment or sale'));
      await settle(tester);
      await tester.tap(find.text('Record debt'));
      await settle(tester);
      await tester.tap(
        find
            .descendant(
              of: find.byType(CustomerPicker),
              matching: find.text('Akinyi'),
            )
            .first,
      );
      await settle(tester);
      expect(
        app.location,
        '/customers/0197a000-0000-7000-8000-00000000000b/debt',
      );
    });
  });

  testWidgets('a report reads a period, and saves its PDF to open or share', (
    tester,
  ) async {
    late FakeReportRepository repo;
    await flow(
      tester,
      '/reports/sales',
      reports: (db) => repo = FakeReportRepository(db),
      (app) async {
        expect(find.textContaining('As of'), findsOne);
        expect(find.text('Best-selling products'), findsOne);

        await tester.tap(find.text('7 days'));
        await settle(tester, real: true);
        final last = repo.loaded.last;
        expect(last.kind, ReportKind.sales);
        expect(last.to!.difference(last.from!).inDays, 6);

        await tester.tap(find.byTooltip('Open as PDF'));
        for (var i = 0; i < 20 && app.openedPdfs.isEmpty; i++) {
          await settle(tester, real: true);
        }
        expect(app.openedPdfs.single.readAsStringSync(), startsWith('%PDF'));
        expect(repo.pdfs.single, last, reason: 'the same period as shown');

        await tester.tap(find.byTooltip('Share PDF'));
        for (var i = 0; i < 20 && app.sharedPdfs.isEmpty; i++) {
          await settle(tester, real: true);
        }
        expect(app.sharedPdfs, hasLength(1));
      },
    );
  });

  testWidgets('offline, a report shows the copy kept, and says when it was '
      'read', (tester) async {
    late FakeReportRepository repo;
    await flow(
      tester,
      '/reports/ageing',
      reports: (db) => repo = FakeReportRepository(db),
      (app) async {
        expect(find.textContaining('As of'), findsOne);
        repo.failure = const ApiException(ApiFailure.offline);
        // Pulled down to refresh, as a shopkeeper would: far enough to arm
        // the indicator on this tall test window.
        await tester.fling(
          find.text('Total owed'),
          const Offset(0, 1200),
          1000,
        );
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        await settle(tester, real: true);
        await settle(tester, real: true);
        expect(
          find.textContaining('No connection. This is the copy'),
          findsOne,
        );
        expect(
          find.text('Bartholomew Kipchumba Arap Kiprotich Wanyonyi'),
          findsOne,
          reason: 'the kept copy, still readable',
        );
      },
    );
  });

  testWidgets('offline with no copy kept, a report says it needs a '
      'connection', (tester) async {
    await flow(
      tester,
      '/reports/collections',
      reports: (db) =>
          FakeReportRepository(db)
            ..failure = const ApiException(ApiFailure.offline),
      (app) async {
        expect(
          find.textContaining('This report needs a connection the first time.'),
          findsOne,
        );
        expect(find.text('Try again'), findsOne);
      },
    );
  });

  testWidgets('staff have no payables report, nor its route', (tester) async {
    await flow(tester, '/reports', role: Role.staff, (app) async {
      expect(find.text('Owed to suppliers'), findsNothing);
      expect(find.text('Debt ageing'), findsOne);
    });
    await flow(
      tester,
      '/reports/payables',
      role: Role.staff,
      (app) async => expect(app.location, '/reports'),
    );
  });
}
