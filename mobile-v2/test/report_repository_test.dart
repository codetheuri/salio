// ReportRepository against a scripted network: what is kept, when the kept
// copy is shown, and when it is not.

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salio/core/database/app_database.dart';
import 'package:salio/core/network/api_client.dart';
import 'package:salio/core/network/api_exception.dart';
import 'package:salio/core/time/server_clock.dart';
import 'package:salio/features/reports/data/report_repository.dart';

/// Answers each request with the next of [answers]: a status and a body,
/// or null for no connection. Records what was asked.
class _Script implements HttpClientAdapter {
  final List<(int, Object)?> answers;
  final asked = <Uri>[];

  _Script(this.answers);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    asked.add(options.uri);
    final next = answers.removeAt(0);
    if (next == null) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'offline',
      );
    }
    final (status, body) = next;
    return ResponseBody.fromString(
      body is String ? body : jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late AppDatabase db;
  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase(NativeDatabase.memory());
  });
  tearDown(() => db.close());

  ReportRepository repo(_Script script) => ReportRepository(
    ApiClient(
      origin: Uri.parse('http://test.invalid'),
      token: () => 't',
      appHeader: 'test',
      adapter: script,
    ),
    db,
    ServerClock(),
  );

  final sales = ReportRequest(
    ReportKind.sales,
    from: DateTime.utc(2026, 10, 1),
    to: DateTime.utc(2026, 10, 24),
  );
  const ok = (
    200,
    {
      'success': true,
      'data': {'total': '1500.00'},
    },
  );

  test(
    'a fresh report is kept, then shown offline with when it was read',
    () async {
      final script = _Script([ok, null]);
      final r = repo(script);
      final fresh = await r.load(sales);
      expect(fresh.isCached, isFalse);
      expect(fresh.data['total'], '1500.00');
      expect(script.asked.single.queryParameters, {
        'from': '2026-10-01',
        'to': '2026-10-24',
      });

      final kept = await r.load(sales);
      expect(kept.isCached, isTrue);
      expect(kept.offline!.kind, ApiFailure.offline);
      expect(kept.data['total'], '1500.00');
      expect(kept.asOf, fresh.asOf, reason: 'the time it was read, not now');
    },
  );

  test(
    'another period is another copy: none kept, the failure shows',
    () async {
      final r = repo(_Script([ok, null]));
      await r.load(sales);
      await expectLater(
        r.load(ReportRequest(ReportKind.sales, from: DateTime.utc(2026, 9, 1))),
        throwsA(isA<ApiException>()),
      );
    },
  );

  test('a refusal is never hidden behind an old copy', () async {
    final r = repo(
      _Script([
        ok,
        (403, {'success': false, 'message': 'Not allowed'}),
      ]),
    );
    await r.load(sales);
    await expectLater(
      r.load(sales),
      throwsA(
        isA<ApiException>().having((e) => e.kind, 'kind', ApiFailure.forbidden),
      ),
    );
  });

  test('the PDF is asked for the same period and customer', () async {
    final script = _Script([(200, '%PDF-1.4')]);
    await repo(script).pdf(
      ReportRequest(
        ReportKind.statement,
        customerId: 'c1',
        from: DateTime.utc(2026, 7, 1),
        to: DateTime.utc(2026, 10, 24),
      ),
    );
    final asked = script.asked.single;
    expect(asked.path, '/api/v1/reports/customers/c1/statement/pdf');
    expect(asked.queryParameters, {'from': '2026-07-01', 'to': '2026-10-24'});
  });

  test('payables asks for its 7-day window', () {
    expect(const ReportRequest(ReportKind.payables).query, {'within_days': 7});
  });
}
