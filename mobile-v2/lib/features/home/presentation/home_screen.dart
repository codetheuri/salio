import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/l10n/generated/app_localizations.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../core/layout/breakpoints.dart';
import '../../../core/money/money.dart';
import '../../../core/session/current_user.dart';
import '../../../core/session/permissions.dart';
import '../../../core/session/session_controller.dart';
import '../../../core/time/shop_time.dart';
import '../../../core/widgets/sync_button.dart';
import '../../customers/data/providers.dart';
import '../../ledger/domain/payment_reference.dart';
import '../../ledger/presentation/widgets/money_fields.dart';
import '../../sales/presentation/customer_picker.dart';
import '../../suppliers/data/providers.dart';
import '../data/home_repository.dart';
import '../data/providers.dart';
import 'reminder.dart';

/// Home: the day at a glance, computed on this phone so it works offline.
/// What shows depends on what the user may see (docs/10, §2.1):
/// - everyone: today's money by method, and the Today list;
/// - those who see the team (owners): today's money by who took it;
/// - everyone else: what they took themselves;
/// - with reports: the shop's figures, as the server's summary has them;
/// - with suppliers: what the shop owes them.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final user = ref.watch(currentUserProvider);
    final shop = ref.watch(
      sessionProvider.select((s) => s.value?.account.businessName),
    );
    final canRecord =
        user.can(Permission.transactionsCreate) ||
        user.can(Permission.salesCreate);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          shop ?? l10n.sectionHome,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: const [SyncButton()],
      ),
      floatingActionButton: canRecord
          ? FloatingActionButton(
              tooltip: l10n.homeRecord,
              onPressed: () => unawaited(_record(context, ref)),
              child: const Icon(Icons.add),
            )
          : null,
      body: ReadableWidth(
        maxWidth: Breakpoints.listWidth,
        child: ListView(
          // Room for the last row above the + button.
          padding: const EdgeInsets.only(bottom: 88),
          children: [
            const _TodayMoneyCard(),
            if (user.can(Permission.reportsRead)) const _Figures(),
            if (user.can(Permission.suppliersRead)) const _Payables(),
            const _TodayList(),
          ],
        ),
      ),
    );
  }

  /// The + button: a debt, a payment or a sale, in at most three taps.
  /// A debt or payment asks for the customer first.
  Future<void> _record(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final user = ref.read(currentUserProvider);
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (user.can(Permission.transactionsCreate)) ...[
              ListTile(
                leading: const Icon(Icons.add_shopping_cart),
                title: Text(l10n.recordDebt),
                onTap: () => Navigator.pop(context, 'debt'),
              ),
              ListTile(
                leading: const Icon(Icons.payments_outlined),
                title: Text(l10n.recordPayment),
                onTap: () => Navigator.pop(context, 'payment'),
              ),
            ],
            if (user.can(Permission.salesCreate))
              ListTile(
                leading: const Icon(Icons.point_of_sale_outlined),
                title: Text(l10n.saleNew),
                onTap: () => Navigator.pop(context, 'sale'),
              ),
          ],
        ),
      ),
    );
    if (choice == null || !context.mounted) return;
    if (choice == 'sale') {
      context.go('/sales/new');
      return;
    }
    final customer = await pickCustomer(context);
    if (customer != null && context.mounted) {
      context.go('/customers/$customer/$choice');
    }
  }
}

/// A heading above each part of Home.
class _Heading extends StatelessWidget {
  final String text;
  final Widget? trailing;

  const _Heading(this.text, {this.trailing});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.md,
      AppSpacing.md,
      AppSpacing.md,
      AppSpacing.xs,
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.titleMedium),
        ),
        ?trailing,
      ],
    ),
  );
}

class _TodayMoneyCard extends ConsumerWidget {
  const _TodayMoneyCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final money = ref.watch(todayMoneyProvider).value;
    final user = ref.watch(currentUserProvider);
    final me = ref.watch(
      sessionProvider.select((s) => s.value?.account.userId),
    );
    final names = ref.watch(staffNamesProvider).value ?? const {};
    // Owners see who took what; staff see what they took.
    final seesTeam = user.can(Permission.staffManage);
    final onPrimary = theme.textTheme.bodyMedium?.copyWith(
      color: AppColors.onPrimary,
    );

    String methodLabel(String wire) => switch (wire) {
      '' => l10n.methodUnrecorded,
      _ =>
        PaymentMethod.values
                .where((m) => m.wire == wire)
                .map((m) => paymentMethodLabel(l10n, m))
                .firstOrNull ??
            wire,
    };

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
                l10n.homeMoneyToday,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: AppColors.primaryLight,
                ),
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  Money.format(money?.totalCents ?? 0, compact: true),
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: AppColors.onPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                l10n.homeMoneySplit(
                  Money.format(money?.paymentsCents ?? 0, compact: true),
                  Money.format(money?.salesCents ?? 0, compact: true),
                ),
                style: onPrimary,
              ),
              if (money != null && money.byMethod.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xs),
                Wrap(
                  spacing: AppSpacing.md,
                  runSpacing: AppSpacing.xs,
                  children: [
                    for (final MapEntry(:key, :value) in money.byMethod.entries)
                      Text(
                        '${methodLabel(key)} ${Money.format(value, compact: true)}',
                        style: onPrimary,
                      ),
                  ],
                ),
              ],
              if (money != null && seesTeam && money.byUser.isNotEmpty) ...[
                const Divider(color: AppColors.primaryLight),
                for (final MapEntry(:key, :value) in money.byUser.entries)
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          key == me
                              ? user.name
                              : names[key] ?? l10n.someoneElse,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: onPrimary,
                        ),
                      ),
                      Text(
                        Money.format(value, compact: true),
                        style: onPrimary,
                      ),
                    ],
                  ),
              ],
              if (money != null && !seesTeam && me != null)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Text(
                    l10n.homeYouTook(Money.format(money.of(me), compact: true)),
                    style: onPrimary,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The shop's figures, as the server's summary computes them.
class _Figures extends ConsumerWidget {
  const _Figures();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final f = ref.watch(shopFiguresProvider).value;
    if (f == null) return const SizedBox.shrink();
    final tiles = [
      (
        l10n.homeOwed,
        Money.format(f.owedCents, compact: true),
        AppColors.debtRed,
      ),
      (
        l10n.homeAdvances,
        Money.format(f.advancesCents, compact: true),
        AppColors.paymentGreen,
      ),
      (
        l10n.homeCollected30,
        Money.format(f.collected30Cents, compact: true),
        AppColors.paymentGreen,
      ),
      (l10n.homeQuiet, '${f.quietCount}', AppColors.textPrimary),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Heading(
          l10n.homeFigures,
          trailing: Text(l10n.homeCustomers(f.totalCustomers)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Two to a row on a phone, four on a wide screen.
              final across = constraints.maxWidth >= 640 ? 4 : 2;
              final width =
                  (constraints.maxWidth - AppSpacing.sm * (across - 1)) /
                  across;
              return Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final (label, value, color) in tiles)
                    SizedBox(
                      width: width,
                      child: _FigureTile(
                        label: label,
                        value: value,
                        color: color,
                      ),
                    ),
                ],
              );
            },
          ),
        ),
        if (f.quietDebtors.isNotEmpty) ...[
          _Heading(l10n.homeQuietTitle),
          for (final d in f.quietDebtors.take(5))
            ListTile(
              title: Text(d.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                l10n.homeQuietSince(
                  ShopTime.date(
                    ref.watch(shopTimeProvider).day(d.lastActivity),
                    Localizations.localeOf(context).toLanguageTag(),
                  ),
                ),
              ),
              trailing: Text(
                Money.format(d.balanceCents, compact: true),
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(color: AppColors.debtRed),
              ),
              onTap: () => context.go('/customers/${d.customerId}'),
            ),
        ],
      ],
    );
  }
}

class _FigureTile extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _FigureTile({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm + AppSpacing.xs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                value,
                maxLines: 1,
                style: theme.textTheme.titleLarge?.copyWith(color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// What the shop owes its suppliers, from this phone's records.
class _Payables extends ConsumerWidget {
  const _Payables();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final suppliers = ref.watch(suppliersProvider).value;
    if (suppliers == null) return const SizedBox.shrink();
    final owed = suppliers
        .where((s) => s.balanceCents > 0)
        .fold(0, (a, s) => a + s.balanceCents);
    if (owed == 0) return const SizedBox.shrink();
    return ListTile(
      leading: const Icon(Icons.local_shipping_outlined),
      title: Text(l10n.homeOwedToSuppliers),
      // Shrinks to fit rather than squeezing the label onto three lines.
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 160),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            Money.format(owed, compact: true),
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(color: AppColors.debtRed),
          ),
        ),
      ),
      onTap: () => context.go('/suppliers'),
    );
  }
}

/// The day's plan: who owes money past its day, or due today, largest
/// first, with Call and Remind.
class _TodayList extends ConsumerWidget {
  const _TodayList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final items = ref.watch(todayListProvider).value;
    if (items == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Heading(
          l10n.homeTodayList,
          trailing: items.isEmpty ? null : Text('${items.length}'),
        ),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            child: Text(
              l10n.homeTodayEmpty,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
        for (final item in items) ...[
          _TodayTile(item),
          const Divider(height: 1),
        ],
      ],
    );
  }
}

class _TodayTile extends ConsumerWidget {
  final TodayItem item;

  const _TodayTile(this.item);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final c = item.customer.customer;
    final phone = c.phone;
    final since = item.customer.dues.earliestDue;
    final lines = [
      if (item.overdueCents > 0)
        since == null
            ? l10n.homeOverdue(Money.format(item.overdueCents, compact: true))
            : l10n.duesOverdue(
                Money.format(item.overdueCents, compact: true),
                ShopTime.date(since, locale),
              ),
      if (item.dueTodayCents > 0)
        l10n.homeDueToday(Money.format(item.dueTodayCents, compact: true)),
    ];
    return ListTile(
      title: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        lines.join('\n'),
        style: theme.textTheme.bodyMedium?.copyWith(
          color: item.overdueCents > 0 ? AppColors.debtRed : null,
        ),
      ),
      onTap: () => context.go('/customers/${c.id}'),
      trailing: phone == null
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: l10n.homeCall(c.name),
                  icon: const Icon(Icons.call_outlined),
                  onPressed: () => unawaited(
                    ref.read(launchExternalProvider)(callLink(phone)),
                  ),
                ),
                IconButton(
                  tooltip: l10n.homeRemind(c.name),
                  icon: const Icon(Icons.notifications_active_outlined),
                  onPressed: () => unawaited(
                    sendReminder(
                      context,
                      ref,
                      phone: phone,
                      text: reminderText(
                        l10n,
                        customer: c.name,
                        shop:
                            ref
                                .read(sessionProvider)
                                .value
                                ?.account
                                .businessName ??
                            '',
                        owedCents: item.customer.balanceCents,
                        overdueSince: item.overdueCents > 0 ? since : null,
                        locale: locale,
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
