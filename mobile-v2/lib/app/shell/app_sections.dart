import 'package:flutter/material.dart';

import '../../core/session/current_user.dart';
import '../../core/session/permissions.dart';
import '../l10n/generated/app_localizations.dart';

/// The top-level sections. Each is one branch of the shell route, so it keeps
/// its own navigation stack and scroll position; the order here is the
/// branch order in app_router.dart.
enum AppSection {
  home('/home', Icons.home_outlined, Icons.home),
  customers('/customers', Icons.people_outline, Icons.people),
  sales('/sales', Icons.point_of_sale_outlined, Icons.point_of_sale),
  stock('/stock', Icons.inventory_2_outlined, Icons.inventory_2),
  suppliers(
    '/suppliers',
    Icons.local_shipping_outlined,
    Icons.local_shipping,
    needs: Permission.suppliersRead,
  ),
  reports(
    '/reports',
    Icons.bar_chart_outlined,
    Icons.bar_chart,
    needs: Permission.reportsRead,
  ),
  more('/more', Icons.menu, Icons.menu_open);

  final String path;
  final IconData icon;
  final IconData selectedIcon;

  /// The permission needed to see the section at all; null for everyone.
  final String? needs;

  const AppSection(this.path, this.icon, this.selectedIcon, {this.needs});

  int get branch => index;

  bool visibleTo(SessionUser user) => needs == null || user.can(needs!);

  String label(AppLocalizations l10n) => switch (this) {
    home => l10n.sectionHome,
    customers => l10n.sectionCustomers,
    sales => l10n.sectionSales,
    stock => l10n.sectionStock,
    suppliers => l10n.sectionSuppliers,
    reports => l10n.sectionReports,
    more => l10n.sectionMore,
  };

  /// The section a location belongs to, if any.
  static AppSection? of(String location) {
    for (final s in values) {
      if (location == s.path || location.startsWith('${s.path}/')) return s;
    }
    return null;
  }
}

/// Which sections a user sees: the phone's bottom bar (always the same five,
/// so a shop's staff and owner find things in the same place), and the rest,
/// listed on the More page. The side rail on wider screens shows them all.
class SectionNavigation {
  final List<AppSection> bar;
  final List<AppSection> overflow;

  const SectionNavigation._(this.bar, this.overflow);

  static const _bar = [
    AppSection.home,
    AppSection.customers,
    AppSection.sales,
    AppSection.stock,
    AppSection.more,
  ];

  factory SectionNavigation.of(SessionUser user) => SectionNavigation._(_bar, [
    for (final s in AppSection.values)
      if (!_bar.contains(s) && s.visibleTo(user)) s,
  ]);

  /// Every section for the side rail, with More last.
  List<AppSection> get rail => [
    ...bar.where((s) => s != AppSection.more),
    ...overflow,
    AppSection.more,
  ];
}
