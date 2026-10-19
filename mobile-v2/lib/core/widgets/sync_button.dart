import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/l10n/generated/app_localizations.dart';
import '../sync/sync_controller.dart';

/// The app bar's sync button: a spinner while syncing, and a count of the
/// records not sent yet, so the shopkeeper can see nothing is lost offline.
class SyncButton extends ConsumerWidget {
  const SyncButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final status = ref.watch(syncProvider);
    final unsent = ref.watch(unsentCountProvider).value ?? 0;
    return IconButton(
      tooltip: status.running ? l10n.syncing : l10n.syncNow,
      onPressed: status.running
          ? null
          : () => unawaited(ref.read(syncProvider.notifier).syncNow()),
      icon: status.running
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Badge(
              isLabelVisible: unsent > 0,
              label: Text('$unsent'),
              child: Icon(
                status.failure == null ? Icons.sync : Icons.cloud_off,
              ),
            ),
    );
  }
}
