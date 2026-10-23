import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/session/session_controller.dart';
import '../core/sync/sync_controller.dart';
import '../features/app_update/presentation/app_update_controller.dart';
import '../features/app_update/presentation/widgets/update_bar.dart';
import 'l10n/generated/app_localizations.dart';
import 'router/app_router.dart';
import 'theme/app_colors.dart';
import 'theme/app_theme.dart';

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
        }
        unawaited(ref.read(appUpdateProvider.notifier).onResume());
      },
    );
    // Look for a new version once the first screen is up. Works signed out
    // too: an app that cannot sign in must still be able to update.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(ref.read(appUpdateProvider.notifier).check()),
    );
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
