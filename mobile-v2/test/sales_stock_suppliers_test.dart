// The flows of M4 through the real screens, on the seeded database: sales
// (and a credit sale's debt), stock notes, purchase orders (with B8's kept
// id) and suppliers, and who may do what. How each screen fits every size
// is the layout tests' job.

import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salio/app/router/app_router.dart';
import 'package:salio/core/database/app_database.dart';
import 'package:salio/core/network/api_exception.dart';
import 'package:salio/core/session/permissions.dart';
import 'package:salio/features/sales/domain/sale_debt.dart';
import 'package:salio/features/sales/presentation/customer_picker.dart';
import 'package:salio/features/stock/presentation/purchase_order_screen.dart';

import 'layout/harness.dart';
import 'support/fixtures.dart';

const _otieno = '0197a000-0000-7000-8000-00000000000c';

void main() {
  setUpAll(loadFonts);

  /// [real] also lets real time pass: a one-off database read, such as a
  /// form loading the record it edits, completes on real time, which a
  /// widget test's clock does not advance.
  Future<void> settle(WidgetTester tester, {bool real = false}) async {
    if (real) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
    }
    // Long enough for a page transition to finish.
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> flow(
    WidgetTester tester,
    String route,
    Future<void> Function(AppUnderTest app) body, {
    Role? role = Role.owner,
    FakePurchaseOrderApi? orders,
    List<File>? shared,
  }) async {
    addTearDown(() => resetView(tester));
    setView(tester, const Size(360, 1400));
    final app = await AppUnderTest.open(
      tester,
      role: role,
      route: route,
      orders: orders,
      overrides: [
        sharePdfProvider.overrideWithValue(
          (file, _) async => shared?.add(file),
        ),
        pdfFolderProvider.overrideWithValue(() async => Directory.systemTemp),
      ],
    );
    try {
      await settle(tester, real: true);
      await body(app);
      expect(app.errors, isEmpty);
    } finally {
      await app.close();
    }
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    final f = find.text(text);
    await tester.ensureVisible(f.first);
    await tester.tap(f.first);
    await settle(tester);
  }

  /// The form's button, where the screen's title says the same.
  Future<void> tapButton(WidgetTester tester, String text) async {
    final f = find.widgetWithText(ElevatedButton, text);
    await tester.ensureVisible(f);
    await tester.tap(f);
    await settle(tester);
  }

  Future<int> balanceOf(AppUnderTest app, String customerId) async {
    final rows =
        await (app.db.select(app.db.ledgerEntries)..where(
              (e) =>
                  e.customerId.equals(customerId) & e.isDeleted.equals(false),
            ))
            .get();
    return rows.fold<int>(
      0,
      (a, e) => a + (e.type == 'debt' ? e.amountCents : -e.amountCents),
    );
  }

  testWidgets('an M-Pesa sale keeps its checked code', (tester) async {
    await flow(tester, '/sales/new', (app) async {
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'Unga 2kg');
      await tester.enterText(fields.at(1), '2');
      await tester.enterText(fields.at(2), '360');
      await tapText(tester, 'M-Pesa');
      await tester.enterText(find.byType(TextFormField).at(3), 'sjk4x7');
      await tapText(tester, 'Save');
      expect(find.text('An M-Pesa code is 10 letters and digits.'), findsOne);

      await tester.enterText(find.byType(TextFormField).at(3), 'sjk4x7y2pq');
      await tapText(tester, 'Save');
      final sale = await (app.db.select(
        app.db.sales,
      )..where((s) => s.productName.equals('Unga 2kg'))).getSingle();
      expect(sale.quantity, 2000);
      expect(sale.amountCents, 36000);
      expect(sale.paymentMethod, 'mpesa');
      expect(sale.reference, 'SJK4X7Y2PQ');
      expect(sale.syncState, SyncState.pending);
      expect(app.location, '/sales');
      expect(find.text('Unga 2kg × 2'), findsOne);
    });
  });

  testWidgets('a credit sale needs a customer, and puts the server\'s debt '
      'on their account at once', (tester) async {
    await flow(tester, '/sales/new', (app) async {
      final before = await balanceOf(app, _otieno);
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'DAP 50kg');
      await tester.enterText(fields.at(1), '1.5');
      await tester.enterText(fields.at(2), '5250');
      await tapText(tester, 'Credit');
      await tapText(tester, 'Save');
      expect(find.text('A credit sale needs a customer.'), findsOne);

      await tapText(tester, 'Choose the customer');
      // The picker opens over the form: its own search box, not the form's.
      final search = find.descendant(
        of: find.byType(CustomerPicker),
        matching: find.byType(TextField),
      );
      await tester.enterText(search, '0700 111');
      await settle(tester);
      await tester.tap(
        find
            .descendant(
              of: find.byType(CustomerPicker),
              matching: find.text('Otieno'),
            )
            .first,
      );
      await settle(tester);
      await tapText(tester, 'Save');

      final sale = await (app.db.select(
        app.db.sales,
      )..where((s) => s.productName.equals('DAP 50kg'))).getSingle();
      final debt = await (app.db.select(
        app.db.ledgerEntries,
      )..where((e) => e.saleId.equals(sale.id))).getSingle();
      expect(debt.id, SaleDebt.idFor(sale.id));
      expect(debt.description, 'Sale: DAP 50kg x 1.5');
      expect(debt.customerId, _otieno);
      expect(await balanceOf(app, _otieno), before + 525000);
    });
  });

  testWidgets('voiding a credit sale takes its debt off the account', (
    tester,
  ) async {
    await flow(tester, '/customers/$_otieno/sale', (app) async {
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'Sugar 1kg');
      await tester.enterText(fields.at(2), '180');
      await tapText(tester, 'Save');
      expect(app.location, '/customers/$_otieno', reason: 'back to them');
      final sale = await (app.db.select(
        app.db.sales,
      )..where((s) => s.productName.equals('Sugar 1kg'))).getSingle();
      final before = await balanceOf(app, _otieno);

      app.container.read(appRouterProvider).go('/sales/${sale.id}');
      await settle(tester);
      await tapText(tester, 'Void sale');
      await tester.tap(find.text('Void sale').last);
      await settle(tester);
      expect(await balanceOf(app, _otieno), before - 18000);
      final voided = await (app.db.select(
        app.db.sales,
      )..where((s) => s.id.equals(sale.id))).getSingle();
      expect(voided.isDeleted, isTrue);
      expect(voided.syncState, SyncState.pending);
    });
  });

  testWidgets('staff sell but do not void, order or see suppliers', (
    tester,
  ) async {
    await flow(
      tester,
      '/sales/$longSaleId',
      role: Role.staff,
      (app) async => expect(find.text('Void sale'), findsNothing),
    );
    await flow(tester, '/stock', role: Role.staff, (app) async {
      expect(find.text('Place order'), findsNothing);
      expect(find.text('Note stock'), findsOne);
    });
    await flow(
      tester,
      '/stock/order',
      role: Role.staff,
      (app) async => expect(app.location, '/stock'),
    );
    await flow(
      tester,
      '/suppliers/$longSupplierId',
      role: Role.staff,
      (app) async => expect(app.location, '/home'),
    );
  });

  testWidgets('a stock note is added, and removed while not ordered', (
    tester,
  ) async {
    await flow(tester, '/stock/new', (app) async {
      await tester.enterText(find.byType(TextFormField).first, 'Kerosene 1L');
      await tapText(tester, 'Save');
      expect(app.location, '/stock');
      expect(find.text('Kerosene 1L'), findsOne);

      await tapText(tester, 'Kerosene 1L');
      await settle(tester, real: true);
      await tapText(tester, 'Remove');
      await tester.tap(find.text('Remove').last);
      await settle(tester);
      expect(find.text('Kerosene 1L'), findsNothing);
      final note = await (app.db.select(
        app.db.stockRequests,
      )..where((r) => r.productName.equals('Kerosene 1L'))).getSingle();
      expect(note.isDeleted, isTrue, reason: 'a tombstone, not a delete');
    });
  });

  testWidgets('a note on an order cannot change', (tester) async {
    await flow(tester, '/stock/0197a000-0000-7000-8000-0000000005d3', (
      app,
    ) async {
      expect(
        find.text(
          'This is on a purchase order. Cancel the order to change it.',
        ),
        findsOne,
      );
      expect(find.text('Remove'), findsNothing);
    });
  });

  testWidgets('placing an order: every product needs a quantity, and a '
      'retry after a failure sends the same id (B8)', (tester) async {
    final orders = FakePurchaseOrderApi()
      ..failure = const ApiException(ApiFailure.offline);
    await flow(tester, '/stock/order', orders: orders, (app) async {
      await tester.enterText(find.byType(TextFormField).first, 'Twiga');
      await tapButton(tester, 'Place order');
      expect(find.text('How many?'), findsWidgets);
      expect(orders.placed, isEmpty, reason: 'nothing sent until valid');

      final quantities = find.widgetWithText(TextFormField, 'Quantity');
      await tester.enterText(quantities.at(0), '12');
      await tester.enterText(quantities.at(1), '6');
      await tapButton(tester, 'Place order');
      expect(
        find.text('No connection. Check your bundle or Wi-Fi and try again.'),
        findsOne,
      );

      orders.failure = null;
      await tapButton(tester, 'Place order');
      expect(orders.placed, hasLength(2));
      expect(orders.placed.toSet(), hasLength(1), reason: 'one id, kept');
      expect(app.location, '/stock/orders/${orders.placed.first}');
    });
  });

  testWidgets('an order is shared as a PDF, and cancelled by the owner', (
    tester,
  ) async {
    final orders = FakePurchaseOrderApi();
    final shared = <File>[];
    await flow(
      tester,
      '/stock/orders/$longOrderId',
      orders: orders,
      shared: shared,
      (app) async {
        await tester.tap(find.text('Share PDF'));
        // The PDF is written to a real file, which takes real time.
        for (var i = 0; i < 20 && shared.isEmpty; i++) {
          await settle(tester, real: true);
        }
        expect(shared.single.path, endsWith('PO-0107.pdf'));
        expect(shared.single.readAsStringSync(), startsWith('%PDF'));

        await tapText(tester, 'Cancel order');
        await tester.tap(find.text('Cancel order').last);
        await settle(tester);
        expect(orders.cancelled, [longOrderId]);
      },
    );
  });

  testWidgets('offline, the orders tab says it needs a connection', (
    tester,
  ) async {
    final orders = FakePurchaseOrderApi()
      ..failure = const ApiException(ApiFailure.offline);
    await flow(tester, '/stock?tab=orders', orders: orders, (app) async {
      expect(
        find.textContaining('Purchase orders need a connection.'),
        findsOne,
      );
    });
  });

  testWidgets('a supplier: added, billed, paid, and kept while owed', (
    tester,
  ) async {
    await flow(tester, '/suppliers/new', (app) async {
      await tester.enterText(find.byType(TextFormField).at(0), 'Bidco');
      await tester.enterText(find.byType(TextFormField).at(1), '0733 444 555');
      await tapText(tester, 'Save');
      final s = await (app.db.select(
        app.db.suppliers,
      )..where((s) => s.name.equals('Bidco'))).getSingle();
      expect(s.phone, '+254733444555');
      expect(app.location, '/suppliers/${s.id}');

      await tapText(tester, 'Record bill');
      await tester.enterText(find.byType(TextFormField).at(0), '10000');
      await tester.enterText(find.byType(TextFormField).at(1), 'Invoice 9');
      await tapText(tester, 'Save');
      await tapText(tester, 'Pay supplier');
      await tester.enterText(find.byType(TextFormField).at(0), '4000');
      await tester.enterText(find.byType(TextFormField).at(1), 'Part');
      await tapText(tester, 'Save');
      expect(find.text('KES 6,000'), findsOne);
      expect(find.text('We owe'), findsOne);

      await tester.tap(find.byTooltip('More options'));
      await settle(tester);
      await tapText(tester, 'Delete supplier');
      expect(find.textContaining('balance is zero'), findsOne);
    });
  });
}
