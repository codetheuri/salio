import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/l10n/generated/app_localizations.dart';
import '../../../app/router/app_router.dart';
import '../../../app/shell/app_sections.dart';
import '../../../core/app_info.dart';
import '../../../core/format/dates.dart';
import '../../../core/layout/breakpoints.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/session/current_user.dart';
import '../../../core/session/session_controller.dart';
import '../../../core/sync/sync_controller.dart';

/// The More page: the account and its sync, on a phone the sections that do
/// not fit in the bottom bar, and what support needs to know about this
/// build. Settings and the team join it in M6.
class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final nav = SectionNavigation.of(ref.watch(currentUserProvider));
    final env = ref.watch(appEnvironmentProvider);
    final info = ref.watch(packageInfoProvider).value;
    // On wider screens the rail already lists every section.
    final compact = MediaQuery.sizeOf(context).width < Breakpoints.medium;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.sectionMore)),
      body: ReadableWidth(
        child: ListView(
          children: [
            const _AccountSection(),
            const Divider(),
            if (compact && nav.overflow.isNotEmpty) ...[
              _Heading(l10n.moreSections),
              for (final s in nav.overflow)
                ListTile(
                  leading: Icon(s.icon),
                  title: Text(s.label(l10n)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.go(s.path),
                ),
              const Divider(),
            ],
            _Heading(l10n.aboutTitle),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text(
                info == null
                    ? '…'
                    : l10n.aboutVersion(info.version, info.buildNumber),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.layers_outlined),
              title: Text(l10n.aboutEnvironment),
              subtitle: Text(env.flavor.name),
            ),
            ListTile(
              leading: const Icon(Icons.dns_outlined),
              title: Text(l10n.aboutServer),
              subtitle: Text(
                env.apiBaseUrl.toString(),
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  final String text;

  const _Heading(this.text);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        text,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

class _AccountSection extends ConsumerWidget {
  const _AccountSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final session = ref.watch(sessionProvider).value;
    if (session == null) return const SizedBox.shrink();
    final status = ref.watch(syncProvider);
    final unsent = ref.watch(unsentCountProvider).value ?? 0;
    final last = ref.watch(lastSyncProvider).value;
    final locale = Localizations.localeOf(context).toLanguageTag();

    final String syncLine;
    if (!session.canSync) {
      syncLine = l10n.syncSignInAgain;
    } else if (status.running) {
      syncLine = l10n.syncing;
    } else if (status.failure == ApiFailure.offline ||
        status.failure == ApiFailure.timeout) {
      syncLine = l10n.syncOffline;
    } else {
      syncLine = last == null
          ? l10n.syncNever
          : l10n.syncLast(formatDateTime(last, locale));
    }

    return Column(
      children: [
        _Heading(l10n.accountTitle),
        ListTile(
          leading: const Icon(Icons.storefront_outlined),
          title: Text(
            session.account.businessName ?? session.account.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            '${session.account.name} · ${session.account.phone}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        ListTile(
          leading: const Icon(Icons.sync),
          title: Text(l10n.syncWaiting(unsent)),
          subtitle: Text(syncLine),
          trailing: session.canSync
              ? TextButton(
                  onPressed: status.running
                      ? null
                      : () => unawaited(
                          ref.read(syncProvider.notifier).syncNow(),
                        ),
                  child: Text(l10n.syncNow),
                )
              : TextButton(
                  onPressed: () => context.go(AppRoutes.signIn),
                  child: Text(l10n.signInButton),
                ),
        ),
        ListTile(
          leading: const Icon(Icons.logout),
          title: Text(l10n.signOut),
          onTap: () => unawaited(_signOut(context, ref, unsent)),
        ),
      ],
    );
  }

  /// Signing out keeps this account's file, but says plainly when records
  /// are still waiting, so nobody thinks they are lost (docs/10, §4.5).
  Future<void> _signOut(BuildContext context, WidgetRef ref, int unsent) async {
    final l10n = AppLocalizations.of(context);
    if (unsent > 0) {
      final go = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          content: Text(l10n.signOutUnsent(unsent)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l10n.signOut),
            ),
          ],
        ),
      );
      if (go != true) return;
    }
    await ref.read(sessionProvider.notifier).signOut();
  }
}
