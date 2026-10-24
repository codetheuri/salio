import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/l10n/generated/app_localizations.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../core/layout/breakpoints.dart';
import '../../../core/phone/phone.dart';
import '../../../core/widgets/money_text.dart';
import '../../../core/widgets/sync_badge.dart';
import '../../../core/widgets/sync_button.dart';
import '../data/customer_repository.dart';
import '../data/providers.dart';
import 'customer_screen.dart';

/// Customers, read from this phone's database, so it works offline and
/// updates itself when a sync brings changes.
///
/// From 840 dp the list and the chosen customer sit side by side (docs/10,
/// §2.2); narrower, the chosen customer has the whole screen.
class CustomersScreen extends StatelessWidget {
  /// The customer open beside the list, or on its own on a phone.
  final String? selectedId;

  const CustomersScreen({super.key, this.selectedId});

  @override
  Widget build(BuildContext context) {
    final twoPanes = MediaQuery.sizeOf(context).width >= Breakpoints.expanded;
    final selected = selectedId;
    if (!twoPanes) {
      return selected == null
          ? const _CustomerList()
          : CustomerScreen(customerId: selected);
    }
    return Row(
      children: [
        const SizedBox(
          width: Breakpoints.listPaneWidth,
          child: _CustomerList(),
        ),
        const VerticalDivider(width: 1, thickness: 1),
        Expanded(
          child: selected == null
              ? const _NoneSelected()
              : CustomerScreen(
                  key: ValueKey(selected),
                  customerId: selected,
                  besideList: true,
                ),
        ),
      ],
    );
  }
}

class _CustomerList extends ConsumerStatefulWidget {
  const _CustomerList();

  @override
  ConsumerState<_CustomerList> createState() => _CustomerListState();
}

class _CustomerListState extends ConsumerState<_CustomerList> {
  // Starts from the kept query, so coming back from a customer shows the
  // same list.
  late final _search = TextEditingController(
    text: ref.read(customerQueryProvider).search,
  );

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final query = ref.watch(customerQueryProvider);
    final customers = ref.watch(customersProvider);
    final selected = GoRouterState.of(context).pathParameters['id'];
    final filtered =
        query.search.trim().isNotEmpty || query.filter != CustomerFilter.all;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.sectionCustomers),
        actions: const [SyncButton()],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: l10n.customerAdd,
        onPressed: () => context.go('/customers/new'),
        child: const Icon(Icons.person_add),
      ),
      body: ReadableWidth(
        maxWidth: Breakpoints.listWidth,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.md,
                0,
              ),
              child: TextField(
                controller: _search,
                onChanged: ref.read(customerQueryProvider.notifier).search,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: l10n.customersSearch,
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: query.search.isEmpty
                      ? null
                      : IconButton(
                          tooltip: l10n.cancel,
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _search.clear();
                            ref.read(customerQueryProvider.notifier).search('');
                          },
                        ),
                ),
              ),
            ),
            // Scrolls sideways rather than wrapping: one row whatever the
            // language or text size.
            SizedBox(
              height: 56,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                children: [
                  for (final f in CustomerFilter.values)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(
                        end: AppSpacing.sm,
                      ),
                      child: ChoiceChip(
                        label: Text(_filterLabel(l10n, f)),
                        selected: query.filter == f,
                        onSelected: (_) =>
                            ref.read(customerQueryProvider.notifier).filter(f),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: switch (customers) {
                AsyncData(:final value) when value.isEmpty => _Empty(
                  filtered ? l10n.customersNoMatch : l10n.customersEmpty,
                ),
                AsyncData(:final value) => ListView.separated(
                  // Room for the last row above the + button.
                  padding: const EdgeInsets.only(bottom: 88),
                  itemCount: value.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) => _CustomerTile(
                    value[i],
                    selected: value[i].customer.id == selected,
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

  static String _filterLabel(AppLocalizations l10n, CustomerFilter f) =>
      switch (f) {
        CustomerFilter.all => l10n.filterAll,
        CustomerFilter.owing => l10n.filterOwing,
        CustomerFilter.overdue => l10n.filterOverdue,
        CustomerFilter.overLimit => l10n.filterOverLimit,
        CustomerFilter.advance => l10n.filterAdvance,
        CustomerFilter.cleared => l10n.filterCleared,
      };
}

class _CustomerTile extends StatelessWidget {
  final CustomerBalance item;
  final bool selected;

  const _CustomerTile(this.item, {required this.selected});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final c = item.customer;
    final phone = c.phone;
    return ListTile(
      selected: selected,
      selectedTileColor: AppColors.primaryLight.withValues(alpha: 0.35),
      leading: CircleAvatar(
        backgroundColor: AppColors.primaryLight,
        foregroundColor: AppColors.primaryDark,
        child: Text(
          c.name.isEmpty ? '?' : c.name.characters.first.toUpperCase(),
        ),
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          SyncBadge(item.syncState),
        ],
      ),
      subtitle: Text.rich(
        TextSpan(
          children: [
            if (item.dues.isOverdue)
              TextSpan(
                text: l10n.filterOverdue,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.debtRed,
                  fontWeight: FontWeight.w500,
                ),
              ),
            if (item.dues.isOverdue && phone != null)
              const TextSpan(text: ' · '),
            if (phone != null) TextSpan(text: Phone.display(phone)),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 140),
        child: BalanceText(item.balanceCents),
      ),
      onTap: () => context.go('/customers/${c.id}'),
    );
  }
}

class _NoneSelected extends StatelessWidget {
  const _NoneSelected();

  @override
  Widget build(BuildContext context) =>
      Scaffold(body: _Empty(AppLocalizations.of(context).customerSelect));
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
            Icons.people_outline,
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
