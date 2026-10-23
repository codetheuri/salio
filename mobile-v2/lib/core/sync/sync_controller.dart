import 'dart:async';

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
import 'sync_engine.dart';

final _log = Logger('sync');

final syncEngineProvider = Provider<SyncEngine>(
  (ref) => SyncEngine(
    ref.watch(databaseProvider),
    ref.watch(apiClientProvider),
    ref.watch(serverClockProvider),
  ),
);

/// How syncing is going, for the screens.
class SyncStatus {
  final bool running;

  /// Why the last sync stopped, or null when it finished.
  final ApiFailure? failure;

  /// This app version may no longer sync: it must update first. Records
  /// made meanwhile wait on the phone (docs/10, D12).
  final bool blockedByUpdate;

  const SyncStatus({
    this.running = false,
    this.failure,
    this.blockedByUpdate = false,
  });
}

/// Runs syncs: when the app starts, a few seconds after each change, every
/// two minutes while the app is open, and when asked (docs/10, §4.3). M2
/// adds backoff after failures and a run when the connection returns.
final syncProvider = NotifierProvider<SyncController, SyncStatus>(
  SyncController.new,
);

class SyncController extends Notifier<SyncStatus> {
  static const afterChange = Duration(seconds: 3);
  static const whileOpen = Duration(minutes: 2);

  Timer? _soon;
  Timer? _periodic;

  @override
  SyncStatus build() {
    ref.onDispose(() {
      _soon?.cancel();
      _periodic?.cancel();
    });
    // Restarted for each account: watching the session rebuilds this.
    final canSync = ref.watch(
      sessionProvider.select((s) => s.value?.canSync ?? false),
    );
    if (canSync) {
      _periodic = Timer.periodic(whileOpen, (_) => unawaited(syncNow()));
      _soon = Timer(Duration.zero, () => unawaited(syncNow()));
    }
    return const SyncStatus();
  }

  /// Syncs a few seconds from now; more changes in the meantime wait for
  /// the same sync.
  void requestSoon() {
    _soon?.cancel();
    _soon = Timer(afterChange, () => unawaited(syncNow()));
  }

  Future<void> syncNow() async {
    final session = ref.read(sessionProvider).value;
    if (session == null || !session.canSync || state.running) return;
    // A version the server no longer accepts does not try: what it would
    // send may be in a shape the server now reads differently. The ledger
    // keeps working; records wait until the update.
    if (ref.read(appUpdateProvider).required) {
      state = const SyncStatus(blockedByUpdate: true);
      return;
    }
    state = const SyncStatus(running: true);
    try {
      await ref.read(syncEngineProvider).sync();
      if (ref.mounted) state = const SyncStatus();
    } on ApiException catch (e) {
      if (!ref.mounted) return;
      state = SyncStatus(failure: e.kind);
      if (e.kind == ApiFailure.unauthorized) {
        await ref.read(sessionProvider.notifier).endedByServer(e.message);
      } else if (!e.isTransient) {
        _log.severe('sync stopped', e);
      }
    }
  }
}

/// Records on this phone the server has not accepted yet.
final unsentCountProvider = StreamProvider<int>((ref) {
  final db = ref.watch(databaseProvider);
  final pending = Variable.withInt(SyncState.pending.index);
  return db
      .customSelect(
        'SELECT (SELECT COUNT(*) FROM customers WHERE sync_state = ?1) + '
        '(SELECT COUNT(*) FROM ledger_entries WHERE sync_state = ?1) AS n',
        variables: [pending],
        readsFrom: {db.customers, db.ledgerEntries},
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
