import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'permissions.dart';

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

/// Who is signed in. Until sign-in exists (M1) the app shows every screen
/// as an owner would see it; the layout tests replace this for each role.
final currentUserProvider = Provider<SessionUser>(
  (ref) => SessionUser.ofRole('Preview', Role.owner),
);
