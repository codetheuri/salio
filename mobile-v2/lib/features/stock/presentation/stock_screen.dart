import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/l10n/generated/app_localizations.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../core/database/app_database.dart';
import '../../../core/layout/breakpoints.dart';
import '../../../core/session/current_user.dart';
import '../../../core/session/permissions.dart';
import '../../../core/time/shop_time.dart';
import '../../../core/widgets/failure_text.dart';
import '../../../core/widgets/sync_badge.dart';
import '../../../core/widgets/sync_button.dart';
import '../../customers/presentation/customer_screen.dart';
import '../data/providers.dart';
import '../data/purchase_order_api.dart';

/// Stock, in two tabs:
/// - **To order:** what ran out, noted by anyone, offline. Owners place a
///   purchase order from it.
/// - **Orders:** purchase orders, read from the server, so they need a
///   connection.
class StockScreen extends ConsumerWidget {
  /// Opens on the Orders tab, as after placing an order.
  final bool showOrders;

  const StockScreen({super.key, this.showOrders = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final user = ref.watch(currentUserProvider);
    return DefaultTabController(
      length: 2,
      initialIndex: showOrders ? 1 : 0,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.sectionStock),
          actions: const [SyncButton()],
          bottom: TabBar(
            tabs: [
              Tab(text: l10n.stockToOrder),
              Tab(text: l10n.stockOrders),
            ],
          ),
        ),
        floatingActionButton: user.can(Permission.stockRequest)
            ? FloatingActionButton.extended(
                onPressed: () => context.go('/stock/new'),
                icon: const Icon(Icons.add),
                label: Text(l10n.stockNoteNew),
              )
            : null,
        body: const ReadableWidth(
          maxWidth: Breakpoints.listWidth,
          child: TabBarView(children: [_ToOrder(), _Orders()]),
        ),
      ),
    );
  }
}

class _ToOrder extends ConsumerWidget {
  const _ToOrder();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final notes = ref.watch(toOrderProvider).value;
    final user = ref.watch(currentUserProvider);
    if (notes == null) return const Center(child: CircularProgressIndicator());
    return ListView(
      // Room for the last row above the button.
      padding: const EdgeInsets.only(bottom: 88),
      children: [
        if (user.can(Permission.purchaseOrdersManage))
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: FilledButton.icon(
                onPressed: () => context.go('/stock/order'),
                icon: const Icon(Icons.local_shipping_outlined),
                label: Text(l10n.orderPlace),
              ),
            ),
          ),
        if (notes.isEmpty) _Empty(l10n.stockToOrderEmpty),
        for (final n in notes) ...[_NoteTile(n), const Divider(height: 1)],
      ],
    );
  }
}

class _NoteTile extends ConsumerWidget {
  final StockRequestRow note;

  const _NoteTile(this.note);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final notes = note.notes;
    return ListTile(
      leading: const Icon(Icons.inventory_2_outlined),
      title: Row(
        children: [
          Flexible(
            child: Text(
              note.productName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SyncBadge(note.syncState),
        ],
      ),
      subtitle: Text(
        [
          l10n.stockRanOut(ShopTime.date(note.neededOn, locale)),
          l10n.recordedBy(recordedBy(ref, l10n, note.userId)),
          ?notes,
        ].join(' · '),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () => context.go('/stock/${note.id}'),
    );
  }
}

class _Orders extends ConsumerWidget {
  const _Orders();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final orders = ref.watch(purchaseOrdersProvider);
    return RefreshIndicator(
      onRefresh: () => ref.refresh(purchaseOrdersProvider.future),
      child: switch (orders) {
        AsyncData(:final value) when value.isEmpty => ListView(
          children: [_Empty(l10n.ordersEmpty)],
        ),
        AsyncData(:final value) => ListView.separated(
          padding: const EdgeInsets.only(bottom: 88),
          itemCount: value.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, i) => _OrderTile(value[i], locale: locale),
        ),
        AsyncError(:final error) => ListView(
          children: [
            _Empty(
              '${l10n.ordersNeedConnection}\n${describeFailure(l10n, error)}',
            ),
            Center(
              child: OutlinedButton(
                onPressed: () => ref.invalidate(purchaseOrdersProvider),
                child: Text(l10n.updateTryAgain),
              ),
            ),
          ],
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _OrderTile extends StatelessWidget {
  final PurchaseOrder order;
  final String locale;

  const _OrderTile(this.order, {required this.locale});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cancelled = order.cancelled;
    return ListTile(
      leading: const Icon(Icons.receipt_long_outlined),
      title: Text(
        '${order.reference} · ${order.supplierName}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: cancelled
            ? const TextStyle(decoration: TextDecoration.lineThrough)
            : null,
      ),
      subtitle: Text(
        [
          if (cancelled) l10n.orderCancelled,
          ShopTime.date(order.orderedOn, locale),
          l10n.orderProducts(order.lines.length),
        ].join(' · '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.go('/stock/orders/${order.id}'),
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
          Icons.inventory_2_outlined,
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
