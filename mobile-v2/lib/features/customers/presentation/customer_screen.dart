import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/l10n/generated/app_localizations.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../core/database/app_database.dart';
import '../../../core/layout/breakpoints.dart';
import '../../../core/money/money.dart';
import '../../../core/phone/phone.dart';
import '../../../core/session/current_user.dart';
import '../../../core/session/permissions.dart';
import '../../../core/session/session_controller.dart';
import '../../../core/sync/sync_controller.dart';
import '../../../core/time/shop_time.dart';
import '../../../core/widgets/sync_badge.dart';
import '../data/customer_repository.dart';
import '../data/providers.dart';

/// One customer: their balance, limit and dues, and their entries, newest
/// first. Every entry shows its date and time and who recorded it (two
/// field-test requests).
class CustomerScreen extends ConsumerWidget {
  final String customerId;

  /// Shown beside the list on a wide screen: no back arrow, the list is
  /// right there.
  final bool besideList;

  const CustomerScreen({
    super.key,
    required this.customerId,
    this.besideList = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final customer = ref.watch(customerProvider(customerId)).value;
    final entries = ref.watch(entriesProvider(customerId)).value ?? const [];
    final user = ref.watch(currentUserProvider);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !besideList,
        title: Text(
          customer?.customer.name ?? '',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [if (customer != null) _Menu(customer: customer, user: user)],
      ),
      body: ReadableWidth(
        maxWidth: Breakpoints.listWidth,
        child: ListView(
          padding: const EdgeInsets.only(bottom: AppSpacing.lg),
          children: [
            if (customer != null) ...[
              _Header(customer),
              _Account(customer),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                // Side by side when they fit, one above the other at large
                // text or on a narrow phone.
                child: Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    if (user.can(Permission.transactionsCreate)) ...[
                      FilledButton.icon(
                        onPressed: () =>
                            context.go('/customers/$customerId/debt'),
                        icon: const Icon(Icons.add_shopping_cart),
                        label: Text(l10n.recordDebt),
                      ),
                      OutlinedButton.icon(
                        onPressed: () =>
                            context.go('/customers/$customerId/payment'),
                        icon: const Icon(Icons.payments_outlined),
                        label: Text(l10n.recordPayment),
                      ),
                    ],
                    if (user.can(Permission.salesCreate))
                      OutlinedButton.icon(
                        onPressed: () =>
                            context.go('/customers/$customerId/sale'),
                        icon: const Icon(Icons.point_of_sale_outlined),
                        label: Text(l10n.saleCredit),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            if (entries.isEmpty)
              Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Text(
                  l10n.entriesEmpty,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge,
                ),
              ),
            for (final e in entries) ...[
              const Divider(height: 1),
              EntryTile(
                e,
                onTap: () =>
                    context.go('/customers/$customerId/entries/${e.id}'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Menu extends ConsumerWidget {
  final CustomerBalance customer;
  final SessionUser user;

  const _Menu({required this.customer, required this.user});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final id = customer.customer.id;
    final items = <(String, IconData, VoidCallback)>[
      if (user.can(Permission.customersUpdate))
        (
          l10n.customerEdit,
          Icons.edit_outlined,
          () => context.go('/customers/$id/edit'),
        ),
      if (user.can(Permission.customersCreditLimit))
        (
          l10n.creditLimitSet,
          Icons.speed_outlined,
          () => context.go('/customers/$id/limit'),
        ),
      if (user.can(Permission.customersDelete))
        (
          l10n.customerDelete,
          Icons.delete_outline,
          () => unawaited(_delete(context, ref)),
        ),
    ];
    if (items.isEmpty) return const SizedBox.shrink();
    return PopupMenuButton<int>(
      tooltip: l10n.moreOptions,
      onSelected: (i) => items[i].$3(),
      itemBuilder: (context) => [
        for (final (i, item) in items.indexed)
          PopupMenuItem(
            value: i,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(item.$2),
              title: Text(item.$1),
            ),
          ),
      ],
    );
  }

  /// Only at a zero balance: the server refuses anything else, so the phone
  /// says so at once instead of after a sync.
  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    if (customer.balanceCents != 0) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          content: Text(l10n.customerDeleteNotZero),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.issueDismiss),
            ),
          ],
        ),
      );
      return;
    }
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(l10n.customerDeleteConfirm(customer.customer.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (go != true) return;
    await ref.read(customerRepositoryProvider).delete(customer.customer.id);
    ref.read(syncProvider.notifier).requestSoon();
    if (context.mounted) context.go('/customers');
  }
}

/// Name, phone and balance on the dark card.
class _Header extends StatelessWidget {
  final CustomerBalance customer;

  const _Header(this.customer);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final c = customer.customer;
    final cents = customer.balanceCents;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Card(
        color: AppColors.primaryDark,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: AppColors.onPrimary,
                      ),
                    ),
                    if (c.phone != null)
                      Text(
                        Phone.display(c.phone!),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: AppColors.primaryLight,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        Money.format(cents.abs(), compact: true),
                        maxLines: 1,
                        style: theme.textTheme.headlineMedium?.copyWith(
                          color: AppColors.onPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      switch (cents) {
                        > 0 => l10n.balanceOwes,
                        < 0 => l10n.balanceAdvance,
                        _ => l10n.balanceCleared,
                      },
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: AppColors.primaryLight,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The credit limit and what is falling due, when there is either.
class _Account extends StatelessWidget {
  final CustomerBalance customer;

  const _Account(this.customer);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final limit = customer.creditLimitCents;
    final available = customer.availableCents;
    final dues = customer.dues;
    final lines = <(IconData, String, Color?)>[
      if (limit != null)
        (
          Icons.speed_outlined,
          '${l10n.creditLimit}: ${Money.format(limit, compact: true)} · '
              '${available! < 0 ? l10n.creditOver(Money.format(-available, compact: true)) : l10n.creditAvailable(Money.format(available, compact: true))}',
          available < 0 ? AppColors.debtRed : null,
        ),
      if (dues.isOverdue && dues.earliestDue != null)
        (
          Icons.warning_amber_rounded,
          l10n.duesOverdue(
            Money.format(dues.overdueCents, compact: true),
            ShopTime.date(dues.earliestDue!, locale),
          ),
          AppColors.debtRed,
        ),
      if (dues.nextDue != null)
        (
          Icons.event_outlined,
          l10n.duesNext(
            Money.format(dues.totalCents - dues.overdueCents, compact: true),
            ShopTime.date(dues.nextDue!, locale),
          ),
          null,
        ),
    ];
    if (lines.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (icon, text, color) in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 18, color: color ?? AppColors.textSecondary),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      text,
                      style: theme.textTheme.bodyMedium?.copyWith(color: color),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// One entry: what, when, by whom, and how much. A voided entry stays,
/// crossed out, as a paper ledger keeps a struck line.
class EntryTile extends ConsumerWidget {
  final LedgerEntryRow entry;
  final VoidCallback? onTap;

  const EntryTile(this.entry, {super.key, this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final debt = entry.type == 'debt';
    final voided = entry.isDeleted;
    final color = voided
        ? AppColors.textSecondary
        : debt
        ? AppColors.debtRed
        : AppColors.paymentGreen;
    final strike = voided
        ? const TextStyle(decoration: TextDecoration.lineThrough)
        : null;
    return ListTile(
      onTap: onTap,
      title: Text(
        entry.description ?? (debt ? l10n.entryDebt : l10n.entryPayment),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: strike,
      ),
      subtitle: Row(
        children: [
          Flexible(
            child: Text(
              [
                if (voided) l10n.entryVoided,
                debt ? l10n.entryDebt : l10n.entryPayment,
                ref
                    .watch(shopTimeProvider)
                    .dateTime(entry.transactionDate, locale),
                l10n.recordedBy(recordedBy(ref, l10n, entry.userId)),
              ].join(' · '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SyncBadge(entry.syncState),
        ],
      ),
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 140),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            '${debt ? '+' : '−'} ${Money.format(entry.amountCents, compact: true)}',
            style: theme.textTheme.titleMedium
                ?.copyWith(color: color)
                .merge(strike),
          ),
        ),
      ),
    );
  }
}

/// Who recorded an entry, by name: the signed-in user, someone on the
/// cached team list, or, before that list has been read, "someone else".
String recordedBy(WidgetRef ref, AppLocalizations l10n, String userId) {
  final me = ref.watch(sessionProvider.select((s) => s.value?.account.userId));
  if (userId == me) return ref.watch(currentUserProvider).name;
  return ref.watch(staffNamesProvider).value?[userId] ?? l10n.someoneElse;
}
