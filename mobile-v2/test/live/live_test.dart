// Simulated phones against a real server-v2 (docs/10, §8.2). Each phone runs
// the app's own database, sync engine and network code.
//
//   mobile-v2/scripts/live-server.sh &          # a throwaway server on :8091
//   SALIO_LIVE_URL=http://127.0.0.1:8091 flutter test test/live
//
// Without SALIO_LIVE_URL these tests are skipped; CI's mobile-v2-live job
// sets it.

import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salio/core/database/app_database.dart';
import 'package:salio/core/network/api_client.dart';
import 'package:salio/core/network/api_exception.dart';
import 'package:salio/core/phone/phone.dart' as phone_rule;
import 'package:salio/core/session/permissions.dart';
import 'package:salio/features/app_update/data/app_update_service.dart';
import 'package:salio/features/ledger/domain/payment_reference.dart';
import 'package:salio/features/sales/data/sales_repository.dart';
import 'package:salio/features/sales/domain/sale_debt.dart';
import 'package:salio/features/stock/data/purchase_order_api.dart';

import '../support/fake_app_update.dart';

import '../support/phone.dart';

final _url = Platform.environment['SALIO_LIVE_URL'];
final _skip = _url == null ? 'set SALIO_LIVE_URL (see the header)' : null;

final _random = Random();

/// A phone number nobody else in this database has.
String _newPhone() =>
    '07${List.generate(8, (_) => _random.nextInt(10)).join()}';

const _password = 'live-test-pass';

/// A new shop with an owner on phone A and a member of staff on phone B.
Future<({Phone a, Phone b, String ownerPhone, String staffPhone})> _newShop({
  int pageSizeB = 200,
}) async {
  final server = Uri.parse(_url!);
  final rest = ApiClient(origin: server, token: () => null, appHeader: 'test');
  final ownerPhone = _newPhone();
  final registered =
      await rest.post('/auth/register-business', {
            'business_name': 'Live Test Shop',
            'name': 'Owner Amina',
            'phone': ownerPhone,
            'password': _password,
          })
          as Map<String, dynamic>;
  final ownerToken = registered['token'] as String;
  final invite =
      await ApiClient(
            origin: server,
            token: () => ownerToken,
            appHeader: 'test',
          ).post('/auth/invite', {})
          as Map<String, dynamic>;
  final staffPhone = _newPhone();
  await rest.post('/auth/join', {
    'code': invite['code'],
    'name': 'Staff Juma',
    'phone': staffPhone,
    'password': _password,
  });

  final a = await Phone.signIn(
    server,
    'A',
    phone: ownerPhone,
    password: _password,
  );
  final b = await Phone.signIn(
    server,
    'B',
    phone: staffPhone,
    password: _password,
    pageSize: pageSizeB,
  );
  addTearDown(a.close);
  addTearDown(b.close);
  return (a: a, b: b, ownerPhone: ownerPhone, staffPhone: staffPhone);
}

void main() {
  group('live', skip: _skip, () {
    test('the updater finds, downloads and checks the published release, '
        'before anyone signs in', () async {
      final dir = Directory.systemTemp.createTempSync('updates');
      addTearDown(() => dir.deleteSync(recursive: true));
      final service = AppUpdateService(
        Dio(BaseOptions(baseUrl: _url!)),
        FakeInstaller(dir: dir.path),
      );
      final release = await service.fetchLatest();
      expect(release, isNotNull);
      expect(release!.build, 999);
      expect(release.rolloutPercent, 100);
      expect(release.notesIn('sw'), 'Toleo la majaribio');
      final path = await service.download(release, 'arm64');
      expect(File(path).lengthSync(), release.files['arm64']!.size);
      // And again: already there, nothing downloaded twice.
      expect(await service.downloaded(release, 'arm64'), path);
    });

    test('sign-in carries what each person may do (B5), and any form of '
        'the number signs in (B15)', () async {
      final shop = await _newShop();
      expect(shop.a.account.permissions, contains(Permission.customersDelete));
      expect(
        shop.b.account.permissions,
        isNot(contains(Permission.customersDelete)),
      );
      expect(
        shop.b.account.permissions!.toSet(),
        Role.staff.permissions,
        reason: 'the server and the app agree on what staff may do',
      );
      // The owner's number, in another form.
      final national = phone_rule.Phone.display(
        shop.a.account.phone,
      ).replaceAll(' ', '');
      final again = await Phone.signIn(
        Uri.parse(_url!),
        'A again',
        phone: '+254${national.substring(1)}',
        password: _password,
      );
      addTearDown(again.close);
      expect(again.account.userId, shop.a.account.userId);
      expect(shop.a.account.phone, startsWith('+254'));
    });

    test('1: a debt recorded offline on phone A appears on phone B', () async {
      final shop = await _newShop();

      // Offline on A: nothing here touches the network.
      final otieno = await shop.a.customers.add(
        name: 'Otieno',
        phone: '0711222333',
      );
      await shop.a.ledger.recordDebt(
        customerId: otieno,
        amountCents: 150050,
        description: 'Sugar and flour',
      );
      expect(await shop.a.balances(), {'Otieno': 150050});
      expect(await shop.a.pendingCount(), 2);

      final pushed = await shop.a.sync.sync();
      expect(pushed.pushed, 2);
      expect(pushed.conflicts, 0);
      expect(await shop.a.pendingCount(), 0);

      await shop.b.sync.sync();
      expect(await shop.b.balances(), {'Otieno': 150050});
      final entries = await shop.b.ledger.watchFor(otieno).first;
      expect(entries.single.description, 'Sugar and flour');
      expect(
        entries.single.userId,
        shop.a.account.userId,
        reason: 'recorded by',
      );
    });

    test('2: a write committed during B\'s pull still reaches B on the next '
        'pull', () async {
      // Pages of one record, so B's pull takes several requests.
      final shop = await _newShop(pageSizeB: 1);
      for (final name in ['Akinyi', 'Baraka', 'Chebet']) {
        await shop.a.customers.add(name: name);
      }
      await shop.a.sync.sync();
      final akinyi =
          (await shop.a.customers.watchAll().first).first.customer.id;

      // While B is in the middle of its pull, A records and pushes a debt.
      var interrupted = false;
      shop.b.adapter.afterResponse = (request, _) async {
        if (interrupted || !request.path.endsWith('/sync/pull')) return;
        interrupted = true;
        await shop.a.ledger.recordDebt(
          customerId: akinyi,
          amountCents: 20000,
          description: 'Bread',
        );
        await shop.a.sync.sync();
      };
      await shop.b.sync.sync();
      expect(interrupted, isTrue);
      shop.b.adapter.afterResponse = null;

      // Whatever B's first sync saw, the next one must bring the debt.
      await shop.b.sync.sync();
      expect((await shop.b.balances())['Akinyi'], 20000);
      expect(await shop.b.balances(), await shop.a.balances());
    });

    test('3: a push whose answer was lost is recorded once', () async {
      final shop = await _newShop();
      final customer = await shop.a.customers.add(name: 'Wanjiru');
      await shop.a.ledger.recordDebt(
        customerId: customer,
        amountCents: 50000,
        description: 'Rice',
      );

      // The server applies the batch; the answer never reaches the phone.
      shop.a.adapter.afterResponse = (request, _) {
        if (request.path.endsWith('/sync/push')) {
          throw DioException.connectionError(
            requestOptions: request,
            reason: 'answer lost',
          );
        }
      };
      await expectLater(
        shop.a.sync.sync(),
        throwsA(
          isA<ApiException>().having((e) => e.kind, 'kind', ApiFailure.offline),
        ),
      );
      // Edited while the batch is in flight: must go in the next batch, not
      // vanish under the replayed answer.
      await shop.a.ledger.recordDebt(
        customerId: customer,
        amountCents: 1000,
        description: 'Matches',
      );
      shop.a.adapter.afterResponse = null;

      await shop.a.sync.sync();
      expect(await shop.a.pendingCount(), 0);
      await shop.b.sync.sync();
      expect(await shop.b.balances(), {'Wanjiru': 51000});
    });

    test('the server refuses a debt with no description, and says so', () async {
      final shop = await _newShop();
      final customer = await shop.a.customers.add(name: 'Kamau');
      await shop.a.sync.sync();
      // Straight into the database: the repository would refuse it first.
      await shop.a.db.customStatement(
        'INSERT INTO ledger_entries (id, customer_id, user_id, type, amount_cents, '
        'description, transaction_date, created_at, updated_at, sync_state) VALUES '
        "('0197a000-0000-7000-8000-00000000c0de', '$customer', "
        "'${shop.a.account.userId}', 'debt', 100, '  ', "
        "'2026-10-19T08:00:00.000Z', '2026-10-19T08:00:00.000Z', "
        "'2026-10-19T08:00:00.000Z', 1)",
      );
      final report = await shop.a.sync.sync();
      expect(report.conflicts, 1);
      final issues = await shop.a.db.select(shop.a.db.syncIssues).get();
      expect(issues.single.reason, 'invalid');
      expect(
        await shop.a.pendingCount(),
        0,
        reason: 'refused, not resent forever',
      );
    });

    test('4: two phones edit one customer offline, different fields, and '
        'both edits survive', () async {
      final shop = await _newShop();
      final id = await shop.a.customers.add(name: 'Njeri');
      await shop.a.syncNow();
      await shop.b.syncNow();

      // Both offline: A changes the phone number, B the notes.
      await shop.a.customers.update(id, phone: '0722000111');
      await shop.b.customers.update(id, notes: 'Pays on Fridays');
      await shop.a.syncNow();
      await shop.b.syncNow();
      await shop.a.syncNow();

      for (final phone in [shop.a, shop.b]) {
        final c = await phone.customer(id);
        expect(c.phone, '+254722000111', reason: phone.label);
        expect(c.notes, 'Pays on Fridays', reason: phone.label);
        expect(c.syncState, SyncState.synced);
      }
      expect(await shop.b.issues(), isEmpty);
    });

    test('5: one M-Pesa payment recorded on both phones offline is counted '
        'once, and the copy can be discarded', () async {
      final shop = await _newShop();
      final id = await shop.a.customers.add(name: 'Wairimu');
      await shop.a.ledger.recordDebt(
        customerId: id,
        amountCents: 100000,
        description: 'Fertiliser',
      );
      await shop.a.syncNow();
      await shop.b.syncNow();

      for (final phone in [shop.a, shop.b]) {
        await phone.ledger.recordPayment(
          customerId: id,
          amountCents: 40000,
          method: PaymentMethod.mpesa,
          reference: 'sjk4x7y2pq',
          description: 'M-Pesa',
        );
      }
      await shop.a.syncNow();
      final report = await shop.b.syncNow();
      expect(report.conflicts, 1);

      final [issue] = await shop.b.issues();
      expect(issue.reason, 'duplicate');
      expect(issue.recordTable, 'transactions');
      await shop.b.attention.discard(issue);

      expect(await shop.b.issues(), isEmpty);
      expect(await shop.b.balances(), {'Wairimu': 60000});
      expect(await shop.b.balances(), await shop.a.serverBalances());
    });

    test('6: staff void an entry and delete a customer offline; both are '
        'refused and the phone shows the server copy', () async {
      final shop = await _newShop();
      final id = await shop.a.customers.add(name: 'Kiprono');
      final debt = await shop.a.ledger.recordDebt(
        customerId: id,
        amountCents: 25000,
        description: 'Maize flour',
      );
      final spare = await shop.a.customers.add(name: 'Spare');
      await shop.a.syncNow();
      await shop.b.syncNow();

      await shop.b.ledger.voidEntry(debt);
      await shop.b.customers.delete(spare);
      expect(await shop.b.balances(), {'Kiprono': 0});
      final report = await shop.b.syncNow();
      expect(report.conflicts, 2);

      // Back as the server holds them, with a note for each.
      expect(await shop.b.balances(), {'Kiprono': 25000, 'Spare': 0});
      final issues = await shop.b.issues();
      expect(issues.map((i) => i.reason), everyElement('forbidden'));
      expect(issues, hasLength(2));
      expect(await shop.b.pendingCount(), 0);
    });

    test('7: deleting a customer who owes money is refused, and the '
        'customer comes back', () async {
      final shop = await _newShop();
      final id = await shop.a.customers.add(name: 'Mutua');
      await shop.a.ledger.recordDebt(
        customerId: id,
        amountCents: 5000,
        description: 'Soap',
      );
      await shop.a.syncNow();

      await shop.a.customers.delete(id);
      expect(await shop.a.balances(), isEmpty);
      await shop.a.syncNow();

      expect(await shop.a.balances(), {'Mutua': 5000});
      expect((await shop.a.issues()).single.reason, 'has_balance');
      expect((await shop.a.customer(id)).isDeleted, isFalse);
    });

    test('8: a credit sale made offline leaves exactly one debt, with the '
        'same id on every phone', () async {
      final shop = await _newShop();
      final otieno = await shop.a.customers.add(
        name: 'Otieno',
        phone: '0711000222',
      );
      await shop.a.syncNow();

      // Offline on A: the sale, and at once the debt it puts on Otieno.
      final sale = await shop.a.sales.record(
        productName: 'DAP 50kg',
        quantity: 2000,
        amountCents: 700000,
        method: SaleMethod.credit,
        customerId: otieno,
      );
      expect(await shop.a.balances(), {'Otieno': 700000});

      final report = await shop.a.syncNow();
      expect(report.conflicts, 0);
      await shop.b.syncNow();

      final debtId = SaleDebt.idFor(sale);
      for (final phone in [shop.a, shop.b]) {
        final debts = await (phone.db.select(
          phone.db.ledgerEntries,
        )..where((e) => e.saleId.equals(sale))).get();
        expect(debts, hasLength(1), reason: phone.label);
        expect(debts.single.id, debtId, reason: phone.label);
        expect(debts.single.description, 'Sale: DAP 50kg x 2');
        expect(debts.single.syncState, SyncState.synced, reason: phone.label);
        expect(await phone.balances(), {'Otieno': 700000});
      }
      expect(await shop.a.serverBalances(), {'Otieno': 700000});
      expect(await shop.a.pendingCount(), 0, reason: 'nothing left waiting');

      // Voided on A: off the account everywhere, once.
      await shop.a.sales.voidSale(sale);
      expect(await shop.a.balances(), {'Otieno': 0});
      await shop.a.syncNow();
      await shop.b.syncNow();
      expect(await shop.b.balances(), {'Otieno': 0});
      expect(await shop.a.serverBalances(), {'Otieno': 0});
    });

    test('9: a staff phone never receives suppliers; promoted to owner and '
        'resynced, it does', () async {
      final shop = await _newShop();
      final elgon = await shop.a.suppliers.add(name: 'Elgon Kenya');
      await shop.a.suppliers.recordBill(
        supplierId: elgon,
        amountCents: 1200000,
        description: 'Invoice 4471',
      );
      await shop.a.syncNow();

      await shop.b.syncNow();
      expect(await shop.b.db.select(shop.b.db.suppliers).get(), isEmpty);
      expect(await shop.b.db.select(shop.b.db.supplierEntries).get(), isEmpty);

      final promoted = await Process.run('scripts/live-promote.sh', [
        phone_rule.Phone.normalize(shop.staffPhone)!,
      ]);
      expect(promoted.exitCode, 0, reason: '${promoted.stderr}');
      expect('${promoted.stdout}', contains('promoted'));
      await shop.b.signInAgain(phone: shop.staffPhone, password: _password);
      expect(shop.b.account.permissions, contains(Permission.suppliersRead));

      final report = await shop.b.syncNow();
      expect(report.resynced, isTrue);
      final suppliers = await shop.b.suppliers.watchList().first;
      expect(suppliers.single.supplier.name, 'Elgon Kenya');
      expect(suppliers.single.balanceCents, 1200000);
    });

    test('B8: placing an order whose answer was lost, then again, places '
        'one order', () async {
      final shop = await _newShop();
      final note = await shop.a.stock.add(productName: 'Duodip 20ml');
      await shop.a.syncNow();

      final id = PurchaseOrderApi.newId();
      Future<PurchaseOrder> place() => shop.a.orders.place(
        id: id,
        supplierName: 'Twiga',
        lines: [
          OrderLine(
            productName: 'Duodip 20ml',
            quantity: 12000,
            stockRequestId: note,
          ),
        ],
      );
      shop.a.adapter.afterResponse = (request, _) {
        if (request.path.endsWith('/purchase-orders')) {
          throw DioException.connectionError(
            requestOptions: request,
            reason: 'answer lost',
          );
        }
      };
      await expectLater(place(), throwsA(isA<ApiException>()));
      shop.a.adapter.afterResponse = null;

      // The note is now on the order, yet the retry is answered, not refused.
      final order = await place();
      expect(order.id, id);
      final all = await shop.a.orders.list();
      expect(all, hasLength(1));
      expect(all.single.lines.single.quantity, 12000);

      // Its note left the list to order, on the next sync.
      await shop.a.syncNow();
      expect(await shop.a.stock.watchToOrder().first, isEmpty);

      // Cancelled twice, the second after a lost answer: done, not an error.
      await shop.a.orders.cancel(id);
      await shop.a.orders.cancel(id);
      expect((await shop.a.orders.get(id)).cancelled, isTrue);
      await shop.a.syncNow();
      expect(
        (await shop.a.stock.watchToOrder().first).single.id,
        note,
        reason: 'back on the list to order',
      );
    });

    test('10: a phone away past the deletion horizon resyncs, loses what '
        'was deleted, and keeps what it had not sent', () async {
      final shop = await _newShop();
      final gone = await shop.a.customers.add(name: 'Gone');
      final stays = await shop.a.customers.add(name: 'Stays');
      await shop.a.syncNow();
      await shop.b.syncNow();

      // A deletes; the deletion is collected before B hears of it.
      await shop.a.customers.delete(gone);
      await shop.a.syncNow();
      final gc = await Process.run('scripts/live-gc.sh', const []);
      expect(gc.exitCode, 0, reason: '${gc.stdout}${gc.stderr}');

      // B, meanwhile, records a debt offline.
      await shop.b.ledger.recordDebt(
        customerId: stays,
        amountCents: 7000,
        description: 'Kerosene',
      );
      final report = await shop.b.syncNow();

      expect(report.resynced, isTrue);
      expect(await shop.b.balances(), {'Stays': 7000});
      expect(await shop.b.pendingCount(), 0);
      expect(await shop.b.balances(), await shop.a.serverBalances());
    });

    test('13: three phones, 500 random operations, a flaky network: every '
        'phone ends with the server\'s balances', () async {
      final shop = await _newShop();
      final c = await Phone.signIn(
        Uri.parse(_url!),
        'C',
        phone: shop.ownerPhone,
        password: _password,
      );
      addTearDown(c.close);
      final phones = [shop.a, shop.b, c];
      final random = Random(13);
      final ids = <String>[];
      var faults = 0;

      // One in five answers is lost on the way back, and one in ten
      // requests never arrives.
      for (final p in phones) {
        p.adapter.afterResponse = (request, _) {
          if (random.nextInt(5) == 0) {
            faults++;
            throw DioException.connectionError(
              requestOptions: request,
              reason: 'lost',
            );
          }
        };
      }
      Future<void> trySync(Phone p) async {
        if (random.nextInt(10) == 0) return; // no signal this time
        try {
          await p.syncNow();
        } on ApiException {
          // The next one carries on; that is the point.
        }
      }

      for (var op = 0; op < 500; op++) {
        final p = phones[random.nextInt(phones.length)];
        final known = [
          for (final b in await p.customers.watchAll().first) b.customer.id,
        ];
        switch (random.nextInt(10)) {
          case 0 || 1 when ids.length < 60:
            ids.add(await p.customers.add(name: 'Customer ${ids.length}'));
          case 2 || 3 || 4 when known.isNotEmpty:
            await p.ledger.recordDebt(
              customerId: known[random.nextInt(known.length)],
              amountCents: 100 * (1 + random.nextInt(500)),
              description: 'Goods',
            );
          case 5 || 6 when known.isNotEmpty:
            await p.ledger.recordPayment(
              customerId: known[random.nextInt(known.length)],
              amountCents: 100 * (1 + random.nextInt(200)),
              method: PaymentMethod.cash,
              description: 'Cash',
            );
          case 7 when known.isNotEmpty:
            await p.customers.update(
              known[random.nextInt(known.length)],
              notes: 'note $op',
            );
          case 8 when known.isNotEmpty:
            // Owners' voids go through; staff's come back refused.
            final entries = await p.ledger
                .watchFor(known[random.nextInt(known.length)])
                .first;
            if (entries.isNotEmpty) {
              await p.ledger.voidEntry(
                entries[random.nextInt(entries.length)].id,
              );
            }
          default:
            await trySync(p);
        }
      }

      // The network settles; everyone syncs until nothing is waiting.
      for (final p in phones) {
        p.adapter.afterResponse = null;
      }
      for (var round = 0; round < 3; round++) {
        for (final p in phones) {
          await p.syncNow();
        }
      }

      final server = await shop.a.serverBalances();
      expect(server, isNotEmpty);
      for (final p in phones) {
        expect(await p.pendingCount(), 0, reason: p.label);
        expect(await p.balances(), server, reason: p.label);
        // Nothing refused: only notes of changes the server undid.
        expect(
          (await p.issues()).map((i) => i.reason).toSet(),
          everyElement(isIn(const {'forbidden', 'stale_write'})),
          reason: p.label,
        );
      }
      expect(faults, greaterThan(20), reason: 'the network was flaky');
    }, timeout: const Timeout(Duration(minutes: 5)));
  });
}
