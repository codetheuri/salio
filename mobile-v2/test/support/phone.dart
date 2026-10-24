// A simulated phone: the app's own database, sync engine, repositories and
// network code, with an in-memory database. Used by the live tests against a
// real server-v2, and by the sync tests against a fake one.

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:salio/core/database/app_database.dart';
import 'package:salio/core/money/money.dart';
import 'package:salio/core/network/api_client.dart';
import 'package:salio/core/session/account_store.dart';
import 'package:salio/core/sync/sync_engine.dart';
import 'package:salio/core/time/server_clock.dart';
import 'package:salio/features/auth/data/auth_api.dart';
import 'package:salio/features/customers/data/customer_repository.dart';
import 'package:salio/features/ledger/data/ledger_repository.dart';
import 'package:salio/features/sync_issues/data/sync_issue_repository.dart';

/// Wraps an adapter so a test can act around each request: run something
/// while the server is answering, or lose the answer on its way back.
class HookAdapter implements HttpClientAdapter {
  final HttpClientAdapter inner;

  /// Called after the server answered and before the phone sees the answer.
  /// Throwing here plays an answer lost on the way back.
  FutureOr<void> Function(RequestOptions request, ResponseBody response)?
  afterResponse;

  HookAdapter([HttpClientAdapter? inner])
    : inner = inner ?? IOHttpClientAdapter();

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final response = await inner.fetch(options, requestStream, cancelFuture);
    final hook = afterResponse;
    if (hook != null) await hook(options, response);
    return response;
  }

  @override
  void close({bool force = false}) => inner.close(force: force);
}

/// Each simulated phone has its own database, which is exactly what drift's
/// "created the database class multiple times" warning is about.
AppDatabase _openDatabase() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  return AppDatabase(NativeDatabase.memory());
}

class Phone {
  final String label;
  final AppDatabase db;
  final ServerClock clock;
  final HookAdapter adapter;
  late final ApiClient api;
  late final SyncEngine sync;
  String? token;
  late Account account;

  Phone._(
    this.label,
    Uri server, {
    int pageSize = 200,
    HttpClientAdapter? adapter,
  }) : db = _openDatabase(),
       clock = ServerClock(),
       adapter = HookAdapter(adapter) {
    api = ApiClient(
      origin: server,
      token: () => token,
      appHeader: 'test; live; $label',
      adapter: this.adapter,
    );
    sync = SyncEngine(db, api, clock, pageSize: pageSize);
  }

  /// A phone signed in with [phone] and [password].
  static Future<Phone> signIn(
    Uri server,
    String label, {
    required String phone,
    required String password,
    int pageSize = 200,
    HttpClientAdapter? adapter,
  }) async {
    final p = Phone._(label, server, pageSize: pageSize, adapter: adapter);
    final result = await AuthApi(
      p.api,
    ).signIn(phone: phone, password: password, now: p.clock.now());
    p
      ..token = result.token
      ..account = result.account;
    return p;
  }

  CustomerRepository get customers =>
      CustomerRepository(db, clock, account.userId);

  LedgerRepository get ledger => LedgerRepository(db, clock, account.userId);

  /// Every live customer's balance, by name.
  Future<Map<String, int>> balances() async => {
    for (final c in await customers.watchAll().first)
      c.customer.name: c.balanceCents,
  };

  /// Balances as the server computes them, by name.
  Future<Map<String, int>> serverBalances() async {
    final list = await api.get('/customers', query: {'per_page': 100}) as List;
    return {
      for (final c in list.cast<Map<String, dynamic>>())
        c['name'] as String: Money.parse(c['balance'] as String),
    };
  }

  Future<List<SyncIssueRow>> issues() => db.select(db.syncIssues).get();

  SyncIssueRepository get attention => SyncIssueRepository(db);

  Future<CustomerRow> customer(String id) =>
      (db.select(db.customers)..where((c) => c.id.equals(id))).getSingle();

  /// Syncs as the signed-in role, as the app does.
  Future<SyncReport> syncNow() => sync.sync(access: account.role.name);

  Future<int> pendingCount() async {
    final c = await (db.select(
      db.customers,
    )..where((r) => r.syncState.equalsValue(SyncState.pending))).get();
    final e = await (db.select(
      db.ledgerEntries,
    )..where((r) => r.syncState.equalsValue(SyncState.pending))).get();
    return c.length + e.length;
  }

  Future<void> close() => db.close();
}
