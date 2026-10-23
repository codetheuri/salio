import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/l10n/generated/app_localizations.dart';
import '../../../../app/theme/app_colors.dart';
import '../app_update_controller.dart';
import 'update_bar.dart';

/// The app's version on the More page, with checking and updating, and the
/// release notes when a new version is offered.
class AppUpdateTile extends ConsumerWidget {
  const AppUpdateTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(appUpdateProvider);
    final controller = ref.read(appUpdateProvider.notifier);
    final installed = state.installed ?? ref.watch(installedAppProvider).value;
    final status = UpdateStatus.of(
      state,
      controller,
      l10n,
      downloadPage: ref.watch(downloadPageProvider),
    );
    final notes = status == null
        ? ''
        : state.latest!.notesIn(Localizations.localeOf(context).languageCode);

    final String subtitle;
    if (status != null) {
      subtitle = [
        status.title,
        if (status.downloading || status.isError) status.subtitle ?? '',
        if (notes.isNotEmpty && !status.isError) notes,
      ].join('\n');
    } else if (state.checking) {
      subtitle = l10n.appChecking;
    } else if (state.error == UpdateError.checkFailed) {
      subtitle = l10n.updateErrorCheck;
    } else if (state.confirmedUpToDate) {
      subtitle = l10n.appUpToDate;
    } else {
      subtitle = l10n.appCheckHint;
    }

    // The button goes under the text rather than beside it, so long
    // Swahili labels and large text never squeeze the description.
    return ListTile(
      leading: Icon(
        status != null ? Icons.system_update : Icons.verified_outlined,
        color: status?.isError ?? false ? AppColors.error : AppColors.primary,
      ),
      title: Text(l10n.appVersionTitle(installed?.version ?? '')),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(subtitle),
          if (status?.downloading ?? false)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: LinearProgressIndicator(value: status!.progress),
            ),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: status != null
                ? FilledButton(
                    onPressed: status.onAction,
                    child: Text(status.actionLabel!),
                  )
                : TextButton(
                    onPressed: state.checking
                        ? null
                        : () => unawaited(controller.check(manual: true)),
                    child: Text(l10n.appCheck),
                  ),
          ),
        ],
      ),
    );
  }
}
