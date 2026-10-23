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
Future<({Phone a, Phone b})> _newShop({int pageSizeB = 200}) async {
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
  return (a: a, b: b);
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
  });
}
