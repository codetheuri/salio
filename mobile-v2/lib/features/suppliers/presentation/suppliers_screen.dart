import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/l10n/generated/app_localizations.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../core/layout/breakpoints.dart';
import '../../../core/money/money.dart';
import '../../../core/phone/phone.dart';
import '../../../core/session/current_user.dart';
import '../../../core/session/permissions.dart';
import '../../../core/widgets/sync_badge.dart';
import '../../../core/widgets/sync_button.dart';
import '../data/providers.dart';
import '../data/supplier_repository.dart';
import 'supplier_screen.dart';

/// Who the shop buys from, and what it owes each (owners). Read from this
/// phone, so it works offline. From 840 dp the list and the chosen supplier
/// sit side by side.
class SuppliersScreen extends StatelessWidget {
  final String? selectedId;

  const SuppliersScreen({super.key, this.selectedId});

  @override
  Widget build(BuildContext context) {
    final twoPanes = MediaQuery.sizeOf(context).width >= Breakpoints.expanded;
    final selected = selectedId;
    if (!twoPanes) {
      return selected == null
          ? const _SupplierList()
          : SupplierScreen(supplierId: selected);
    }
    return Row(
      children: [
        const SizedBox(
          width: Breakpoints.listPaneWidth,
          child: _SupplierList(),
        ),
        const VerticalDivider(width: 1, thickness: 1),
        Expanded(
          child: selected == null
              ? Scaffold(
                  body: _Empty(AppLocalizations.of(context).supplierSelect),
                )
              : SupplierScreen(
                  key: ValueKey(selected),
                  supplierId: selected,
                  besideList: true,
                ),
        ),
      ],
    );
  }
}

class _SupplierList extends ConsumerStatefulWidget {
  const _SupplierList();

  @override
  ConsumerState<_SupplierList> createState() => _SupplierListState();
}

class _SupplierListState extends ConsumerState<_SupplierList> {
  late final _search = TextEditingController(
    text: ref.read(supplierSearchProvider),
  );

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final suppliers = ref.watch(suppliersProvider);
    final user = ref.watch(currentUserProvider);
    final selected = GoRouterState.of(context).pathParameters['id'];
    final searching = ref.watch(supplierSearchProvider).trim().isNotEmpty;
    final total = (suppliers.value ?? const <SupplierBalance>[])
        .where((s) => s.balanceCents > 0)
        .fold(0, (a, s) => a + s.balanceCents);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.sectionSuppliers),
        actions: const [SyncButton()],
      ),
      floatingActionButton: user.can(Permission.suppliersManage)
          ? FloatingActionButton(
              tooltip: l10n.supplierAdd,
              onPressed: () => context.go('/suppliers/new'),
              child: const Icon(Icons.add_business_outlined),
            )
          : null,
      body: ReadableWidth(
        maxWidth: Breakpoints.listWidth,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.md,
                AppSpacing.sm,
              ),
              child: TextField(
                controller: _search,
                onChanged: ref.read(supplierSearchProvider.notifier).set,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: l10n.customersSearch,
                  prefixIcon: const Icon(Icons.search),
                ),
              ),
            ),
            if (total > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    l10n.suppliersOwedTotal(Money.format(total, compact: true)),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ),
            Expanded(
              child: switch (suppliers) {
                AsyncData(:final value) when value.isEmpty => _Empty(
                  searching ? l10n.suppliersNoMatch : l10n.suppliersEmpty,
                ),
                AsyncData(:final value) => ListView.separated(
                  padding: const EdgeInsets.only(bottom: 88),
                  itemCount: value.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) => _SupplierTile(
                    value[i],
                    selected: value[i].supplier.id == selected,
                  ),
                ),
                AsyncError() => _Empty(l10n.errorUnexpected),
                _ => const Center(child: CircularProgressIndicator()),
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _SupplierTile extends StatelessWidget {
  final SupplierBalance item;
  final bool selected;

  const _SupplierTile(this.item, {required this.selected});

  @override
  Widget build(BuildContext context) {
    final s = item.supplier;
    final phone = s.phone;
    return ListTile(
      selected: selected,
      selectedTileColor: AppColors.primaryLight.withValues(alpha: 0.35),
      leading: const CircleAvatar(
        backgroundColor: AppColors.primaryLight,
        foregroundColor: AppColors.primaryDark,
        child: Icon(Icons.local_shipping_outlined),
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          SyncBadge(item.syncState),
        ],
      ),
      subtitle: phone == null ? null : Text(Phone.display(phone)),
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 140),
        child: OwedText(item.balanceCents),
      ),
      onTap: () => context.go('/suppliers/${s.id}'),
    );
  }
}

/// What the shop owes a supplier, with the word that says what it means:
/// colour is never the only signal.
class OwedText extends StatelessWidget {
  final int cents;
  final TextStyle? style;

  const OwedText(this.cents, {super.key, this.style});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final (color, label) = switch (cents) {
      > 0 => (AppColors.debtRed, l10n.supplierWeOwe),
      < 0 => (AppColors.paymentGreen, l10n.supplierPrepaid),
      _ => (AppColors.paymentGreen, l10n.balanceCleared),
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            Money.format(cents.abs(), compact: true),
            maxLines: 1,
            style: (style ?? theme.textTheme.titleMedium)?.copyWith(
              color: color,
            ),
          ),
        ),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelMedium?.copyWith(color: color),
        ),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  final String text;

  const _Empty(this.text);

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.local_shipping_outlined,
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
    ),
  );
}
