import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/l10n/generated/app_localizations.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../core/database/app_database.dart';
import '../../../core/layout/breakpoints.dart';
import '../../../core/money/money.dart';
import '../../../core/session/current_user.dart';
import '../../../core/session/permissions.dart';
import '../../../core/sync/sync_controller.dart';
import '../../../core/time/shop_time.dart';
import '../../customers/data/providers.dart';
import '../../customers/presentation/customer_screen.dart';
import '../domain/payment_reference.dart';

/// One entry in full: what, how much, when to the minute, who recorded it,
/// how it was paid, and whether it has reached the server. Owners can void
/// it; nobody can edit it (domain invariant 2).
class EntryScreen extends ConsumerWidget {
  final String customerId;
  final String entryId;

  const EntryScreen({
    super.key,
    required this.customerId,
    required this.entryId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final entry = ref.watch(entryProvider(entryId)).value;
    final user = ref.watch(currentUserProvider);
    final shop = ref.watch(shopTimeProvider);

    if (entry == null) {
      return Scaffold(appBar: AppBar());
    }
    final debt = entry.type == 'debt';
    final rows = <(String, String)>[
      (l10n.entryRecordedAt, shop.dateTime(entry.transactionDate, locale)),
      (l10n.entryRecordedBy, recordedBy(ref, l10n, entry.userId)),
      if (entry.description != null)
        (l10n.entryDescription, entry.description!),
      if (entry.dueDate != null)
        (l10n.entryDueBy, ShopTime.date(entry.dueDate!, locale)),
      if (entry.paymentMethod != null)
        (l10n.entryMethod, _method(l10n, entry.paymentMethod!)),
      if (entry.reference != null) (l10n.entryReference, entry.reference!),
      (
        l10n.entryStatus,
        switch (entry.syncState) {
          SyncState.synced => l10n.entrySent,
          SyncState.pending => l10n.unsent,
          SyncState.refused => l10n.needsAttention,
        },
      ),
    ];
    // A credit sale's debt is the server's, made from the sale; voiding the
    // sale voids it (M4).
    final fromSale = entry.saleId != null;
    final canVoid =
        user.can(Permission.transactionsVoid) && !entry.isDeleted && !fromSale;

    return Scaffold(
      appBar: AppBar(
        title: Text(debt ? l10n.entryTitleDebt : l10n.entryTitlePayment),
      ),
      body: ReadableWidth(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                Money.format(entry.amountCents),
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: entry.isDeleted
                      ? AppColors.textSecondary
                      : debt
                      ? AppColors.debtRed
                      : AppColors.paymentGreen,
                  decoration: entry.isDeleted
                      ? TextDecoration.lineThrough
                      : null,
                ),
              ),
            ),
            if (entry.isDeleted)
              Text(
                l10n.entryVoided,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: AppColors.debtRed,
                ),
              ),
            const SizedBox(height: AppSpacing.md),
            for (final (label, value) in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    Text(value, style: theme.textTheme.bodyLarge),
                  ],
                ),
              ),
            if (fromSale)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.point_of_sale_outlined),
                title: Text(l10n.entryFromSale),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.go('/sales/${entry.saleId}'),
              ),
            if (canVoid) ...[
              const SizedBox(height: AppSpacing.lg),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                  ),
                  onPressed: () => _void(context, ref, entry),
                  icon: const Icon(Icons.block),
                  label: Text(l10n.entryVoid),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _method(AppLocalizations l10n, String wire) =>
      switch (PaymentMethod.values.where((m) => m.wire == wire).firstOrNull) {
        PaymentMethod.cash => l10n.methodCash,
        PaymentMethod.mpesa => l10n.methodMpesa,
        PaymentMethod.bank => l10n.methodBank,
        null => wire,
      };

  Future<void> _void(
    BuildContext context,
    WidgetRef ref,
    LedgerEntryRow entry,
  ) async {
    final l10n = AppLocalizations.of(context);
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(l10n.entryVoidConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.entryVoid),
          ),
        ],
      ),
    );
    if (go != true) return;
    await ref.read(ledgerRepositoryProvider).voidEntry(entry.id);
    ref.read(syncProvider.notifier).requestSoon();
    if (context.mounted) context.go('/customers/$customerId');
  }
}
