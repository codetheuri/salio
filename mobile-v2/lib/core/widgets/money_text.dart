import 'package:flutter/material.dart';

import '../../app/l10n/generated/app_localizations.dart';
import '../../app/theme/app_colors.dart';
import '../money/money.dart';

/// A balance: the amount and, under it, the word that says what it means.
/// Colour is never the only signal (docs/10, §5). Amounts shrink to fit and
/// never wrap.
class BalanceText extends StatelessWidget {
  final int cents;
  final TextStyle? style;
  final CrossAxisAlignment alignment;

  const BalanceText(
    this.cents, {
    super.key,
    this.style,
    this.alignment = CrossAxisAlignment.end,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final (color, label) = switch (cents) {
      > 0 => (AppColors.debtRed, l10n.balanceOwes),
      < 0 => (AppColors.paymentGreen, l10n.balanceAdvance),
      _ => (AppColors.paymentGreen, l10n.balanceCleared),
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: alignment,
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
