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
import '../../../core/sync/sync_controller.dart';
import '../../../core/time/shop_time.dart';
import '../../../core/widgets/record_detail.dart';
import '../../../core/widgets/sync_badge.dart';
import '../../customers/presentation/customer_screen.dart';
import '../data/providers.dart';
import '../data/supplier_repository.dart';
import 'suppliers_screen.dart';

/// One supplier: what the shop owes them, and their bills and payments,
/// newest first, each with its date, time and who recorded it.
class SupplierScreen extends ConsumerWidget {
  final String supplierId;
  final bool besideList;

  const SupplierScreen({
    super.key,
    required this.supplierId,
    this.besideList = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final supplier = ref.watch(supplierProvider(supplierId)).value;
    final entries =
        ref.watch(supplierEntriesProvider(supplierId)).value ?? const [];
    final user = ref.watch(currentUserProvider);
    final manage = user.can(Permission.suppliersManage);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !besideList,
        title: Text(
          supplier?.supplier.name ?? '',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [if (supplier != null && manage) _Menu(supplier: supplier)],
      ),
      body: ReadableWidth(
        maxWidth: Breakpoints.listWidth,
        child: ListView(
          padding: const EdgeInsets.only(bottom: AppSpacing.lg),
          children: [
            if (supplier != null) ...[
              _Header(supplier),
              if (manage)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                  ),
                  child: Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      FilledButton.icon(
                        onPressed: () =>
                            context.go('/suppliers/$supplierId/bill'),
                        icon: const Icon(Icons.receipt_long_outlined),
                        label: Text(l10n.supplierRecordBill),
                      ),
                      OutlinedButton.icon(
                        onPressed: () =>
                            context.go('/suppliers/$supplierId/payment'),
                        icon: const Icon(Icons.payments_outlined),
                        label: Text(l10n.supplierRecordPayment),
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
                  l10n.supplierEntriesEmpty,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge,
                ),
              ),
            for (final e in entries) ...[
              const Divider(height: 1),
              _EntryTile(
                e,
                onTap: () =>
                    context.go('/suppliers/$supplierId/entries/${e.id}'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Menu extends ConsumerWidget {
  final SupplierBalance supplier;

  const _Menu({required this.supplier});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final id = supplier.supplier.id;
    return PopupMenuButton<int>(
      tooltip: l10n.moreOptions,
      onSelected: (i) => i == 0
          ? context.go('/suppliers/$id/edit')
          : unawaited(_delete(context, ref)),
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 0,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.edit_outlined),
            title: Text(l10n.supplierEdit),
          ),
        ),
        PopupMenuItem(
          value: 1,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.delete_outline),
            title: Text(l10n.supplierDelete),
          ),
        ),
      ],
    );
  }

  /// Only at a zero balance, which the server checks again.
  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    if (supplier.balanceCents != 0) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          content: Text(l10n.supplierDeleteNotZero),
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
    if (!await confirmAction(
      context,
      message: l10n.supplierDeleteConfirm(supplier.supplier.name),
      action: l10n.delete,
    )) {
      return;
    }
    await ref.read(supplierRepositoryProvider).delete(supplier.supplier.id);
    ref.read(syncProvider.notifier).requestSoon();
    if (context.mounted) context.go('/suppliers');
  }
}

class _Header extends StatelessWidget {
  final SupplierBalance supplier;

  const _Header(this.supplier);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = supplier.supplier;
    final phone = s.phone;
    final notes = s.notes;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                    if (phone != null) Text(Phone.display(phone)),
                    if (notes != null)
                      Text(
                        notes,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Flexible(
                child: OwedText(
                  supplier.balanceCents,
                  style: theme.textTheme.headlineSmall,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One bill or payment: a bill adds to what the shop owes, a payment takes
/// from it. A voided one stays, crossed out.
class _EntryTile extends ConsumerWidget {
  final SupplierEntryRow entry;
  final VoidCallback onTap;

  const _EntryTile(this.entry, {required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final bill = entry.type == 'bill';
    final voided = entry.isDeleted;
    final strike = voided
        ? const TextStyle(decoration: TextDecoration.lineThrough)
        : null;
    return ListTile(
      onTap: onTap,
      title: Text(
        entry.description,
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
                bill ? l10n.supplierBill : l10n.supplierPayment,
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
            '${bill ? '+' : '−'} ${Money.format(entry.amountCents, compact: true)}',
            style: theme.textTheme.titleMedium
                ?.copyWith(
                  color: voided
                      ? AppColors.textSecondary
                      : bill
                      ? AppColors.debtRed
                      : AppColors.paymentGreen,
                )
                .merge(strike),
          ),
        ),
      ),
    );
  }
}
