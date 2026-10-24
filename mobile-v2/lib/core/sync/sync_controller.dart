import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../features/app_update/presentation/app_update_controller.dart';
import '../database/app_database.dart';
import '../database/database_provider.dart';
import '../network/api_exception.dart';
import '../network/api_provider.dart';
import '../session/session_controller.dart';
import '../time/clock_provider.dart';
import 'self_check.dart';
import 'sync_engine.dart';

final _log = Logger('sync');

final syncEngineProvider = Provider<SyncEngine>(
  (ref) => SyncEngine(
    ref.watch(databaseProvider),
    ref.watch(apiClientProvider),
    ref.watch(serverClockProvider),
  ),
);

final selfCheckProvider = Provider<BalanceSelfCheck>(
  (ref) => BalanceSelfCheck(
    ref.watch(databaseProvider),
    ref.watch(apiClientProvider),
  ),
);

/// True each time the phone gains a connection, false when it loses the
/// last one. Replaced in tests, which have no connectivity plugin.
final connectionChangesProvider = Provider<Stream<bool>>(
  (ref) => Connectivity().onConnectivityChanged.map(
    (links) => links.any((l) => l != ConnectivityResult.none),
  ),
);

/// How syncing is going, for the screens.
class SyncStatus {
  final bool running;

  /// Why the last sync stopped, or null when it finished.
  final ApiFailure? failure;

  /// When the next attempt after a failure is due, or null.
  final DateTime? retryAt;

  /// This app version may no longer sync: it must update first. Records
  /// made meanwhile wait on the phone (docs/10, D12).
  final bool blockedByUpdate;

  const SyncStatus({
    this.running = false,
    this.failure,
    this.retryAt,
    this.blockedByUpdate = false,
  });
}

/// Runs syncs (docs/10, §4.3):
///
/// - when the app starts, and on return to it;
/// - a few seconds after each change;
/// - every two minutes while the app is open;
/// - when the connection comes back;
/// - when the user taps Sync.
///
/// One at a time. After a failure it tries again after 5 s, 15 s, 1 minute,
/// then every 5 minutes, so a shop with no signal does not drain its
/// battery, and one whose signal comes back is not kept waiting long.
final syncProvider = NotifierProvider<SyncController, SyncStatus>(
  SyncController.new,
);

class SyncController extends Notifier<SyncStatus> {
  static const afterChange = Duration(seconds: 3);
  static const whileOpen = Duration(minutes: 2);
  static const backoff = [
    Duration(seconds: 5),
    Duration(seconds: 15),
    Duration(minutes: 1),
    Duration(minutes: 5),
  ];

  Timer? _soon;
  Timer? _periodic;
  Timer? _retry;
  StreamSubscription<bool>? _connection;
  var _failures = 0;

  @override
  SyncStatus build() {
    ref.onDispose(() {
      _soon?.cancel();
      _periodic?.cancel();
      _retry?.cancel();
      unawaited(_connection?.cancel());
    });
    // Restarted for each account: watching the session rebuilds this.
    final canSync = ref.watch(
      sessionProvider.select((s) => s.value?.canSync ?? false),
    );
    if (canSync) {
      _periodic = Timer.periodic(whileOpen, (_) {
        // Not while waiting after a failure: the wait is what spares the
        // battery of a phone with no signal.
        if (_retry?.isActive ?? false) return;
        unawaited(syncNow());
      });
      _soon = Timer(Duration.zero, () => unawaited(syncNow()));
      var online = true;
      _connection = ref.read(connectionChangesProvider).listen((now) {
        // Back from no connection at all: no need to sit out a wait.
        if (now && !online) unawaited(syncNow(reset: true));
        online = now;
      }, onError: (Object e) => _log.info('connectivity unavailable: $e'));
    }
    return const SyncStatus();
  }

  /// Syncs a few seconds from now; more changes in the meantime wait for
  /// the same sync.
  void requestSoon() {
    _soon?.cancel();
    _soon = Timer(afterChange, () => unawaited(syncNow()));
  }

  /// Syncs now. [reset] drops any wait left from earlier failures, for a
  /// sync the user asked for or a connection that came back.
  Future<void> syncNow({bool reset = false}) async {
    final session = ref.read(sessionProvider).value;
    if (session == null || !session.canSync || state.running) return;
    if (reset) _failures = 0;
    _retry?.cancel();
    // A version the server no longer accepts does not try: what it would
    // send may be in a shape the server now reads differently. The ledger
    // keeps working; records wait until the update.
    if (ref.read(appUpdateProvider).required) {
      state = const SyncStatus(blockedByUpdate: true);
      return;
    }
    state = const SyncStatus(running: true);
    try {
      await ref
          .read(syncEngineProvider)
          .sync(access: session.account.role.name);
      _failures = 0;
      if (ref.mounted) state = const SyncStatus();
    } on ApiException catch (e) {
      if (!ref.mounted) return;
      if (e.kind == ApiFailure.unauthorized) {
        state = SyncStatus(failure: e.kind);
        await ref.read(sessionProvider.notifier).endedByServer(e.message);
        return;
      }
      if (!e.isTransient) _log.severe('sync stopped', e);
      final wait = backoff[_failures.clamp(0, backoff.length - 1)];
      _failures++;
      _retry = Timer(wait, () => unawaited(syncNow()));
      state = SyncStatus(
        failure: e.kind,
        retryAt: ref.read(serverClockProvider).deviceNow().add(wait),
      );
      return;
    }
    await _selfCheck();
  }

  Future<void> _selfCheck() async {
    try {
      await ref
          .read(selfCheckProvider)
          .runIfDue(ref.read(serverClockProvider).now());
    } on ApiException catch (e) {
      // Only an alarm; the next sync tries again.
      _log.info('self-check not run: $e');
    }
  }
}

/// Records on this phone the server has not accepted yet, of every kind.
final unsentCountProvider = StreamProvider<int>((ref) {
  final db = ref.watch(databaseProvider);
  final pending = Variable.withInt(SyncState.pending.index);
  final tables = <TableInfo<Table, DataClass>>[
    db.customers,
    db.ledgerEntries,
    db.sales,
    db.stockRequests,
    db.suppliers,
    db.supplierEntries,
  ];
  return db
      .customSelect(
        'SELECT ${[for (final t in tables) '(SELECT COUNT(*) FROM ${t.actualTableName} WHERE sync_state = ?1)'].join(' + ')} AS n',
        variables: [pending],
        readsFrom: tables.toSet(),
      )
      .watchSingle()
      .map((row) => row.read<int>('n'));
});

/// When this phone last finished a sync, or null if never.
final lastSyncProvider = StreamProvider<DateTime?>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.syncMeta)
        ..where((m) => m.key.equals(SyncEngine.lastSyncKey)))
      .watchSingleOrNull()
      .map((row) => row == null ? null : DateTime.parse(row.value));
});
