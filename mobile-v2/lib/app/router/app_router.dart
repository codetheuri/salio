import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/session/current_user.dart';
import '../../core/widgets/section_placeholder.dart';
import '../../features/more/presentation/more_screen.dart';
import '../shell/app_sections.dart';
import '../shell/main_shell.dart';

/// The router is created once. Changes to who is signed in reach it through
/// [GoRouter.refreshListenable], which re-runs the redirect without
/// rebuilding the router, so open screens and tab history survive.
///
/// Every decision about where a user may be is in [redirect], in one place
/// (docs/10, D9). Sign-in, the forced password change and required updates
/// join it in M1 and M6.
final appRouterProvider = Provider<GoRouter>((ref) {
  final user = ValueNotifier(ref.read(currentUserProvider));
  ref.listen(currentUserProvider, (_, next) => user.value = next);
  ref.onDispose(user.dispose);

  return GoRouter(
    initialLocation: AppSection.home.path,
    debugLogDiagnostics: kDebugMode,
    refreshListenable: user,
    redirect: (context, state) {
      // A section the user may not see, opened from a link or after a role
      // change, falls back to Home rather than showing an empty screen.
      final section = AppSection.of(state.matchedLocation);
      if (section != null && !section.visibleTo(user.value)) {
        return AppSection.home.path;
      }
      return null;
    },
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => MainShell(navigationShell: shell),
        branches: [
          for (final section in AppSection.values)
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: section.path,
                  builder: (context, state) => section == AppSection.more
                      ? const MoreScreen()
                      : SectionPlaceholder(section: section),
                ),
              ],
            ),
        ],
      ),
    ],
  );
});
