import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';

import '../../features/auth/data/auth_api.dart';
import '../network/api_provider.dart';
import '../time/clock_provider.dart';
import 'account_store.dart';
import 'session.dart';

final _log = Logger('session');

/// The phone's accounts. A provider so tests can use a temporary folder.
final accountStoreProvider = FutureProvider<AccountStore>((ref) async {
  return AccountStore(
    await getApplicationSupportDirectory(),
    DeviceSecretStore(),
  );
});

/// Who is signed in, or null for the sign-in screen.
final sessionProvider = AsyncNotifierProvider<SessionController, Session?>(
  SessionController.new,
);

class SessionController extends AsyncNotifier<Session?> {
  @override
  Future<Session?> build() async {
    final store = await ref.watch(accountStoreProvider.future);
    final state = await store.load();
    if (state.current == null) return null;
    final account = state.accounts
        .where((a) => a.userId == state.current)
        .firstOrNull;
    if (account == null) return null;
    // Opens offline: nothing here needs the network (docs/10, §4.5).
    return Session(account, await store.token(account.userId));
  }

  /// Signs in. Throws ApiException when the server says no or cannot be
  /// reached; the screen shows why.
  Future<void> signIn({required String phone, required String password}) async {
    final store = await ref.read(accountStoreProvider.future);
    final api = AuthApi(ref.read(apiClientProvider));
    final result = await api.signIn(
      phone: phone.trim(),
      password: password,
      now: ref.read(serverClockProvider).now(),
    );
    final known = (await store.load()).accounts
        .where((a) => a.userId == result.account.userId)
        .firstOrNull;
    var account = result.account.copyWith(businessName: known?.businessName);
    await store.saveToken(account.userId, result.token);
    await store.use(account);
    state = AsyncData(Session(account, result.token));

    // The shop's name, for the screens. Not needed to work, so a failure is
    // only logged and the next sign-in tries again.
    try {
      account = account.copyWith(businessName: await api.businessName());
      await store.use(account);
      state = AsyncData(Session(account, result.token));
    } on Exception catch (e) {
      _log.info('business name not read: $e');
    }
  }

  /// The server ended the session (401): deactivated, or the password was
  /// changed on another phone. The shop's records stay usable here; syncing
  /// waits for a new sign-in to the same account.
  Future<void> endedByServer(String reason) async {
    final session = state.value;
    if (session == null || !session.canSync) return;
    final store = await ref.read(accountStoreProvider.future);
    await store.deleteToken(session.account.userId);
    state = AsyncData(Session(session.account, null, endedReason: reason));
  }

  /// Signs out. The account's file and its unsent records stay on the
  /// phone, and go up the next time this account signs in here.
  Future<void> signOut() async {
    final session = state.value;
    if (session == null) return;
    final store = await ref.read(accountStoreProvider.future);
    await store.deleteToken(session.account.userId);
    await store.leave();
    state = const AsyncData(null);
  }
}
