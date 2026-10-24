import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/breakpoints.dart';
import '../../core/session/current_user.dart';
import '../../features/sync_issues/data/providers.dart';
import '../l10n/generated/app_localizations.dart';
import '../theme/app_colors.dart';
import 'app_sections.dart';
import 'shell_back_handler.dart';

typedef _IconFor =
    Widget Function(AppSection section, IconData icon, {Color? color});

/// The frame around the main sections. It adapts to the screen width
/// (docs/10, §2.2):
/// - under 600 dp: a bottom bar with five sections;
/// - from 600 dp: a side rail with every section the user may see;
/// - from 1200 dp: the rail shows labels beside its icons.
class MainShell extends ConsumerWidget {
  final StatefulNavigationShell navigationShell;

  const MainShell({super.key, required this.navigationShell});

  void _open(AppSection section) {
    navigationShell.goBranch(
      section.branch,
      // Tapping the current section again returns to its first screen.
      initialLocation: section.branch == navigationShell.currentIndex,
    );
  }

  /// The highlighted entry: the current section, or More when the current
  /// section is only reachable from the More page.
  static int _selectedIndex(List<AppSection> items, AppSection current) {
    final i = items.indexOf(current);
    return i >= 0 ? i : items.indexOf(AppSection.more);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final nav = SectionNavigation.of(ref.watch(currentUserProvider));
    final current = AppSection.values[navigationShell.currentIndex];
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < Breakpoints.medium;
    // A dot on More while something there needs attention.
    final attention = (ref.watch(syncIssueCountProvider).value ?? 0) > 0;
    Widget icon(AppSection s, IconData data, {Color? color}) => Badge(
      isLabelVisible: attention && s == AppSection.more,
      backgroundColor: AppColors.error,
      smallSize: 8,
      child: Icon(data, color: color),
    );

    // The phone's back button on a section never closes the app by surprise.
    return ShellBackHandler(
      onHome: current == AppSection.home,
      // On a phone, sections missing from the bar are opened from More.
      openedFromMore: compact && !nav.bar.contains(current),
      goHome: () => navigationShell.goBranch(AppSection.home.branch),
      goMore: () => navigationShell.goBranch(AppSection.more.branch),
      child: compact
          ? _withBar(l10n, nav, current, icon)
          : _withRail(
              l10n,
              nav,
              current,
              icon,
              extended: width >= Breakpoints.large,
            ),
    );
  }

  Widget _withBar(
    AppLocalizations l10n,
    SectionNavigation nav,
    AppSection current,
    _IconFor icon,
  ) {
    return Scaffold(
      body: navigationShell,
      // Bar labels stay one line: they barely grow with the phone's font
      // setting (the icons carry the meaning), as Material recommends.
      bottomNavigationBar: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.1,
        child: NavigationBar(
          selectedIndex: _selectedIndex(nav.bar, current),
          onDestinationSelected: (i) => _open(nav.bar[i]),
          destinations: [
            for (final s in nav.bar)
              NavigationDestination(
                icon: icon(s, s.icon),
                selectedIcon: icon(s, s.selectedIcon, color: AppColors.primary),
                label: s.label(l10n),
              ),
          ],
        ),
      ),
    );
  }

  Widget _withRail(
    AppLocalizations l10n,
    SectionNavigation nav,
    AppSection current,
    _IconFor icon, {
    required bool extended,
  }) {
    final items = nav.rail;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Row(
          children: [
            // Scrolls when the screen is too short for every entry, e.g. a
            // phone in landscape.
            LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: IntrinsicHeight(
                    child: NavigationRail(
                      extended: extended,
                      minExtendedWidth: 200,
                      labelType: extended
                          ? NavigationRailLabelType.none
                          : NavigationRailLabelType.all,
                      selectedIndex: _selectedIndex(items, current),
                      onDestinationSelected: (i) => _open(items[i]),
                      destinations: [
                        for (final s in items)
                          NavigationRailDestination(
                            icon: icon(s, s.icon),
                            selectedIcon: icon(
                              s,
                              s.selectedIcon,
                              color: AppColors.primary,
                            ),
                            label: Text(s.label(l10n)),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const VerticalDivider(width: 1, thickness: 1),
            Expanded(child: navigationShell),
          ],
        ),
      ),
    );
  }
}
