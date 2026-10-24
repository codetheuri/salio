import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/l10n/generated/app_localizations.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../core/layout/breakpoints.dart';
import '../../../core/session/current_user.dart';
import '../../../core/session/permissions.dart';
import '../data/report_repository.dart';
import 'report_screen.dart';

/// The reports a user may open. They are read online, so each says so,
/// and the last copy of each stays readable offline. A customer's
/// statement is opened from the customer.
class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final user = ref.watch(currentUserProvider);
    final reports = [
      (ReportKind.ageing, Icons.hourglass_bottom, l10n.reportAgeingHint),
      (ReportKind.sales, Icons.point_of_sale_outlined, l10n.reportSalesHint),
      (
        ReportKind.collections,
        Icons.payments_outlined,
        l10n.reportCollectionsHint,
      ),
      if (user.can(Permission.suppliersRead))
        (
          ReportKind.payables,
          Icons.local_shipping_outlined,
          l10n.reportPayablesHint,
        ),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(l10n.sectionReports)),
      body: ReadableWidth(
        maxWidth: Breakpoints.listWidth,
        child: ListView(
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Text(
                l10n.reportsIntro,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            for (final (kind, icon, hint) in reports) ...[
              ListTile(
                leading: Icon(icon),
                title: Text(reportTitle(l10n, kind)),
                subtitle: Text(hint),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.go('/reports/${kind.name}'),
              ),
              const Divider(height: 1),
            ],
          ],
        ),
      ),
    );
  }
}
