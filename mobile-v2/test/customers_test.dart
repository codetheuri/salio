// The customer and ledger flows of M3 through the real screens, on the
// seeded database: search, filters, adding with the required phone,
// payments with their code, the limit warning, voids, and who may do what.
// How each screen fits every size is the layout tests' job.

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salio/app/router/app_router.dart';
import 'package:salio/core/database/app_database.dart';
import 'package:salio/core/session/permissions.dart';
import 'package:salio/core/widgets/password_field.dart';
import 'package:salio/features/customers/presentation/customer_form_screen.dart';

import 'layout/harness.dart';
import 'support/fixtures.dart';

void main() {
  setUpAll(loadFonts);

  /// Runs [body] on an open app and closes it whatever happens, so a
  /// failed check is reported as itself: the harness holds Flutter's error
  /// handler until the app closes.
  Future<void> flow(
    WidgetTester tester,
    String route,
    Future<void> Function(AppUnderTest app) body, {
    Role? role = Role.owner,
    PickedContact? contact,
    Size size = const Size(360, 1200),
  }) async {
    addTearDown(() => resetView(tester));
    setView(tester, size);
    final app = await AppUnderTest.open(
      tester,
      role: role,
      route: route,
      overrides: [contactPickerProvider.overrideWithValue(() async => contact)],
    );
    try {
      await body(app);
      expect(app.errors, isEmpty);
    } finally {
      await app.close();
    }
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('search finds a customer by phone in any form', (tester) async {
    await flow(tester, '/customers', (app) async {
      for (final typed in ['0700 111 222', '+254700111', '700111222']) {
        await tester.enterText(find.byType(TextField).first, typed);
        await settle(tester);
        expect(find.text('Otieno'), findsWidgets, reason: typed);
        expect(find.text('Akinyi'), findsNothing, reason: typed);
      }
      await tester.enterText(find.byType(TextField).first, 'aki');
      await settle(tester);
      expect(find.text('Akinyi'), findsOneWidget);
    });
  });

  testWidgets('filters: overdue, over limit, advance, cleared', (tester) async {
    await flow(tester, '/customers', (app) async {
      Future<void> filter(String label) async {
        final chip = find.widgetWithText(ChoiceChip, label);
        await tester.ensureVisible(chip);
        await tester.tap(chip);
        await settle(tester);
      }

      const long = 'Bartholomew Kipchumba Arap Kiprotich Wanyonyi';
      await filter('Overdue');
      expect(find.text(long), findsOneWidget);
      expect(find.text('Customer number 3'), findsNothing);
      await filter('Over limit');
      expect(find.text(long), findsOneWidget);
      await filter('Advance');
      expect(find.text(long), findsNothing);
      await filter('Cleared');
      expect(find.text('Akinyi'), findsOneWidget);
    });
  });

  testWidgets('a new customer needs a phone, or the walk-in choice', (
    tester,
  ) async {
    await flow(
      tester,
      '/customers/new',
      contact: (name: 'Njeri Contact', phone: '+254 733 444 555'),
      (app) async {
        await tester.enterText(find.byType(TextFormField).first, 'Njeri');
        await tester.tap(find.text('Save'));
        await settle(tester);
        expect(find.textContaining('Enter a phone number'), findsOneWidget);

        await tester.enterText(find.byType(TextFormField).at(1), '12345');
        await tester.tap(find.text('Save'));
        await settle(tester);
        expect(find.textContaining('Not a phone number'), findsOneWidget);

        // Picked from contacts: the name stays as typed, the number is
        // shown the way shops say it.
        await tester.tap(find.byTooltip('Pick from contacts'));
        await settle(tester);
        expect(find.text('0733 444 555'), findsOneWidget);
        await tester.tap(find.text('Save'));
        await settle(tester);

        final saved = await (app.db.select(
          app.db.customers,
        )..where((c) => c.name.equals('Njeri'))).getSingle();
        expect(saved.phone, '+254733444555');
        expect(saved.syncState, SyncState.pending);
        expect(app.location, '/customers/${saved.id}');
      },
    );
  });

  testWidgets('a number another customer has offers that customer', (
    tester,
  ) async {
    await flow(tester, '/customers/new', (app) async {
      await tester.enterText(find.byType(TextFormField).first, 'Otieno again');
      await tester.enterText(find.byType(TextFormField).at(1), '+254700111222');
      await tester.tap(find.text('Save'));
      await settle(tester);
      expect(find.text('Otieno already has this number.'), findsOneWidget);
      await tester.tap(find.text('Open'));
      await settle(tester);
      expect(app.location, '/customers/0197a000-0000-7000-8000-00000000000c');
    });
  });

  testWidgets('a walk-in customer is saved with no phone', (tester) async {
    await flow(tester, '/customers/new', (app) async {
      await tester.enterText(find.byType(TextFormField).first, 'Walk-in Mary');
      await tester.tap(find.text('No phone (walk-in customer)'));
      await tester.tap(find.text('Save'));
      await settle(tester);
      final saved = await (app.db.select(
        app.db.customers,
      )..where((c) => c.name.equals('Walk-in Mary'))).getSingle();
      expect(saved.phone, isNull);
    });
  });

  testWidgets('a payment checks its M-Pesa code and warns of an advance', (
    tester,
  ) async {
    const otieno = '0197a000-0000-7000-8000-00000000000c';
    await flow(tester, '/customers/$otieno/payment', (app) async {
      await tester.enterText(find.byType(TextFormField).first, '500');
      await settle(tester);
      expect(find.textContaining('held as an advance'), findsOneWidget);

      await tester.tap(find.text('M-Pesa'));
      await settle(tester);
      await tester.enterText(find.byType(TextFormField).at(1), 'sjk4x7y2p');
      await tester.tap(find.text('Save'));
      await settle(tester);
      expect(
        find.text('An M-Pesa code is 10 letters and digits.'),
        findsOneWidget,
      );

      await tester.enterText(find.byType(TextFormField).at(1), 'sjk4x7y2pq');
      await tester.tap(find.text('Save'));
      await settle(tester);
      final payment =
          await (app.db.select(app.db.ledgerEntries)..where(
                (e) => e.customerId.equals(otieno) & e.reference.isNotNull(),
              ))
              .getSingle();
      expect(payment.reference, 'SJK4X7Y2PQ');
      expect(payment.paymentMethod, 'mpesa');
      expect(payment.description, 'M-Pesa');
      expect(app.location, '/customers/$otieno');
    });
  });

  testWidgets('a debt past the credit limit asks first', (tester) async {
    await flow(tester, '/customers/$longCustomerId/debt', (app) async {
      await tester.enterText(find.byType(TextFormField).first, '10');
      await tester.enterText(find.byType(TextFormField).at(1), 'Bread');
      await tester.tap(find.text('Save'));
      await settle(tester);
      expect(find.textContaining('over their limit'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      expect(app.location, '/customers/$longCustomerId/debt');

      await tester.tap(find.text('Save'));
      await settle(tester);
      await tester.tap(find.text('Record anyway'));
      await settle(tester);
      expect(app.location, '/customers/$longCustomerId');
    });
  });

  testWidgets('an entry shows who recorded it; owners void it', (tester) async {
    await flow(tester, '/customers/$longCustomerId/entries/$longEntryId', (
      app,
    ) async {
      expect(find.text('Wanjiru Nyambura Kamau-Odhiambo'), findsOneWidget);
      await tester.tap(find.text('Void entry'));
      await settle(tester);
      await tester.tap(find.text('Void entry').last);
      await settle(tester);
      final entry = await (app.db.select(
        app.db.ledgerEntries,
      )..where((e) => e.id.equals(longEntryId))).getSingle();
      expect(entry.isDeleted, isTrue);
      expect(entry.syncState, SyncState.pending);
    });
  });

  testWidgets('staff cannot void, delete or set a limit', (tester) async {
    await flow(
      tester,
      '/customers/$longCustomerId/entries/$longEntryId',
      role: Role.staff,
      (app) async => expect(find.text('Void entry'), findsNothing),
    );
    await flow(tester, '/customers/$longCustomerId', role: Role.staff, (
      app,
    ) async {
      await tester.tap(find.byTooltip('More options'));
      await settle(tester);
      expect(find.text('Edit customer'), findsOneWidget);
      expect(find.text('Delete customer'), findsNothing);
      expect(find.text('Set credit limit'), findsNothing);
    });
    // Opened directly, from an old link: back to the customer.
    await flow(
      tester,
      '/customers/$longCustomerId/limit',
      role: Role.staff,
      (app) async => expect(app.location, '/customers/$longCustomerId'),
    );
  });

  testWidgets('a credit limit: the amount is there to type, empty is none', (
    tester,
  ) async {
    const otieno = '0197a000-0000-7000-8000-00000000000c';
    Future<int?> limitOf(AppUnderTest app, String id) async =>
        (await (app.db.select(
          app.db.customers,
        )..where((c) => c.id.equals(id))).getSingle()).creditLimitCents;

    await flow(tester, '/customers/$otieno/limit', (app) async {
      expect(find.text('Remove limit'), findsNothing, reason: 'none set');
      await tester.enterText(find.byType(TextFormField), '5000');
      await tester.tap(find.text('Save'));
      await settle(tester);
      expect(await limitOf(app, otieno), 500000);
      expect(app.location, '/customers/$otieno');
    });
    await flow(tester, '/customers/$longCustomerId/limit', (app) async {
      await settle(tester);
      expect(find.text('100000'), findsOneWidget);
      await tester.tap(find.text('Remove limit'));
      await tester.tap(find.text('Save'));
      await settle(tester);
      expect(await limitOf(app, longCustomerId), isNull);
    });
  });

  testWidgets('a password can be shown while typing it', (tester) async {
    await flow(tester, '/sign-in', role: null, size: const Size(360, 800), (
      app,
    ) async {
      bool hidden() => tester
          .widget<EditableText>(
            find.descendant(
              of: find.byType(PasswordField),
              matching: find.byType(EditableText),
            ),
          )
          .obscureText;
      expect(hidden(), isTrue);
      await tester.tap(find.byTooltip('Show password'));
      await tester.pump();
      expect(hidden(), isFalse);
      await tester.tap(find.byTooltip('Hide password'));
      await tester.pump();
      expect(hidden(), isTrue);
    });
  });

  testWidgets('a customer who owes cannot be deleted', (tester) async {
    await flow(tester, '/customers/$longCustomerId', (app) async {
      await tester.tap(find.byTooltip('More options'));
      await settle(tester);
      await tester.tap(find.text('Delete customer'));
      await settle(tester);
      expect(find.textContaining('balance is zero'), findsOneWidget);
    });
  });

  testWidgets('a tablet shows the list and the customer side by side', (
    tester,
  ) async {
    await flow(
      tester,
      '/customers/$longCustomerId',
      size: const Size(1280, 800),
      (app) async {
        expect(find.text('Akinyi'), findsOneWidget, reason: 'the list');
        expect(find.text('Record payment'), findsOneWidget);
      },
    );
  });

  testWidgets('signed out, the sign-in screen leads to register and join', (
    tester,
  ) async {
    await flow(tester, '/sign-in', role: null, size: const Size(360, 800), (
      app,
    ) async {
      await tester.tap(find.text('New shop? Register it'));
      await settle(tester);
      expect(app.location, '/register');
      await tester.tap(find.text('Register'));
      await settle(tester);
      expect(find.text('At least 5 characters'), findsOneWidget);

      app.container.read(appRouterProvider).go('/join');
      await settle(tester);
      expect(find.text('Invite code'), findsOneWidget);
    });
  });
}
