import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';

import '../../features/auth/data/auth_api.dart';
import '../network/api_exception.dart';
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
  Future<void> signIn({required String phone, required String password}) =>
      _start(
        (api, now) =>
            api.signIn(phone: phone.trim(), password: password, now: now),
      );

  /// Registers a new shop and signs its owner in.
  Future<void> register({
    required String businessName,
    required String name,
    required String phone,
    required String password,
  }) => _start(
    (api, now) => api.register(
      businessName: businessName.trim(),
      name: name.trim(),
      phone: phone.trim(),
      password: password,
      now: now,
    ),
  );

  /// Joins a shop as staff with an invite code, and signs in.
  Future<void> join({
    required String code,
    required String name,
    required String phone,
    required String password,
  }) => _start(
    (api, now) => api.join(
      code: code.trim().toUpperCase(),
      name: name.trim(),
      phone: phone.trim(),
      password: password,
      now: now,
    ),
  );

  Future<void> _start(
    Future<({String token, Account account})> Function(
      AuthApi api,
      DateTime now,
    )
    authenticate,
  ) async {
    final store = await ref.read(accountStoreProvider.future);
    final result = await authenticate(
      AuthApi(ref.read(apiClientProvider)),
      ref.read(serverClockProvider).now(),
    );
    final known = (await store.load()).accounts
        .where((a) => a.userId == result.account.userId)
        .firstOrNull;
    final account = result.account.copyWith(
      businessName: known?.businessName,
      timeZone: known?.timeZone,
    );
    await store.saveToken(account.userId, result.token);
    await store.use(account);
    state = AsyncData(Session(account, result.token));
  }

  /// Reads the profile and the shop from the server, so a role, a
  /// permission or the shop's name changed on another phone shows here.
  /// The app runs it after sign-in, when it opens and when it comes back. Not
  /// needed to work: offline it does nothing, and the next run tries again.
  Future<void> refresh() async {
    final session = state.value;
    if (session == null || !session.canSync) return;
    final api = AuthApi(ref.read(apiClientProvider));
    try {
      final me = await api.me();
      final shop = await api.business();
      if (state.value?.account.userId != session.account.userId) return;
      final account = session.account.copyWith(
        name: me.name,
        role: me.role,
        permissions: me.permissions,
        businessName: shop.name,
        timeZone: shop.timeZone,
      );
      final store = await ref.read(accountStoreProvider.future);
      await store.use(account);
      state = AsyncData(Session(account, session.token));
    } on ApiException catch (e) {
      if (e.kind == ApiFailure.unauthorized) {
        await endedByServer(e.message);
      } else {
        _log.info('profile not refreshed: $e');
      }
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
