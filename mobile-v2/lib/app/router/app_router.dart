import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/session/current_user.dart';
import '../../core/session/permissions.dart';
import '../../core/session/session.dart';
import '../../core/session/session_controller.dart';
import '../../core/widgets/section_placeholder.dart';
import '../../features/auth/presentation/join_screen.dart';
import '../../features/auth/presentation/register_screen.dart';
import '../../features/auth/presentation/sign_in_screen.dart';
import '../../features/auth/presentation/splash_screen.dart';
import '../../features/customers/presentation/credit_limit_screen.dart';
import '../../features/customers/presentation/customer_form_screen.dart';
import '../../features/customers/presentation/customers_screen.dart';
import '../../features/ledger/presentation/entry_screen.dart';
import '../../features/ledger/presentation/record_debt_screen.dart';
import '../../features/ledger/presentation/record_payment_screen.dart';
import '../../features/more/presentation/more_screen.dart';
import '../../features/sync_issues/presentation/needs_attention_screen.dart';
import '../shell/app_sections.dart';
import '../shell/main_shell.dart';

abstract final class AppRoutes {
  static const splash = '/splash';
  static const signIn = '/sign-in';
  static const register = '/register';
  static const join = '/join';
  static const needsAttention = '/more/attention';

  /// The screens someone signed out may see.
  static const signedOut = {signIn, register, join};
}

/// The router is created once. Changes to who is signed in reach it through
/// [GoRouter.refreshListenable], which re-runs the redirect without
/// rebuilding the router, so open screens and tab history survive.
///
/// Every decision about where a user may be is in the redirect, in one
/// place (docs/10, D9). The forced password change and required updates
/// join it in M6.
final appRouterProvider = Provider<GoRouter>((ref) {
  final session = ValueNotifier<AsyncValue<Session?>>(
    ref.read(sessionProvider),
  );
  ref.listen(sessionProvider, (_, next) => session.value = next);
  ref.onDispose(session.dispose);

  return GoRouter(
    initialLocation: AppSection.home.path,
    debugLogDiagnostics: kDebugMode,
    refreshListenable: session,
    redirect: (context, state) {
      final current = session.value;
      final location = state.matchedLocation;
      // Only while the saved account is read at start; during sign-in the
      // sign-in screen stays up with its own spinner.
      if (current.isLoading && !current.hasValue) return AppRoutes.splash;

      final signedIn = current.value;
      if (signedIn == null) {
        return AppRoutes.signedOut.contains(location) ? null : AppRoutes.signIn;
      }
      // An account whose session the server ended may come back here to sign
      // in again; one that can sync has no reason to.
      if (location == AppRoutes.splash ||
          (AppRoutes.signedOut.contains(location) && signedIn.canSync)) {
        return AppSection.home.path;
      }
      if (location == AppRoutes.register || location == AppRoutes.join) {
        return AppRoutes.signIn;
      }

      // A section the user may not see, opened from a link or after a role
      // change, falls back to Home rather than showing an empty screen.
      final user = ref.read(currentUserProvider);
      final section = AppSection.of(location);
      if (section != null && !section.visibleTo(user)) {
        return AppSection.home.path;
      }
      // Owner-only screens, opened by someone else: back to the customer.
      final needs = _customerActions[location.split('/').last];
      if (needs != null &&
          location.startsWith('/customers/') &&
          !user.can(needs)) {
        return location.substring(0, location.lastIndexOf('/'));
      }
      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: AppRoutes.signIn,
        builder: (context, state) => const SignInScreen(),
      ),
      GoRoute(
        path: AppRoutes.register,
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: AppRoutes.join,
        builder: (context, state) => const JoinScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => MainShell(navigationShell: shell),
        branches: [
          for (final section in AppSection.values)
            StatefulShellBranch(routes: [_sectionRoute(section)]),
        ],
      ),
    ],
  );
});

/// Customer screens that need a permission, by their last path segment.
const _customerActions = {
  'edit': Permission.customersUpdate,
  'limit': Permission.customersCreditLimit,
  'debt': Permission.transactionsCreate,
  'payment': Permission.transactionsCreate,
  'new': Permission.customersCreate,
};

/// A section's first screen, and the screens opened from it, which keep the
/// section's place in the bar.
GoRoute _sectionRoute(AppSection section) => switch (section) {
  AppSection.customers => GoRoute(
    path: section.path,
    builder: (context, state) => const CustomersScreen(),
    routes: [
      GoRoute(
        path: 'new',
        builder: (context, state) => const CustomerFormScreen(),
      ),
      GoRoute(
        path: ':id',
        // Beside the list from 840 dp, on its own on a phone.
        builder: (context, state) =>
            CustomersScreen(selectedId: state.pathParameters['id']),
        routes: [
          GoRoute(
            path: 'edit',
            builder: (context, state) =>
                CustomerFormScreen(customerId: state.pathParameters['id']),
          ),
          GoRoute(
            path: 'limit',
            builder: (context, state) =>
                CreditLimitScreen(customerId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: 'debt',
            builder: (context, state) =>
                RecordDebtScreen(customerId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: 'payment',
            builder: (context, state) =>
                RecordPaymentScreen(customerId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: 'entries/:entryId',
            builder: (context, state) => EntryScreen(
              customerId: state.pathParameters['id']!,
              entryId: state.pathParameters['entryId']!,
            ),
          ),
        ],
      ),
    ],
  ),
  AppSection.more => GoRoute(
    path: section.path,
    builder: (context, state) => const MoreScreen(),
    routes: [
      GoRoute(
        path: 'attention',
        builder: (context, state) => const NeedsAttentionScreen(),
      ),
    ],
  ),
  _ => GoRoute(
    path: section.path,
    builder: (context, state) => SectionPlaceholder(section: section),
  ),
};
