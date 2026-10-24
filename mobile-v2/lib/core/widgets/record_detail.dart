import 'package:flutter/material.dart';

import '../../app/l10n/generated/app_localizations.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../database/app_database.dart';
import '../money/money.dart';

/// The pieces of a record's own screen (an entry, a sale, a supplier's
/// bill): the amount, large, then label-and-value rows. Labels sit above
/// values, so a long value wraps instead of squeezing its label.

/// The amount at the top, crossed out and labelled when voided.
class AmountHeadline extends StatelessWidget {
  final int cents;
  final Color color;
  final bool voided;

  const AmountHeadline({
    super.key,
    required this.cents,
    required this.color,
    this.voided = false,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: Text(
            Money.format(cents),
            style: theme.textTheme.headlineMedium?.copyWith(
              color: voided ? AppColors.textSecondary : color,
              decoration: voided ? TextDecoration.lineThrough : null,
            ),
          ),
        ),
        if (voided)
          Text(
            l10n.entryVoided,
            style: theme.textTheme.titleSmall?.copyWith(
              color: AppColors.debtRed,
            ),
          ),
      ],
    );
  }
}

/// Label-and-value rows.
class DetailRows extends StatelessWidget {
  final List<(String, String)> rows;

  const DetailRows(this.rows, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
      ],
    );
  }
}

/// Whether the server has a record yet, in words.
String syncStateText(AppLocalizations l10n, SyncState state) => switch (state) {
  SyncState.synced => l10n.entrySent,
  SyncState.pending => l10n.unsent,
  SyncState.refused => l10n.needsAttention,
};

/// A red outlined button for voiding, at the start of the row.
class VoidButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const VoidButton({super.key, required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) => Align(
    alignment: AlignmentDirectional.centerStart,
    child: OutlinedButton.icon(
      style: OutlinedButton.styleFrom(foregroundColor: AppColors.error),
      onPressed: onPressed,
      icon: const Icon(Icons.block),
      label: Text(label),
    ),
  );
}

/// Asks before something that cannot be undone. True to go ahead.
Future<bool> confirmAction(
  BuildContext context, {
  required String message,
  required String action,
}) async {
  final l10n = AppLocalizations.of(context);
  final go = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(action),
        ),
      ],
    ),
  );
  return go == true;
}
