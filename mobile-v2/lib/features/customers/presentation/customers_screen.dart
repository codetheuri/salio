import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/l10n/generated/app_localizations.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../core/layout/breakpoints.dart';
import '../../../core/widgets/money_text.dart';
import '../../../core/widgets/sync_badge.dart';
import '../../../core/widgets/sync_button.dart';
import '../data/customer_repository.dart';
import '../data/providers.dart';

/// Every customer with their balance, read from this phone's database, so
/// it works offline and updates itself when a sync brings changes.
/// Search and filters arrive in M3.
class CustomersScreen extends ConsumerWidget {
  const CustomersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final customers = ref.watch(customersProvider);

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
        child: switch (customers) {
          AsyncData(:final value) when value.isEmpty => _Empty(
            l10n.customersEmpty,
          ),
          AsyncData(:final value) => ListView.separated(
            // Room for the last row above the + button.
            padding: const EdgeInsets.only(bottom: 88),
            itemCount: value.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) => _CustomerTile(value[i]),
          ),
          AsyncError() => _Empty(l10n.errorUnexpected),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ),
    );
  }
}

class _CustomerTile extends StatelessWidget {
  final CustomerBalance item;

  const _CustomerTile(this.item);

  @override
  Widget build(BuildContext context) {
    final c = item.customer;
    return ListTile(
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
      subtitle: c.phone == null
          ? null
          : Text(c.phone!, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 140),
        child: BalanceText(item.balanceCents),
      ),
      onTap: () => context.go('/customers/${c.id}'),
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
