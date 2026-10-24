import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/l10n/generated/app_localizations.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../core/database/app_database.dart';
import '../../../core/format/dates.dart';
import '../../../core/layout/breakpoints.dart';
import '../../../core/money/money.dart';
import '../../../core/widgets/sync_badge.dart';
import '../data/providers.dart';

/// One customer: their balance and their entries, newest first. Every entry
/// shows its date and time (a field-test request).
class CustomerScreen extends ConsumerWidget {
  final String customerId;

  const CustomerScreen({super.key, required this.customerId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final customer = ref.watch(customerProvider(customerId)).value;
    final entries = ref.watch(entriesProvider(customerId)).value ?? const [];
    final locale = Localizations.localeOf(context).toLanguageTag();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          customer?.customer.name ?? '',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go('/customers/$customerId/debt'),
        icon: const Icon(Icons.add_shopping_cart),
        label: Text(l10n.recordDebt),
      ),
      body: ReadableWidth(
        maxWidth: Breakpoints.listWidth,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 88),
          children: [
            Padding(
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
                              customer?.customer.name ?? '',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: AppColors.onPrimary,
                              ),
                            ),
                            if (customer?.customer.phone != null)
                              Text(
                                customer!.customer.phone!,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: AppColors.primaryLight,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Flexible(
                        child: _HeaderBalance(customer?.balanceCents ?? 0),
                      ),
                    ],
                  ),
                ),
              ),
            ),
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
              _EntryTile(e, locale: locale),
              const Divider(height: 1),
            ],
          ],
        ),
      ),
    );
  }
}

/// The balance on the dark header card, in white with its word beneath.
class _HeaderBalance extends StatelessWidget {
  final int cents;

  const _HeaderBalance(this.cents);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Column(
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
    );
  }
}

class _EntryTile extends StatelessWidget {
  final LedgerEntryRow entry;
  final String locale;

  const _EntryTile(this.entry, {required this.locale});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final debt = entry.type == 'debt';
    final color = debt ? AppColors.debtRed : AppColors.paymentGreen;
    return ListTile(
      title: Text(
        entry.description ?? (debt ? l10n.entryDebt : l10n.entryPayment),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Row(
        children: [
          Flexible(
            child: Text(
              '${debt ? l10n.entryDebt : l10n.entryPayment} · '
              '${formatDateTime(entry.transactionDate, locale)}',
              maxLines: 1,
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
            style: theme.textTheme.titleMedium?.copyWith(color: color),
          ),
        ),
      ),
    );
  }
}
