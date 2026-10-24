// The sync engine against a fake server that fails in every way a shop's
// connection does (docs/10, M2 exit): killed mid-push, lost and repeated
// answers, timeouts, a 500, a moved clock. Each test says what would be
// lost or doubled if the rule it checks were broken.

import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salio/core/database/app_database.dart';
import 'package:salio/core/network/api_client.dart';
import 'package:salio/core/network/api_exception.dart';
import 'package:salio/core/sync/sync_engine.dart';
import 'package:salio/core/time/server_clock.dart';
import 'package:salio/features/customers/data/customer_repository.dart';
import 'package:salio/features/ledger/data/ledger_repository.dart';

import '../support/fake_server.dart';

const me = '0197a000-0000-7000-8000-0000000000u1';

/// One phone: its database, and a sync engine that can be replaced, as an
/// app killed and opened again would.
class Rig {
  final server = FakeServer();
  final db = AppDatabase(NativeDatabase.memory());
  var deviceNow = DateTime.utc(2026, 10, 24, 8);
  late final clock = ServerClock(deviceNow: () => deviceNow);
  late SyncEngine engine = open();

  Rig() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    server.now = () => deviceNow;
  }

  /// A new engine on the same database, as after the app was killed.
  SyncEngine open({int pageSize = 200, int maxPageSize = 2000}) =>
      engine = SyncEngine(
        db,
        ApiClient(
          origin: Uri.parse('http://fake'),
          token: () => 't',
          appHeader: 'test',
          adapter: server,
        ),
        clock,
        pageSize: pageSize,
        maxPageSize: maxPageSize,
      );

  CustomerRepository get customers => CustomerRepository(db, clock, me);
  LedgerRepository get ledger => LedgerRepository(db, clock, me);

  Future<SyncReport> sync({String? access}) => engine.sync(access: access);

  Future<CustomerRow?> customer(String id) => (db.select(
    db.customers,
  )..where((c) => c.id.equals(id))).getSingleOrNull();

  Future<List<SyncIssueRow>> issues() => db.select(db.syncIssues).get();

  Map<String, dynamic> serverCustomer(String id, {String name = 'Wanjiku'}) => {
    'id': id,
    'name': name,
    'created_by': me,
    'created_at': '2026-10-01T08:00:00.000Z',
    'updated_at': '2026-10-01T08:00:00.000Z',
    'is_deleted': false,
  };

  Future<void> close() => db.close();
}

void main() {
  late Rig rig;
  setUp(() => rig = Rig());
  tearDown(() => rig.close());

  group('pushing', () {
    test('a push killed before its answer goes again, the same batch, '
        'and is recorded once', () async {
      final id = await rig.customers.add(name: 'Wanjiku');
      rig.server.faults.add(Fault.lostAnswer);
      await expectLater(rig.sync(), throwsA(isA<ApiException>()));

      // Edited while the first answer was lost: it must not ride along
      // under the old operation id, whose replayed answer would never
      // mention it.
      await rig.customers.update(id, phone: '0712000001');
      rig.open(); // the app was killed and opened again
      await rig.sync();

      final [first, again, edit] = rig.server.pushes;
      final sent = (edit['customers'] as List).cast<Map<String, dynamic>>();
      expect(again, first, reason: 'a retry sends the frozen body');
      expect(edit['operation_id'], isNot(first['operation_id']));
      expect(sent.single['phone'], '0712000001');
      expect(rig.server.records['customers'], hasLength(1));
      expect((await rig.customer(id))!.syncState, SyncState.synced);
    });

    test('a timeout keeps the batch, and the next sync sends it', () async {
      await rig.ledger.recordDebt(
        customerId: await rig.customers.add(name: 'Wanjiku'),
        amountCents: 50000,
        description: 'Sugar',
      );
      rig.server.faults.add(Fault.timeout);
      await expectLater(
        rig.sync(),
        throwsA(
          isA<ApiException>().having((e) => e.kind, 'kind', ApiFailure.timeout),
        ),
      );
      expect(await rig.db.select(rig.db.pushBatches).get(), hasLength(1));

      await rig.sync();
      expect(rig.server.records['transactions'], hasLength(1));
      expect(await rig.db.select(rig.db.pushBatches).get(), isEmpty);
    });

    test('a 500 changes nothing on the phone', () async {
      final id = await rig.customers.add(name: 'Wanjiku');
      rig.server.faults.add(Fault.serverError);
      await expectLater(
        rig.sync(),
        throwsA(
          isA<ApiException>().having((e) => e.kind, 'kind', ApiFailure.server),
        ),
      );
      expect((await rig.customer(id))!.syncState, SyncState.pending);

      await rig.sync();
      expect((await rig.customer(id))!.syncState, SyncState.synced);
    });

    test('a replayed answer settles the batch once', () async {
      final id = await rig.customers.add(name: 'Wanjiku', phone: '0712');
      rig.server.refuse = (kind, r) => 'duplicate';
      rig.server.faults.add(Fault.lostAnswer);
      await expectLater(rig.sync(), throwsA(isA<ApiException>()));
      await rig.sync();

      expect(await rig.issues(), hasLength(1), reason: 'not one per answer');
      expect((await rig.customer(id))!.syncState, SyncState.refused);
    });

    test('a debt is dated by the server clock, however wrong the phone '
        'clock is', () async {
      // The phone thinks it is three hours earlier than it is.
      rig.server.now = () => rig.deviceNow.add(const Duration(hours: 3));
      await rig.sync();
      final id = await rig.ledger.recordDebt(
        customerId: 'c',
        amountCents: 100,
        description: 'Bread',
      );
      final entry = await (rig.db.select(
        rig.db.ledgerEntries,
      )..where((e) => e.id.equals(id))).getSingle();
      expect(entry.createdAt, rig.server.now());

      // And remembered when the app opens again.
      final reopened = ServerClock(deviceNow: () => rig.deviceNow);
      rig.engine = SyncEngine(rig.db, rig.engine.api, reopened);
      rig.server.faults.add(Fault.offline);
      await expectLater(rig.engine.sync(), throwsA(isA<ApiException>()));
      expect(reopened.offset, const Duration(hours: 3));
    });

    test('parents go before what points to them, across batches', () async {
      for (var i = 0; i < SyncEngine.maxBatchRecords + 5; i++) {
        await rig.customers.add(name: 'Customer $i');
      }
      final last = (await rig.db.select(rig.db.customers).get()).last;
      await rig.ledger.recordDebt(
        customerId: last.id,
        amountCents: 100,
        description: 'Bread',
      );
      await rig.sync();
      final [first, second] = rig.server.pushes;
      expect(first['transactions'], isNull);
      expect(second['transactions'], hasLength(1));
    });
  });

  group('conflicts', () {
    test('a refused delete brings the customer back, with a note', () async {
      const id = '0197a000-0000-7000-8000-000000000c01';
      rig.server.put('customers', rig.serverCustomer(id));
      await rig.sync();
      await rig.customers.delete(id);
      rig.server.refuse = (kind, r) => 'has_balance';
      await rig.sync();

      final c = (await rig.customer(id))!;
      expect(c.isDeleted, isFalse, reason: 'the server kept the customer');
      expect(c.syncState, SyncState.synced);
      expect((await rig.issues()).single.reason, 'has_balance');
    });

    test('a lost field takes the server value without a word', () async {
      const id = '0197a000-0000-7000-8000-000000000c02';
      rig.server.put('customers', {
        ...rig.serverCustomer(id),
        'phone': '0722999999',
      });
      await rig.sync();
      await rig.customers.update(id, phone: '0700000000');
      rig.server.refuse = (kind, r) => 'stale_write';
      await rig.sync();

      expect((await rig.customer(id))!.phone, '0722999999');
      expect(await rig.issues(), isEmpty);
    });

    test('a refused record is kept aside and not sent again', () async {
      final id = await rig.customers.add(name: 'Wanjiku', phone: '0712');
      rig.server.refuse = (kind, r) => 'duplicate';
      await rig.sync();
      rig.server.refuse = null;
      await rig.sync();

      expect(rig.server.pushes, hasLength(1));
      expect((await rig.customer(id))!.syncState, SyncState.refused);
      expect((await rig.issues()).single.serverCopy, isNull);
    });

    test('a reason this app does not know refuses, never drops', () async {
      final id = await rig.customers.add(name: 'Wanjiku');
      rig.server.refuse = (kind, r) => 'reason_from_the_future';
      await rig.sync();
      expect((await rig.customer(id))!.syncState, SyncState.refused);
    });

    test(
      'an entry waiting for its customer goes once the customer is in',
      () async {
        final customer = await rig.customers.add(name: 'Wanjiku');
        final debt = await rig.ledger.recordDebt(
          customerId: customer,
          amountCents: 100,
          description: 'Bread',
        );
        rig.server.refuse = (kind, r) =>
            kind == 'customers' ? 'invalid' : 'unknown_customer';
        await rig.sync();
        expect(await rig.issues(), hasLength(2));

        // The customer is sorted out (here: the server takes it on a retry).
        rig.server.refuse = null;
        await (rig.db.update(
          rig.db.customers,
        )..where((c) => c.id.equals(customer))).write(
          const CustomersCompanion(syncState: Value(SyncState.pending)),
        );
        await rig.sync(); // the customer goes in
        await rig.sync(); // then the entry is released and goes

        expect(rig.server.records['transactions']!.keys, [debt]);
        expect(await rig.issues(), isEmpty, reason: 'both were answered');
      },
    );

    test('an older server without copies still settles the push', () async {
      const id = '0197a000-0000-7000-8000-000000000c03';
      rig.server
        ..sendsCurrent = false
        ..put('customers', rig.serverCustomer(id));
      await rig.sync();
      await rig.customers.update(id, notes: 'pays Fridays');
      rig.server.refuse = (kind, r) => 'stale_write';
      await rig.sync();
      expect((await rig.customer(id))!.syncState, SyncState.synced);
    });

    test(
      'an edit made while the batch was out survives the server copy',
      () async {
        const id = '0197a000-0000-7000-8000-000000000c04';
        rig.server.put('customers', rig.serverCustomer(id));
        await rig.sync();
        await rig.customers.update(id, phone: '0700000000');
        rig.server.refuse = (kind, r) => 'stale_write';
        rig.server.faults.add(Fault.lostAnswer);
        await expectLater(rig.sync(), throwsA(isA<ApiException>()));
        await rig.customers.update(id, notes: 'pays Fridays');
        // The replay still answers stale_write; the new batch is accepted.
        rig.server.refuse = null;
        await rig.sync();

        final c = (await rig.customer(id))!;
        expect(c.notes, 'pays Fridays');
        expect(rig.server.records['customers']![id]!['notes'], 'pays Fridays');
      },
    );
  });

  group('pulling', () {
    test('a 500 part way through keeps the pages already saved', () async {
      for (var i = 0; i < 5; i++) {
        rig.server.put(
          'customers',
          rig.serverCustomer('0197a000-0000-7000-8000-00000000010$i'),
        );
      }
      rig.open(pageSize: 2, maxPageSize: 2);
      // Two pages arrive; the third fails.
      rig.server.onPull = (cursor, limit) {
        if (rig.server.pullLimits.length == 2) {
          rig.server.faults.add(Fault.serverError);
        }
      };
      await expectLater(rig.sync(), throwsA(isA<ApiException>()));
      final saved = await rig.db.select(rig.db.customers).get();
      expect(saved, hasLength(4));
      expect(await rig.db.readMeta('cursor'), '4');

      rig.server.onPull = null;
      await rig.sync();
      expect(await rig.db.select(rig.db.customers).get(), hasLength(5));
    });

    test('pages grow while they arrive quickly and shrink after a '
        'timeout', () async {
      for (var i = 0; i < 40; i++) {
        rig.server.put(
          'customers',
          rig.serverCustomer(
            '0197a000-0000-7000-8000-0000000002${i.toString().padLeft(2, '0')}',
          ),
        );
      }
      rig.open(pageSize: 25, maxPageSize: 200);
      await rig.sync();
      expect(rig.server.pullLimits.take(2), [25, 50]);

      // A slow line: every page takes 10 s, and one times out.
      rig.server.pullLimits.clear();
      rig.server.onPull = (cursor, limit) =>
          rig.deviceNow = rig.deviceNow.add(const Duration(seconds: 10));
      rig.server.faults.add(Fault.timeout);
      await rig.sync();
      // The timed-out request never reached the fake, so its limit is
      // not listed: the first listed pull is already the halved one.
      final before = rig.engine.currentPageSize;
      expect(rig.server.pullLimits.first, before);
      expect(before, lessThan(100));
    });

    test('a resync removes what the server no longer has, keeps what is '
        'unsent, and never empties the list on the way', () async {
      const kept = '0197a000-0000-7000-8000-000000000301';
      const purged = '0197a000-0000-7000-8000-000000000302';
      rig.server
        ..put('customers', rig.serverCustomer(kept, name: 'Kept'))
        ..put('customers', rig.serverCustomer(purged, name: 'Purged'));
      await rig.sync();
      final unsent = await rig.customers.add(name: 'Unsent');

      // Away past the horizon: the server forgot a deletion meanwhile.
      rig.server
        ..purge('customers', purged)
        ..put('customers', rig.serverCustomer(kept, name: 'Kept again'));
      final seen = <Set<String>>[];
      final watching = rig.customers.watchAll().listen(
        (list) => seen.add({for (final c in list) c.customer.name}),
      );
      rig.server.faults.add(Fault.offline); // the push fails: still unsent
      await expectLater(rig.sync(), throwsA(isA<ApiException>()));
      final report = await rig.engine.sync();
      await Future<void>.delayed(Duration.zero);
      await watching.cancel();

      expect(report.resynced, isTrue);
      final names = {
        for (final c in await rig.db.select(rig.db.customers).get()) c.name,
      };
      expect(names, {'Kept again', 'Unsent'});
      expect(await rig.customer(unsent), isNotNull);
      expect(
        seen.every((s) => s.isNotEmpty),
        isTrue,
        reason: 'the screen was never emptied: $seen',
      );
    });

    test('a resync cut short carries on, and removes nothing it saw', () async {
      String id(int i) => '0197a000-0000-7000-8000-00000000040$i';
      for (var i = 0; i < 4; i++) {
        rig.server.put('customers', rig.serverCustomer(id(i)));
      }
      await rig.sync();
      rig.server
        ..purge('customers', id(0))
        ..put('customers', rig.serverCustomer(id(4)))
        ..put('customers', rig.serverCustomer(id(5)));
      // Pages of four: the first reaches past the horizon, so the resync
      // can carry on from it. The second fails.
      rig.open(pageSize: 4, maxPageSize: 4);
      final pulls = rig.server.pullLimits.length;
      rig.server.onPull = (cursor, limit) {
        if (rig.server.pullLimits.length == pulls + 2) {
          rig.server.faults.add(Fault.offline);
        }
      };
      await expectLater(rig.sync(), throwsA(isA<ApiException>()));
      expect(await rig.db.readMeta('resync'), '1');
      rig.server.onPull = null;
      final report = await rig.sync();

      expect(report.resynced, isTrue);
      final ids = {
        for (final c in await rig.db.select(rig.db.customers).get()) c.id,
      };
      expect(ids, {id(1), id(2), id(3), id(4), id(5)});
      expect(await rig.db.select(rig.db.resyncSeen).get(), isEmpty);
    });

    test('a role change pulls everything again', () async {
      const supplier = '0197a000-0000-7000-8000-000000000501';
      rig.server.put('suppliers', {
        'id': supplier,
        'name': 'Elgon Kenya',
        'created_by': me,
        'created_at': '2026-10-01T08:00:00.000Z',
        'updated_at': '2026-10-01T08:00:00.000Z',
        'is_deleted': false,
      });
      await rig.sync(access: 'owner');
      expect(await rig.db.select(rig.db.suppliers).get(), hasLength(1));

      // Now staff: the server stops showing suppliers.
      rig.server.hidden.add('suppliers');
      final report = await rig.sync(access: 'staff');
      expect(report.resynced, isTrue);
      expect(await rig.db.select(rig.db.suppliers).get(), isEmpty);
    });

    test('lists and fields this app does not know are ignored', () async {
      rig.server
        ..put('loyalty_cards', {'id': 'x'})
        ..put('customers', {
          ...rig.serverCustomer('0197a000-0000-7000-8000-000000000601'),
          'nickname': 'Shiku',
        });
      await rig.sync();
      expect(await rig.db.select(rig.db.customers).get(), hasLength(1));
    });
  });

  test('every kind travels both ways', () async {
    // Each of the six kinds arrives from the server and is stored.
    const at = '2026-10-01T08:00:00.000Z';
    rig.server
      ..put('customers', rig.serverCustomer('c1'))
      ..put('suppliers', {
        'id': 's1',
        'name': 'Elgon',
        'created_by': me,
        'created_at': at,
        'updated_at': at,
      })
      ..put('sales', {
        'id': 'sa1',
        'customer_id': 'c1',
        'user_id': me,
        'product_name': 'DAP 50kg',
        'quantity': '1.5',
        'amount': '3500.00',
        'payment_method': 'credit',
        'sale_date': at,
        'created_at': at,
        'updated_at': at,
      })
      ..put('transactions', {
        'id': 't1',
        'customer_id': 'c1',
        'user_id': me,
        'type': 'debt',
        'amount': '3500.00',
        'sale_id': 'sa1',
        'transaction_date': at,
        'created_at': at,
        'updated_at': at,
      })
      ..put('supplier_transactions', {
        'id': 'st1',
        'supplier_id': 's1',
        'user_id': me,
        'type': 'bill',
        'amount': '5000.00',
        'description': 'Invoice 1',
        'transaction_date': at,
        'created_at': at,
        'updated_at': at,
      })
      ..put('stock_requests', {
        'id': 'r1',
        'user_id': me,
        'product_name': 'Duodip',
        'needed_on': at,
        'purchase_order_id': 'po1',
        'created_at': at,
        'updated_at': at,
      });
    await rig.sync();
    final sale = await rig.db.select(rig.db.sales).getSingle();
    expect(sale.quantity, 1500);
    expect(sale.amountCents, 350000);
    expect(
      (await rig.db.select(rig.db.stockRequests).getSingle()).purchaseOrderId,
      'po1',
    );
    expect(await rig.db.select(rig.db.supplierEntries).get(), hasLength(1));

    // A void of the sale's debt is the server's to make: never sent.
    await rig.db
        .update(rig.db.ledgerEntries)
        .write(
          const LedgerEntriesCompanion(syncState: Value(SyncState.pending)),
        );
    // And a sale made here goes up with its quantity as the server reads it.
    await rig.db
        .update(rig.db.sales)
        .write(
          const SalesCompanion(
            syncState: Value(SyncState.pending),
            localVersion: Value(1),
          ),
        );
    await rig.sync();
    final push = rig.server.pushes.single;
    expect(push['transactions'], isNull);
    final sales = (push['sales'] as List).cast<Map<String, dynamic>>();
    expect(sales.single['quantity'], '1.5');
    expect(jsonEncode(push), isNot(contains('purchase_order_id')));
  });
}
