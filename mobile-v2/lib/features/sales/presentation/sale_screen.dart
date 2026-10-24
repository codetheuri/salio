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
import '../data/providers.dart';
import '../data/sales_repository.dart';
import 'sales_screen.dart';

/// One sale in full. Owners void it, and with it a credit sale's debt;
/// nobody edits it (domain invariant 2).
class SaleScreen extends ConsumerWidget {
  final String saleId;
  final bool besideList;

  const SaleScreen({super.key, required this.saleId, this.besideList = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final item = ref.watch(saleProvider(saleId)).value;
    final user = ref.watch(currentUserProvider);
    final shop = ref.watch(shopTimeProvider);

    if (item == null) {
      return Scaffold(appBar: AppBar(automaticallyImplyLeading: !besideList));
    }
    final s = item.sale;
    final method = SaleMethod.of(s.paymentMethod);
    final customerName = item.customerName;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !besideList,
        title: Text(saleTitle(s), maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: ReadableWidth(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            AmountHeadline(
              cents: s.amountCents,
              voided: s.isDeleted,
              color: method == SaleMethod.credit
                  ? AppColors.debtRed
                  : AppColors.paymentGreen,
            ),
            const SizedBox(height: AppSpacing.md),
            DetailRows([
              (l10n.saleProduct, saleTitle(s)),
              (l10n.saleSoldAt, shop.dateTime(s.saleDate, locale)),
              (l10n.saleSoldBy, recordedBy(ref, l10n, s.userId)),
              (l10n.entryMethod, saleMethodLabel(l10n, method)),
              if (s.reference != null) (l10n.entryReference, s.reference!),
              if (s.dueDate != null)
                (l10n.entryDueBy, ShopTime.date(s.dueDate!, locale)),
              if (s.notes != null) (l10n.paymentNote, s.notes!),
              (l10n.entryStatus, syncStateText(l10n, s.syncState)),
            ]),
            if (s.customerId != null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.person_outline),
                title: Text(customerName ?? l10n.someoneElse),
                subtitle: Text(
                  method == SaleMethod.credit
                      ? l10n.saleOnAccount
                      : l10n.saleCustomer,
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.go('/customers/${s.customerId}'),
              ),
            if (user.can(Permission.salesVoid) && !s.isDeleted) ...[
              const SizedBox(height: AppSpacing.lg),
              VoidButton(
                label: l10n.saleVoid,
                onPressed: () => _void(context, ref, item),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _void(
    BuildContext context,
    WidgetRef ref,
    SaleWithCustomer item,
  ) async {
    final l10n = AppLocalizations.of(context);
    final credit = item.sale.paymentMethod == SaleMethod.credit.wire;
    if (!await confirmAction(
      context,
      message: credit ? l10n.saleVoidConfirmCredit : l10n.saleVoidConfirm,
      action: l10n.saleVoid,
    )) {
      return;
    }
    await ref.read(salesRepositoryProvider).voidSale(item.sale.id);
    ref.read(syncProvider.notifier).requestSoon();
    if (context.mounted && !besideList) context.go('/sales');
  }
}
