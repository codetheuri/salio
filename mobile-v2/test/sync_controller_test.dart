// When syncs run: the waits after failures, the connection coming back, and
// the role passed to the engine (docs/10, §4.3).

import 'dart:async';

import 'package:drift/native.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salio/core/database/app_database.dart';
import 'package:salio/core/network/api_client.dart';
import 'package:salio/core/network/api_exception.dart';
import 'package:salio/core/session/permissions.dart';
import 'package:salio/core/session/session_controller.dart';
import 'package:salio/core/sync/self_check.dart';
import 'package:salio/core/sync/sync_controller.dart';
import 'package:salio/core/sync/sync_engine.dart';
import 'package:salio/core/time/server_clock.dart';

import 'support/fake_app_update.dart';
import 'support/fixtures.dart';

/// An engine that answers from a script: an exception to throw, or null
/// for a sync that worked.
class ScriptedEngine extends SyncEngine {
  final script = <ApiException?>[];
  final accesses = <String?>[];

  ScriptedEngine(AppDatabase db)
    : super(
        db,
        ApiClient(
          origin: Uri.parse('http://unused'),
          token: () => null,
          appHeader: 'test',
        ),
        ServerClock(),
      );

  int get calls => accesses.length;

  @override
  Future<SyncReport> sync({String? access}) async {
    accesses.add(access);
    final next = script.isEmpty ? null : script.removeAt(0);
    if (next != null) throw next;
    return const SyncReport();
  }
}

class NoSelfCheck extends BalanceSelfCheck {
  NoSelfCheck(AppDatabase db)
    : super(
        db,
        ApiClient(
          origin: Uri.parse('http://unused'),
          token: () => null,
          appHeader: 'test',
        ),
      );

  @override
  Future<SelfCheck?> runIfDue(DateTime now) async => null;
}

void main() {
  const offline = ApiException(ApiFailure.offline);

  void run(
    void Function(
      FakeAsync async,
      ProviderContainer container,
      ScriptedEngine engine,
      StreamController<bool> connection,
    )
    body, {
    Role role = Role.staff,
  }) {
    fakeAsync((async) {
      final db = AppDatabase(NativeDatabase.memory());
      final engine = ScriptedEngine(db);
      final connection = StreamController<bool>.broadcast();
      final container = ProviderContainer(
        overrides: [
          sessionProvider.overrideWith(() => FixedSession(sessionFor(role))),
          syncEngineProvider.overrideWithValue(engine),
          selfCheckProvider.overrideWithValue(NoSelfCheck(db)),
          connectionChangesProvider.overrideWithValue(connection.stream),
          ...fakeUpdateOverrides(),
        ],
      );
      // Keep the controller alive, as the app's screens do.
      final sub = container.listen(syncProvider, (_, _) {});
      async.flushMicrotasks();
      container.read(syncProvider);
      async.flushMicrotasks();
      body(async, container, engine, connection);
      sub.close();
      container.dispose();
      unawaited(connection.close());
      unawaited(db.close());
      async.flushMicrotasks();
    });
  }

  test('after failures it waits 5 s, 15 s, 1 minute, then 5 minutes', () {
    run((async, container, engine, _) {
      engine.script.addAll(List.filled(6, offline));
      async.elapse(Duration.zero);
      expect(engine.calls, 1);
      expect(container.read(syncProvider).failure, ApiFailure.offline);
      expect(container.read(syncProvider).retryAt, isNotNull);

      for (final (wait, calls) in [
        (const Duration(seconds: 5), 2),
        (const Duration(seconds: 15), 3),
        (const Duration(minutes: 1), 4),
        (const Duration(minutes: 5), 5),
        (const Duration(minutes: 5), 6),
      ]) {
        async.elapse(wait - const Duration(milliseconds: 1));
        expect(engine.calls, calls - 1, reason: 'not before $wait');
        async.elapse(const Duration(milliseconds: 1));
        expect(engine.calls, calls, reason: 'after $wait');
      }

      // A success ends the waits; the next failure starts at 5 s again.
      async.elapse(const Duration(minutes: 5));
      expect(container.read(syncProvider).failure, isNull);
      engine.script.add(offline);
      unawaited(container.read(syncProvider.notifier).syncNow());
      async.flushMicrotasks();
      final calls = engine.calls;
      async.elapse(const Duration(seconds: 5));
      expect(engine.calls, calls + 1);
    });
  });

  test('a connection coming back syncs at once', () {
    run((async, container, engine, connection) {
      engine.script.addAll(List.filled(4, offline));
      async.elapse(const Duration(seconds: 25)); // three failures in
      expect(engine.calls, 3);

      connection.add(false);
      async.flushMicrotasks();
      expect(engine.calls, 3, reason: 'losing it does nothing');
      connection.add(true);
      async.flushMicrotasks();
      expect(engine.calls, 4, reason: 'no need to sit out the minute');
    });
  });

  test('a signed-out answer does not retry', () {
    run((async, container, engine, _) {
      engine.script.add(const ApiException(ApiFailure.unauthorized));
      async.elapse(const Duration(minutes: 1, seconds: 59));
      expect(engine.calls, 1);
      expect(container.read(syncProvider).retryAt, isNull);
    });
  });

  test('the engine is told the role, so a change resyncs', () {
    run(role: Role.owner, (async, container, engine, _) {
      async.elapse(Duration.zero);
      expect(engine.accesses, ['owner']);
    });
  });
}
