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
import 'package:salio/features/app_update/data/app_update_service.dart';

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
Future<({Phone a, Phone b, String ownerPhone})> _newShop({
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
  return (a: a, b: b, ownerPhone: ownerPhone);
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
        expect(c.phone, '0722000111', reason: phone.label);
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
          method: 'mpesa',
          reference: 'sjk4x7y2pq',
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
              method: 'cash',
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
