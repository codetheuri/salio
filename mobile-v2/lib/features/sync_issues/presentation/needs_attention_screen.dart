import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/generated/app_localizations.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../core/format/dates.dart';
import '../../../core/layout/breakpoints.dart';
import '../../../core/money/money.dart';
import '../data/providers.dart';
import '../data/sync_issue_repository.dart';

/// What the server refused, or a change it undid, with what the user can
/// do about each (docs/10, §4.3). Nothing here is lost by waiting: a
/// refused record stays on the phone until the user decides.
class NeedsAttentionScreen extends ConsumerWidget {
  const NeedsAttentionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final issues = ref.watch(syncIssuesProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.needsAttention)),
      body: ReadableWidth(
        maxWidth: Breakpoints.listWidth,
        child: switch (issues) {
          AsyncData(:final value) when value.isEmpty => Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Text(
                l10n.needsAttentionEmpty,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
          ),
          AsyncData(:final value) => ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            itemCount: value.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) => _IssueTile(value[i]),
          ),
          AsyncError() => Center(child: Text(l10n.errorUnexpected)),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ),
    );
  }
}

class _IssueTile extends ConsumerWidget {
  final SyncIssueView view;

  const _IssueTile(this.view);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.only(
                  end: AppSpacing.sm,
                  top: 2,
                ),
                child: Icon(
                  view.isNotice ? Icons.info_outline : Icons.error_outline,
                  size: 20,
                  color: view.isNotice
                      ? AppColors.textSecondary
                      : AppColors.error,
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_record(l10n), style: theme.textTheme.titleSmall),
                    const SizedBox(height: 2),
                    Text(_reason(l10n), style: theme.textTheme.bodyMedium),
                    const SizedBox(height: 2),
                    Text(
                      formatDateTime(view.issue.createdAt, locale),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          // Wraps under the text on a narrow screen or at large text,
          // rather than squeezing it.
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: AppSpacing.xs,
              children: [
                for (final action in view.actions)
                  TextButton(
                    onPressed: () => unawaited(_act(context, ref, action)),
                    child: Text(switch (action) {
                      IssueAction.dismiss => l10n.issueDismiss,
                      IssueAction.discard => l10n.issueDiscard,
                      IssueAction.useExisting => l10n.issueUseExisting,
                    }),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _record(AppLocalizations l10n) {
    final name = view.name;
    if (name == null) return l10n.issueRecordGone;
    final amount = view.amountCents == null
        ? ''
        : Money.format(view.amountCents!, compact: true);
    return switch (view.table) {
      'customers' => l10n.issueRecordCustomer(name),
      'transactions' when view.entryType == 'payment' =>
        l10n.issueRecordPayment(amount, name),
      'transactions' => l10n.issueRecordDebt(amount, name),
      'sales' => l10n.issueRecordSale(name, amount),
      'suppliers' => l10n.issueRecordSupplier(name),
      'supplier_transactions' => l10n.issueRecordSupplierEntry(amount, name),
      'stock_requests' => l10n.issueRecordStock(name),
      _ => name,
    };
  }

  String _reason(AppLocalizations l10n) => switch (view.reason) {
    'duplicate' when view.table == 'transactions' => l10n.issueDuplicatePayment,
    'duplicate' when view.table == 'customers' => l10n.issueDuplicateCustomer,
    'duplicate' => l10n.issueDuplicate,
    'forbidden' => l10n.issueForbidden,
    'has_balance' => l10n.issueHasBalance,
    'already_ordered' => l10n.issueAlreadyOrdered,
    'unknown_customer' => l10n.issueWaitingCustomer,
    'unknown_supplier' => l10n.issueWaitingSupplier,
    _ => l10n.issueInvalid,
  };

  Future<void> _act(
    BuildContext context,
    WidgetRef ref,
    IssueAction action,
  ) async {
    final repo = ref.read(syncIssueRepositoryProvider);
    switch (action) {
      case IssueAction.dismiss:
        await repo.dismiss(view.issue);
      case IssueAction.useExisting:
        await repo.useExisting(view.issue, view.existingCustomerId!);
      case IssueAction.discard:
        final l10n = AppLocalizations.of(context);
        final go = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            content: Text(l10n.issueDiscardConfirm),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(l10n.cancel),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(l10n.issueDiscard),
              ),
            ],
          ),
        );
        if (go == true) await repo.discard(view.issue);
    }
  }
}
