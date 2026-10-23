import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/l10n/generated/app_localizations.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/app_info.dart';
import '../app_update_controller.dart';

/// What the update bar and the More tile say and offer in the current step.
class UpdateStatus {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// 0..1 while downloading (null before the size is known).
  final double? progress;
  final bool downloading;
  final bool isError;

  /// The bar offers "Later": only for an offer, never for work under way or
  /// a required update.
  final bool canPutOff;

  const UpdateStatus({
    required this.icon,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
    this.progress,
    this.downloading = false,
    this.isError = false,
    this.canPutOff = false,
  });

  /// "18", or "0.3" below 10 MB, where whole megabytes would round a small
  /// file down to nothing. The same rule as the download page.
  static String _mb(int bytes) {
    final mb = bytes / (1 << 20);
    return mb.toStringAsFixed(mb < 10 ? 1 : 0);
  }

  /// The status for [s]; null when there is nothing to update.
  static UpdateStatus? of(
    AppUpdateState s,
    AppUpdateController c,
    AppLocalizations l10n, {
    required String downloadPage,
  }) {
    final latest = s.latest;
    if (!s.available || latest == null) return null;
    final size = latest.files[s.abi]?.size ?? 0;
    return switch (s.step) {
      UpdateStep.idle when s.required => UpdateStatus(
        icon: Icons.sync_problem,
        title: l10n.updateRequiredTitle,
        subtitle: l10n.updateRequiredDetail,
        actionLabel: l10n.updateButton,
        onAction: c.update,
      ),
      UpdateStep.idle => UpdateStatus(
        icon: Icons.system_update,
        title: l10n.updateAvailable(latest.version),
        subtitle: l10n.updateSize(_mb(size)),
        actionLabel: l10n.updateButton,
        onAction: c.update,
        canPutOff: true,
      ),
      UpdateStep.downloading => UpdateStatus(
        icon: Icons.downloading,
        title: l10n.updateDownloading(((s.progress ?? 0) * 100).floor()),
        subtitle: l10n.updateDownloadingDetail(_mb(s.received), _mb(s.total)),
        actionLabel: l10n.updateStop,
        onAction: c.cancel,
        progress: s.progress,
        downloading: true,
      ),
      UpdateStep.needsPermission => UpdateStatus(
        icon: Icons.admin_panel_settings_outlined,
        title: l10n.updatePermissionTitle,
        subtitle: l10n.updatePermissionDetail,
        actionLabel: l10n.updateAllow,
        onAction: c.allowInstalls,
      ),
      UpdateStep.readyToInstall => UpdateStatus(
        icon: Icons.restart_alt,
        title: l10n.updateReadyTitle(latest.version),
        subtitle: l10n.updateReadyDetail,
        actionLabel: l10n.updateRestart,
        onAction: c.install,
        canPutOff: !s.required,
      ),
      UpdateStep.installing => UpdateStatus(
        icon: Icons.install_mobile,
        title: l10n.updateInstallingTitle,
        subtitle: l10n.updateInstallingDetail,
        actionLabel: l10n.updateRestart,
        onAction: c.install,
      ),
      UpdateStep.failed => UpdateStatus(
        icon: Icons.error_outline,
        title: l10n.updateFailedTitle,
        subtitle: switch (s.error) {
          UpdateError.stopped => l10n.updateErrorStopped,
          UpdateError.damaged => l10n.updateErrorDamaged,
          UpdateError.unavailable => l10n.updateErrorUnavailable,
          UpdateError.couldNotStart => l10n.updateErrorCouldNotStart(
            downloadPage,
          ),
          UpdateError.refused => [
            l10n.updateErrorRefused,
            if (s.androidMessage?.isNotEmpty ?? false) '(${s.androidMessage})',
          ].join(' '),
          UpdateError.checkFailed || null => l10n.updateErrorCheck,
        },
        actionLabel: l10n.updateTryAgain,
        onAction: c.update,
        isError: true,
      ),
    };
  }
}

/// The download page, as people would type it: "apis.salio.urizon.co.ke/app".
final downloadPageProvider = Provider<String>((ref) {
  final url = ref.watch(appEnvironmentProvider).apiBaseUrl.resolve('/app');
  return '${url.host}${url.hasPort ? ':${url.port}' : ''}${url.path}';
});

/// Wraps the whole app. When a newer version is offered, a bar under every
/// screen says so. Unlike DairyGo there is no screen that replaces the app:
/// a required update only stops syncing, and its bar cannot be put off
/// (docs/10, D12).
class UpdateBar extends ConsumerWidget {
  final Widget child;

  const UpdateBar({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appUpdateProvider);
    final l10n = AppLocalizations.of(context);
    final status = UpdateStatus.of(
      state,
      ref.read(appUpdateProvider.notifier),
      l10n,
      downloadPage: ref.watch(downloadPageProvider),
    );
    // A download on Wi-Fi shows only once it is ready; "Later" hides an
    // offer, never work under way.
    final show =
        status != null &&
        !(state.quiet && state.step == UpdateStep.downloading) &&
        !(state.dismissed && status.canPutOff);
    return Column(
      children: [
        Expanded(child: child),
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          child: show
              ? _Bar(status: status, required: state.required)
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

class _Bar extends ConsumerWidget {
  final UpdateStatus status;
  final bool required;

  const _Bar({required this.status, required this.required});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final color = status.isError
        ? AppColors.error
        : required
        ? AppColors.primaryDark
        : AppColors.primary;
    // The bar sits outside the navigator, so it brings its own Material and
    // text direction for its buttons.
    return Material(
      color: color,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.sm,
          AppSpacing.sm,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(status.icon, color: AppColors.onPrimary),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        status.title,
                        style: const TextStyle(
                          color: AppColors.onPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (status.subtitle != null)
                        Text(
                          status.subtitle!,
                          style: TextStyle(
                            color: AppColors.onPrimary.withValues(alpha: 0.9),
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            // Buttons on their own line, so they fit the smallest phones
            // with large text, in either language.
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Wrap(
                spacing: AppSpacing.xs,
                children: [
                  if (status.canPutOff)
                    TextButton(
                      onPressed: ref.read(appUpdateProvider.notifier).later,
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.onPrimary,
                        minimumSize: const Size(48, 48),
                      ),
                      child: Text(l10n.updateLater),
                    ),
                  if (status.actionLabel != null)
                    FilledButton(
                      onPressed: status.onAction,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.onPrimary,
                        foregroundColor: color,
                        minimumSize: const Size(64, 48),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                      ),
                      child: Text(status.actionLabel!),
                    ),
                ],
              ),
            ),
            if (status.downloading) ...[
              const SizedBox(height: AppSpacing.sm),
              LinearProgressIndicator(
                value: status.progress,
                color: AppColors.onPrimary,
                backgroundColor: Colors.white24,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
