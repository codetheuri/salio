import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/l10n/generated/app_localizations.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../core/layout/breakpoints.dart';
import '../../../core/session/current_user.dart';
import '../../../core/session/permissions.dart';
import '../../../core/sync/sync_controller.dart';
import '../../../core/time/shop_time.dart';
import '../../../core/widgets/record_detail.dart';
import '../../customers/presentation/customer_screen.dart';
import '../../ledger/domain/payment_reference.dart';
import '../../ledger/presentation/widgets/money_fields.dart';
import '../data/providers.dart';

/// One bill or payment in full. Owners void it; nobody edits it.
class SupplierEntryScreen extends ConsumerWidget {
  final String supplierId;
  final String entryId;

  const SupplierEntryScreen({
    super.key,
    required this.supplierId,
    required this.entryId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final entry = ref.watch(supplierEntryProvider(entryId)).value;
    final user = ref.watch(currentUserProvider);
    final shop = ref.watch(shopTimeProvider);
    if (entry == null) return Scaffold(appBar: AppBar());

    final bill = entry.type == 'bill';
    final method = PaymentMethod.values
        .where((m) => m.wire == entry.paymentMethod)
        .firstOrNull;
    return Scaffold(
      appBar: AppBar(
        title: Text(bill ? l10n.supplierBill : l10n.supplierPayment),
      ),
      body: ReadableWidth(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            AmountHeadline(
              cents: entry.amountCents,
              voided: entry.isDeleted,
              color: bill ? AppColors.debtRed : AppColors.paymentGreen,
            ),
            const SizedBox(height: AppSpacing.md),
            DetailRows([
              (l10n.entryDescription, entry.description),
              (
                l10n.entryRecordedAt,
                shop.dateTime(entry.transactionDate, locale),
              ),
              (l10n.entryRecordedBy, recordedBy(ref, l10n, entry.userId)),
              if (entry.dueDate != null)
                (l10n.entryDueBy, ShopTime.date(entry.dueDate!, locale)),
              if (method != null)
                (l10n.entryMethod, paymentMethodLabel(l10n, method)),
              if (entry.reference != null)
                (l10n.entryReference, entry.reference!),
              (l10n.entryStatus, syncStateText(l10n, entry.syncState)),
            ]),
            if (user.can(Permission.suppliersVoid) && !entry.isDeleted) ...[
              const SizedBox(height: AppSpacing.lg),
              VoidButton(
                label: l10n.entryVoid,
                onPressed: () async {
                  if (!await confirmAction(
                    context,
                    message: l10n.entryVoidConfirm,
                    action: l10n.entryVoid,
                  )) {
                    return;
                  }
                  await ref
                      .read(supplierRepositoryProvider)
                      .voidEntry(entry.id);
                  ref.read(syncProvider.notifier).requestSoon();
                  if (context.mounted) context.go('/suppliers/$supplierId');
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}
