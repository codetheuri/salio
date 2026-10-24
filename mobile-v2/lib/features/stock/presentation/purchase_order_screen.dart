import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/l10n/generated/app_localizations.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../core/layout/breakpoints.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/phone/phone.dart';
import '../../../core/quantity/quantity.dart';
import '../../../core/session/current_user.dart';
import '../../../core/session/permissions.dart';
import '../../../core/sync/sync_controller.dart';
import '../../../core/time/shop_time.dart';
import '../../../core/widgets/failure_text.dart';
import '../../../core/widgets/record_detail.dart';
import '../data/providers.dart';
import '../data/purchase_order_api.dart';

/// Hands a downloaded PDF to Android's share sheet: WhatsApp, email, Drive.
/// Replaced in tests, which have no share sheet.
typedef SharePdf = Future<void> Function(File file, String subject);

final sharePdfProvider = Provider<SharePdf>(
  (ref) => (file, subject) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/pdf')],
        subject: subject,
      ),
    );
  },
);

/// Where a PDF is written before sharing: the app's own cache, which
/// Android clears when space runs low. Replaced in tests.
final pdfFolderProvider = Provider<Future<Directory> Function()>(
  (ref) => getTemporaryDirectory,
);

/// One purchase order, read from the server: the products and quantities,
/// sent to the supplier as a PDF. Owners cancel it, which puts its stock
/// notes back on the list to order.
class PurchaseOrderScreen extends ConsumerStatefulWidget {
  final String orderId;

  const PurchaseOrderScreen({super.key, required this.orderId});

  @override
  ConsumerState<PurchaseOrderScreen> createState() =>
      _PurchaseOrderScreenState();
}

class _PurchaseOrderScreenState extends ConsumerState<PurchaseOrderScreen> {
  var _busy = false;
  String? _error;

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on ApiException catch (e) {
      if (mounted) {
        setState(
          () => _error = describeFailure(AppLocalizations.of(context), e),
        );
      }
    } on FileSystemException {
      if (mounted) {
        setState(() => _error = AppLocalizations.of(context).errorUnexpected);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share(PurchaseOrder order) => _run(() async {
    final bytes = await ref.read(purchaseOrderApiProvider).pdf(order.id);
    final folder = await ref.read(pdfFolderProvider)();
    final file = File('${folder.path}/${order.reference}.pdf');
    await file.writeAsBytes(bytes, flush: true);
    await ref.read(sharePdfProvider)(
      file,
      '${order.reference} · ${order.supplierName}',
    );
  });

  Future<void> _cancel(PurchaseOrder order) async {
    final l10n = AppLocalizations.of(context);
    if (!await confirmAction(
      context,
      message: l10n.orderCancelConfirm(order.reference),
      action: l10n.orderCancel,
    )) {
      return;
    }
    await _run(() async {
      await ref.read(purchaseOrderApiProvider).cancel(order.id);
      ref
        ..invalidate(purchaseOrderProvider(order.id))
        ..invalidate(purchaseOrdersProvider);
      // Its notes come back to the list with the next sync.
      ref.read(syncProvider.notifier).requestSoon();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final order = ref.watch(purchaseOrderProvider(widget.orderId));
    return Scaffold(
      appBar: AppBar(title: Text(order.value?.reference ?? l10n.stockOrders)),
      body: ReadableWidth(
        child: switch (order) {
          AsyncData(:final value) => _body(context, value),
          AsyncError(:final error) => ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              Text(
                '${l10n.ordersNeedConnection}\n${describeFailure(l10n, error)}',
              ),
              const SizedBox(height: AppSpacing.md),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: OutlinedButton(
                  onPressed: () =>
                      ref.invalidate(purchaseOrderProvider(widget.orderId)),
                  child: Text(l10n.updateTryAgain),
                ),
              ),
            ],
          ),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ),
    );
  }

  Widget _body(BuildContext context, PurchaseOrder order) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final user = ref.watch(currentUserProvider);
    final phone = order.supplierPhone;
    final notes = order.notes;
    final error = _error;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        if (order.cancelled)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text(
              l10n.orderCancelled,
              style: theme.textTheme.titleSmall?.copyWith(
                color: AppColors.debtRed,
              ),
            ),
          ),
        DetailRows([
          (l10n.orderSupplier, order.supplierName),
          if (phone != null) (l10n.signInPhone, Phone.display(phone)),
          (l10n.orderedOn, ShopTime.date(order.orderedOn, locale)),
          if (notes != null) (l10n.paymentNote, notes),
        ]),
        Text(l10n.orderProductsTitle, style: theme.textTheme.titleMedium),
        for (final line in order.lines)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(line.productName),
            trailing: Text(
              Quantity.toWire(line.quantity),
              style: theme.textTheme.titleMedium,
            ),
          ),
        const SizedBox(height: AppSpacing.md),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text(
              error,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.error,
              ),
            ),
          ),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            FilledButton.icon(
              onPressed: _busy ? null : () => unawaited(_share(order)),
              icon: const Icon(Icons.share_outlined),
              label: Text(l10n.orderSharePdf),
            ),
            if (user.can(Permission.purchaseOrdersManage) && !order.cancelled)
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.error,
                ),
                onPressed: _busy ? null : () => unawaited(_cancel(order)),
                icon: const Icon(Icons.block),
                label: Text(l10n.orderCancel),
              ),
          ],
        ),
        if (_busy)
          const Padding(
            padding: EdgeInsets.only(top: AppSpacing.md),
            child: LinearProgressIndicator(),
          ),
        const SizedBox(height: AppSpacing.md),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton(
            onPressed: () => context.go('/stock?tab=orders'),
            child: Text(l10n.ordersAll),
          ),
        ),
      ],
    );
  }
}
