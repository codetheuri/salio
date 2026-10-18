import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/l10n/generated/app_localizations.dart';
import '../../../app/shell/app_sections.dart';
import '../../../core/app_info.dart';
import '../../../core/layout/breakpoints.dart';
import '../../../core/session/current_user.dart';

/// The More page: on a phone, the sections that do not fit in the bottom
/// bar; on every screen, what support needs to know about this build.
/// Settings, the team and the account join it in M6.
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
