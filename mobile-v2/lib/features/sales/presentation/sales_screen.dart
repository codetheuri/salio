import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/l10n/generated/app_localizations.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../core/database/app_database.dart';
import '../../../core/layout/breakpoints.dart';
import '../../../core/money/money.dart';
import '../../../core/quantity/quantity.dart';
import '../../../core/session/current_user.dart';
import '../../../core/session/permissions.dart';
import '../../../core/time/shop_time.dart';
import '../../../core/widgets/sync_badge.dart';
import '../../../core/widgets/sync_button.dart';
import '../data/providers.dart';
import '../data/sales_repository.dart';
import 'sale_screen.dart';

/// Sales of the last 30 days, newest first, by day, with today's takings
/// by method at the top: what the owner counts at closing. Read from this
/// phone, so it works offline.
///
/// From 840 dp the list and the chosen sale sit side by side.
class SalesScreen extends StatelessWidget {
  final String? selectedId;

  const SalesScreen({super.key, this.selectedId});

  @override
  Widget build(BuildContext context) {
    final twoPanes = MediaQuery.sizeOf(context).width >= Breakpoints.expanded;
    final selected = selectedId;
    if (!twoPanes) {
      return selected == null
          ? const _SaleList()
          : SaleScreen(saleId: selected);
    }
    return Row(
      children: [
        const SizedBox(width: Breakpoints.listPaneWidth, child: _SaleList()),
        const VerticalDivider(width: 1, thickness: 1),
        Expanded(
          child: selected == null
              ? Scaffold(body: _Empty(AppLocalizations.of(context).saleSelect))
              : SaleScreen(
                  key: ValueKey(selected),
                  saleId: selected,
                  besideList: true,
                ),
        ),
      ],
    );
  }
}

class _SaleList extends ConsumerWidget {
  const _SaleList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final sales = ref.watch(salesProvider);
    final shop = ref.watch(shopTimeProvider);
    final today = ref.watch(shopTodayProvider);
    final user = ref.watch(currentUserProvider);
    final selected = GoRouterState.of(context).pathParameters['id'];

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.sectionSales),
        actions: const [SyncButton()],
      ),
      floatingActionButton: user.can(Permission.salesCreate)
          ? FloatingActionButton.extended(
              onPressed: () => context.go('/sales/new'),
              icon: const Icon(Icons.add),
              label: Text(l10n.saleNew),
            )
          : null,
      body: ReadableWidth(
        maxWidth: Breakpoints.listWidth,
        child: switch (sales) {
          AsyncData(:final value) => _list(
            context,
            value,
            shop,
            today,
            selected,
          ),
          AsyncError() => _Empty(l10n.errorUnexpected),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ),
    );
  }

  Widget _list(
    BuildContext context,
    List<SaleWithCustomer> sales,
    ShopTime shop,
    DateTime today,
    String? selected,
  ) {
    final l10n = AppLocalizations.of(context);
    final byDay = <DateTime, List<SaleWithCustomer>>{};
    for (final s in sales) {
      (byDay[shop.day(s.sale.saleDate)] ??= []).add(s);
    }
    final todays = byDay[today] ?? const [];
    return ListView(
      // Room for the last row above the button.
      padding: const EdgeInsets.only(bottom: 88),
      children: [
        _TodayCard(todays),
        if (sales.isEmpty) _Empty(l10n.salesEmpty),
        for (final MapEntry(key: day, value: list) in byDay.entries) ...[
          _DayHeader(day: day, today: today, sales: list),
          for (final s in list) ...[
            _SaleTile(s, selected: s.sale.id == selected),
            const Divider(height: 1),
          ],
        ],
      ],
    );
  }
}

/// Live sales' total, by method.
Map<SaleMethod, int> totalsByMethod(Iterable<SaleWithCustomer> sales) {
  final totals = <SaleMethod, int>{};
  for (final s in sales) {
    if (s.sale.isDeleted) continue;
    final m = SaleMethod.of(s.sale.paymentMethod);
    totals[m] = (totals[m] ?? 0) + s.sale.amountCents;
  }
  return totals;
}

String saleMethodLabel(AppLocalizations l10n, SaleMethod m) => switch (m) {
  SaleMethod.cash => l10n.methodCash,
  SaleMethod.mpesa => l10n.methodMpesa,
  SaleMethod.bank => l10n.methodBank,
  SaleMethod.credit => l10n.methodCredit,
};

/// "DAP 50kg × 2".
String saleTitle(SaleRow s) =>
    '${s.productName} × ${Quantity.toWire(s.quantity)}';

class _TodayCard extends StatelessWidget {
  final List<SaleWithCustomer> sales;

  const _TodayCard(this.sales);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final totals = totalsByMethod(sales);
    final total = totals.values.fold(0, (a, b) => a + b);
    final count = sales.where((s) => !s.sale.isDeleted).length;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Card(
        color: AppColors.primaryDark,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.salesToday(count),
                style: theme.textTheme.titleSmall?.copyWith(
                  color: AppColors.primaryLight,
                ),
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  Money.format(total, compact: true),
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: AppColors.onPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (totals.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xs),
                Wrap(
                  spacing: AppSpacing.md,
                  runSpacing: AppSpacing.xs,
                  children: [
                    for (final m in SaleMethod.values)
                      if (totals[m] != null)
                        Text(
                          '${saleMethodLabel(l10n, m)} '
                          '${Money.format(totals[m]!, compact: true)}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: AppColors.onPrimary,
                          ),
                        ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  final DateTime day;
  final DateTime today;
  final List<SaleWithCustomer> sales;

  const _DayHeader({
    required this.day,
    required this.today,
    required this.sales,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final total = totalsByMethod(sales).values.fold(0, (a, b) => a + b);
    final label = day == today
        ? l10n.today
        : day == today.subtract(const Duration(days: 1))
        ? l10n.yesterday
        : ShopTime.date(day, locale);
    final style = theme.textTheme.titleSmall?.copyWith(
      color: AppColors.textSecondary,
    );
    return Container(
      color: theme.colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: style,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(Money.format(total, compact: true), style: style),
        ],
      ),
    );
  }
}

class _SaleTile extends ConsumerWidget {
  final SaleWithCustomer item;
  final bool selected;

  const _SaleTile(this.item, {required this.selected});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final shop = ref.watch(shopTimeProvider);
    final s = item.sale;
    final voided = s.isDeleted;
    final strike = voided
        ? const TextStyle(decoration: TextDecoration.lineThrough)
        : null;
    final method = SaleMethod.of(s.paymentMethod);
    return ListTile(
      selected: selected,
      selectedTileColor: AppColors.primaryLight.withValues(alpha: 0.35),
      title: Row(
        children: [
          Flexible(
            child: Text(
              saleTitle(s),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: strike,
            ),
          ),
          SyncBadge(s.syncState),
        ],
      ),
      subtitle: Text(
        [
          if (voided) l10n.entryVoided,
          DateFormat.Hm().format(shop.local(s.saleDate)),
          saleMethodLabel(l10n, method),
          ?item.customerName,
        ].join(' · '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 140),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            Money.format(s.amountCents, compact: true),
            style: theme.textTheme.titleMedium
                ?.copyWith(
                  color: voided
                      ? AppColors.textSecondary
                      : method == SaleMethod.credit
                      ? AppColors.debtRed
                      : AppColors.paymentGreen,
                )
                .merge(strike),
          ),
        ),
      ),
      onTap: () => context.go('/sales/${s.id}'),
    );
  }
}

class _Empty extends StatelessWidget {
  final String text;

  const _Empty(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(AppSpacing.lg),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.point_of_sale_outlined,
          size: 64,
          color: AppColors.textSecondary,
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          text,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      ],
    ),
  );
}
