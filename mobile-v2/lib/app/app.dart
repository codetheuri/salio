import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

class SalioApp extends ConsumerWidget {
  const SalioApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
      // behind the bar is white, like the bottom bar. From DairyGo.
      builder: (context, child) => ColoredBox(
        color: AppColors.surface,
        child: SafeArea(
          top: false,
          left: false,
          right: false,
          child: MediaQuery.withClampedTextScaling(
            maxScaleFactor: maxTextScale,
            child: child!,
          ),
        ),
      ),
    );
  }
}
