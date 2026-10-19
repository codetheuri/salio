import 'package:flutter_riverpod/flutter_riverpod.dart';

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

  bool can(String permission) => permissions.contains(permission);
}

/// Who is signed in, as far as screens need to know. Permissions come from
/// the role table until the server sends them (docs/10, B5). Signed out,
/// nothing is allowed.
final currentUserProvider = Provider<SessionUser>((ref) {
  final account = ref.watch(sessionProvider).value?.account;
  if (account == null) {
    return const SessionUser(name: '', role: Role.staff, permissions: {});
  }
  return SessionUser.ofRole(account.name, account.role);
});
