import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'account_store.dart';
import 'permissions.dart';
import 'session_controller.dart';

/// The person using the app, as far as screens need to know.
class SessionUser {
  final String name;
  final Role role;
  final Set<String> permissions;

  const SessionUser({
    required this.name,
    required this.role,
    required this.permissions,
  });

  SessionUser.ofRole(this.name, this.role) : permissions = role.permissions;

  /// The user [account] is: the server's permissions (B5), or for an
  /// account saved before the server sent them, the role's table.
  factory SessionUser.of(Account account) {
    final granted = account.permissions;
    return granted == null
        ? SessionUser.ofRole(account.name, account.role)
        : SessionUser(
            name: account.name,
            role: account.role,
            permissions: granted.toSet(),
          );
  }

  bool can(String permission) => permissions.contains(permission);
}

/// Who is signed in, as far as screens need to know. Permissions are the
/// server's (B5), refreshed when the app opens; an account saved before the
/// server sent them uses the role's table. Signed out, nothing is allowed.
final currentUserProvider = Provider<SessionUser>((ref) {
  final account = ref.watch(sessionProvider).value?.account;
  if (account == null) {
    return const SessionUser(name: '', role: Role.staff, permissions: {});
  }
  return SessionUser.of(account);
});
