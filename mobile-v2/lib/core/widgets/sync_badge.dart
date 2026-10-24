import 'package:flutter/material.dart';

import '../../app/l10n/generated/app_localizations.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../database/app_database.dart';

/// A small mark after a record's name: a cloud while it waits to be sent,
/// a red mark when the server refused it and it needs attention. Nothing
/// once the server has it.
class SyncBadge extends StatelessWidget {
  final SyncState state;

  const SyncBadge(this.state, {super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final (icon, label, color) = switch (state) {
      SyncState.synced => (null, '', AppColors.textSecondary),
      SyncState.pending => (
        Icons.cloud_upload_outlined,
        l10n.unsent,
        AppColors.textSecondary,
      ),
      SyncState.refused => (
        Icons.error_outline,
        l10n.needsAttention,
        AppColors.error,
      ),
    };
    if (icon == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: AppSpacing.xs),
      child: Icon(icon, size: 16, semanticLabel: label, color: color),
    );
  }
}
