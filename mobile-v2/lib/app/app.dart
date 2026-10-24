import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../core/network/api_exception.dart';
import '../core/network/api_provider.dart';
import '../core/session/session_controller.dart';
import '../core/sync/sync_controller.dart';
import '../features/app_update/presentation/app_update_controller.dart';
import '../features/app_update/presentation/widgets/update_bar.dart';
import '../features/customers/data/providers.dart';
import 'l10n/generated/app_localizations.dart';
import 'router/app_router.dart';
import 'theme/app_colors.dart';
import 'theme/app_theme.dart';

final _log = Logger('app');

/// The language chosen in the app; null follows the phone. Swahili for a
/// phone set to Swahili, English for anything else.
final appLocaleProvider = NotifierProvider<AppLocale, Locale?>(AppLocale.new);

class AppLocale extends Notifier<Locale?> {
  @override
  Locale? build() => null;

  void set(Locale? locale) => state = locale;
}

/// The largest text the layouts are tested at (docs/10, §5). The phone's
/// font-size setting is followed up to here.
const maxTextScale = 1.3;

class SalioApp extends ConsumerStatefulWidget {
  const SalioApp({super.key});

  @override
  ConsumerState<SalioApp> createState() => _SalioAppState();
}

class _SalioAppState extends ConsumerState<SalioApp> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Back in the app: sync, so the other phones' records show, and look
    // for a new version now and then.
    _lifecycle = AppLifecycleListener(
      onResume: () {
        if (ref.read(sessionProvider).value?.canSync ?? false) {
          unawaited(ref.read(syncProvider.notifier).syncNow());
          unawaited(_refresh());
        }
        unawaited(ref.read(appUpdateProvider.notifier).onResume());
      },
    );
    // Each time someone signs in, or the app opens signed in: the profile,
    // the shop and the team list, which may have changed elsewhere.
    ref.listenManual(sessionProvider, (previous, next) {
      final before = previous?.value;
      final now = next.value;
      if (now == null || !now.canSync) return;
      if (before?.account.userId == now.account.userId &&
          before?.token == now.token) {
        return;
      }
      unawaited(_refresh());
    }, fireImmediately: true);
    // Look for a new version once the first screen is up. Works signed out
    // too: an app that cannot sign in must still be able to update.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(ref.read(appUpdateProvider.notifier).check()),
    );
  }

  /// Reads what may have changed on other phones: the user's role and
  /// permissions (B5), the shop's name and time zone, and the team's names
  /// for "recorded by". All optional: offline, the cached copies are used.
  Future<void> _refresh() async {
    await ref.read(sessionProvider.notifier).refresh();
    if (!(ref.read(sessionProvider).value?.canSync ?? false)) return;
    try {
      await ref
          .read(staffRepositoryProvider)
          .refresh(ref.read(apiClientProvider));
    } on ApiException catch (e) {
      _log.info('team list not refreshed: $e');
    }
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      routerConfig: ref.watch(appRouterProvider),
      locale: ref.watch(appLocaleProvider),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // Android draws apps behind its navigation bar (the back, home and
      // recent buttons). Keeping everything above it here, once, means no
      // screen, sheet or dialog can put a button under those keys; the strip
      // behind the bar is white, like the bottom bar. From DairyGo. The
      // update bar sits under every screen, sign-in included.
      builder: (context, child) => ColoredBox(
        color: AppColors.surface,
        child: SafeArea(
          top: false,
          left: false,
          right: false,
          child: MediaQuery.withClampedTextScaling(
            maxScaleFactor: maxTextScale,
            child: UpdateBar(child: child!),
          ),
        ),
      ),
    );
  }
}
