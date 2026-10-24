import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/l10n/generated/app_localizations.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../core/files/pdf_files.dart';
import '../../../core/layout/breakpoints.dart';
import '../../../core/money/money.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/quantity/quantity.dart';
import '../../../core/time/shop_time.dart';
import '../../../core/widgets/failure_text.dart';
import '../data/providers.dart';
import '../data/report_repository.dart';

/// The title of each report, also used on the Reports list.
String reportTitle(AppLocalizations l10n, ReportKind kind) => switch (kind) {
  ReportKind.ageing => l10n.reportAgeing,
  ReportKind.sales => l10n.reportSales,
  ReportKind.collections => l10n.reportCollections,
  ReportKind.payables => l10n.reportPayables,
  ReportKind.statement => l10n.reportStatement,
};

/// A preset period: the last [days] days, ending today; or this month.
enum PeriodChoice { today, week, month30, thisMonth, custom }

/// One report, read online. The last copy stays readable offline, with the
/// time it was read; the PDF is saved, then opened or shared.
class ReportScreen extends ConsumerStatefulWidget {
  final ReportKind kind;

  /// The customer, for a statement.
  final String? customerId;

  const ReportScreen({super.key, required this.kind, this.customerId});

  @override
  ConsumerState<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends ConsumerState<ReportScreen> {
  /// A statement starts with the server's own 90 days; the others with 30.
  late var _choice = widget.kind == ReportKind.statement
      ? PeriodChoice.custom
      : PeriodChoice.month30;
  DateTimeRange? _custom;
  var _pdfBusy = false;

  ReportRequest _request(DateTime today) {
    if (!widget.kind.hasPeriod) {
      return ReportRequest(widget.kind, customerId: widget.customerId);
    }
    final (from, to) = switch (_choice) {
      PeriodChoice.today => (today, today),
      PeriodChoice.week => (today.subtract(const Duration(days: 6)), today),
      PeriodChoice.month30 => (today.subtract(const Duration(days: 29)), today),
      PeriodChoice.thisMonth => (DateTime.utc(today.year, today.month), today),
      PeriodChoice.custom => (_custom?.start, _custom?.end),
    };
    return ReportRequest(
      widget.kind,
      from: from,
      to: to,
      customerId: widget.customerId,
    );
  }

  Future<void> _pickRange(DateTime today) async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime.utc(today.year - 3),
      lastDate: today,
      initialDateRange:
          _custom ??
          DateTimeRange(
            start: today.subtract(const Duration(days: 29)),
            end: today,
          ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _choice = PeriodChoice.custom;
      _custom = DateTimeRange(
        start: DateTime.utc(
          picked.start.year,
          picked.start.month,
          picked.start.day,
        ),
        end: DateTime.utc(picked.end.year, picked.end.month, picked.end.day),
      );
    });
  }

  Future<void> _pdf(ReportRequest request, {required bool share}) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _pdfBusy = true);
    try {
      final bytes = await ref.read(reportRepositoryProvider).pdf(request);
      final file = await savePdf(
        ref.read(pdfFolderProvider),
        '${request.key.replaceAll(':', '_')}.pdf',
        bytes,
      );
      if (share) {
        await ref.read(sharePdfProvider)(file, reportTitle(l10n, widget.kind));
      } else if (!await ref.read(openPdfProvider)(file)) {
        messenger.showSnackBar(SnackBar(content: Text(l10n.pdfNoViewer)));
      }
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(describeFailure(l10n, e))));
    } on FileSystemException {
      messenger.showSnackBar(SnackBar(content: Text(l10n.errorUnexpected)));
    } finally {
      if (mounted) setState(() => _pdfBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final today = ref.watch(shopTodayProvider);
    final request = _request(today);
    final report = ref.watch(reportProvider(request));
    return Scaffold(
      appBar: AppBar(
        title: Text(
          reportTitle(l10n, widget.kind),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: l10n.pdfOpen,
            icon: const Icon(Icons.picture_as_pdf_outlined),
            onPressed: _pdfBusy
                ? null
                : () => unawaited(_pdf(request, share: false)),
          ),
          IconButton(
            tooltip: l10n.pdfShare,
            icon: const Icon(Icons.share_outlined),
            onPressed: _pdfBusy
                ? null
                : () => unawaited(_pdf(request, share: true)),
          ),
        ],
      ),
      body: ReadableWidth(
        maxWidth: Breakpoints.listWidth,
        child: RefreshIndicator(
          onRefresh: () => ref.refresh(reportProvider(request).future),
          child: ListView(
            padding: const EdgeInsets.only(bottom: AppSpacing.lg),
            children: [
              if (_pdfBusy) const LinearProgressIndicator(),
              if (widget.kind.hasPeriod) _periodChips(l10n, today),
              ...switch (report) {
                AsyncData(:final value) => [
                  _AsOf(value),
                  ..._content(context, value.data),
                ],
                AsyncError(:final error) => [
                  _Message(
                    '${l10n.reportsNeedConnection}\n${describeFailure(l10n, error)}',
                    onRetry: () => ref.invalidate(reportProvider(request)),
                  ),
                ],
                _ => [
                  const Padding(
                    padding: EdgeInsets.all(AppSpacing.lg),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ],
              },
            ],
          ),
        ),
      ),
    );
  }

  Widget _periodChips(AppLocalizations l10n, DateTime today) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    final custom = _custom;
    String label(PeriodChoice c) => switch (c) {
      PeriodChoice.today => l10n.today,
      PeriodChoice.week => l10n.period7Days,
      PeriodChoice.month30 => l10n.period30Days,
      PeriodChoice.thisMonth => l10n.periodThisMonth,
      PeriodChoice.custom =>
        custom == null
            ? (widget.kind == ReportKind.statement
                  ? l10n.period90Days
                  : l10n.periodChoose)
            : '${ShopTime.date(custom.start, locale)} – '
                  '${ShopTime.date(custom.end, locale)}',
    };
    // One row that scrolls sideways, whatever the language or text size.
    return SizedBox(
      height: 56,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        children: [
          for (final c in PeriodChoice.values)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: AppSpacing.sm),
              child: ChoiceChip(
                label: Text(label(c)),
                selected: _choice == c,
                onSelected: (_) => c == PeriodChoice.custom
                    ? unawaited(_pickRange(today))
                    : setState(() => _choice = c),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _content(BuildContext context, Map<String, dynamic> j) =>
      switch (widget.kind) {
        ReportKind.ageing => _ageing(context, j),
        ReportKind.sales => _sales(context, j),
        ReportKind.collections => _collections(context, j),
        ReportKind.payables => _payables(context, j),
        ReportKind.statement => _statement(context, j),
      };

  List<Widget> _ageing(BuildContext context, Map<String, dynamic> j) {
    final l10n = AppLocalizations.of(context);
    final rows = _list(j['rows']);
    return [
      _Totals([
        (l10n.reportTotalOwed, _amount(j['total'])),
        (l10n.reportPastDue, _amount(j['overdue'])),
        ('0–30', _amount(j['days_0_30'])),
        ('31–60', _amount(j['days_31_60'])),
        ('61–90', _amount(j['days_61_90'])),
        ('90+', _amount(j['days_over_90'])),
      ]),
      _Note(l10n.reportAgeingNote),
      if (rows.isEmpty) _Message(l10n.reportNothing),
      for (final r in rows)
        _Row(
          title: r['name'] as String,
          subtitle: [
            for (final (label, key) in [
              ('0–30', 'days_0_30'),
              ('31–60', 'days_31_60'),
              ('61–90', 'days_61_90'),
              ('90+', 'days_over_90'),
            ])
              if (_amount(r[key]) > 0)
                '$label: ${Money.format(_amount(r[key]), compact: true)}',
            if (_amount(r['overdue']) > 0)
              l10n.reportPastDueAmount(
                Money.format(_amount(r['overdue']), compact: true),
              ),
          ].join(' · '),
          cents: _amount(r['total']),
          color: AppColors.debtRed,
          onTap: () => context.go('/customers/${r['customer_id']}'),
        ),
    ];
  }

  List<Widget> _sales(BuildContext context, Map<String, dynamic> j) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final products = _list(j['top_products']);
    final days = _list(j['daily']).where((d) => (d['count'] as int) > 0);
    return [
      _Totals([
        (l10n.reportSalesTotal(j['count'] as int), _amount(j['total'])),
        (l10n.methodCash, _amount(j['cash_total'])),
        (l10n.methodMpesa, _amount(j['mpesa_total'])),
        (l10n.methodBank, _amount(j['bank_total'])),
        (l10n.methodCredit, _amount(j['credit_total'])),
      ]),
      _Heading(l10n.reportTopProducts),
      if (products.isEmpty) _Message(l10n.reportNothing),
      for (final p in products)
        _Row(
          title:
              '${p['product_name']} × '
              '${Quantity.toWire(Quantity.parse(p['quantity'] as String))}',
          subtitle: l10n.reportSalesCount(p['count'] as int),
          cents: _amount(p['amount']),
        ),
      if (days.isNotEmpty) _Heading(l10n.reportByDay),
      for (final d in days.toList().reversed)
        _Row(
          title: ShopTime.date(_day(d['date']), locale),
          subtitle: l10n.reportSalesCount(d['count'] as int),
          cents: _amount(d['total']),
        ),
    ];
  }

  List<Widget> _collections(BuildContext context, Map<String, dynamic> j) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final staff = _list(j['staff']);
    final days = _list(j['daily']).where((d) => (d['count'] as int) > 0);
    return [
      _Totals([
        (
          l10n.reportCollected(j['payment_count'] as int),
          _amount(j['total_collected']),
        ),
        (l10n.methodCash, _amount(j['cash'])),
        (l10n.methodMpesa, _amount(j['mpesa'])),
        (l10n.methodBank, _amount(j['bank'])),
        (l10n.methodUnrecorded, _amount(j['unrecorded'])),
      ]),
      if (staff.isNotEmpty) _Heading(l10n.reportByStaff),
      for (final s in staff)
        _Row(
          title: s['name'] as String,
          subtitle: l10n.reportStaffLine(
            s['payments_count'] as int,
            s['sales_count'] as int,
            Money.format(_amount(s['sales_total']), compact: true),
          ),
          cents: _amount(s['payments_total']),
          color: AppColors.paymentGreen,
        ),
      if (days.isNotEmpty) _Heading(l10n.reportByDay),
      for (final d in days.toList().reversed)
        _Row(
          title: ShopTime.date(_day(d['date']), locale),
          subtitle: l10n.reportPaymentsCount(d['count'] as int),
          cents: _amount(d['amount']),
          color: AppColors.paymentGreen,
        ),
    ];
  }

  List<Widget> _payables(BuildContext context, Map<String, dynamic> j) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final rows = _list(j['rows']);
    return [
      _Totals([
        (l10n.reportTotalOwed, _amount(j['owed'])),
        (l10n.reportPastDue, _amount(j['overdue'])),
        (l10n.reportDueSoon, _amount(j['due_soon'])),
        (l10n.supplierPrepaid, _amount(j['prepayments_held'])),
      ]),
      if (rows.isEmpty) _Message(l10n.reportNothing),
      for (final r in rows)
        _Row(
          title: r['name'] as String,
          subtitle: [
            if (_amount(r['overdue']) > 0)
              l10n.reportPastDueAmount(
                Money.format(_amount(r['overdue']), compact: true),
              ),
            if (r['next_due'] != null)
              l10n.reportNextDue(ShopTime.date(_day(r['next_due']), locale)),
          ].join(' · '),
          cents: _amount(r['owed']),
          color: AppColors.debtRed,
          onTap: () => context.go('/suppliers/${r['supplier_id']}'),
        ),
    ];
  }

  List<Widget> _statement(BuildContext context, Map<String, dynamic> j) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final lines = _list(j['lines']);
    final period = j['period'] as Map<String, dynamic>;
    return [
      _Heading(
        '${j['customer_name']} · ${ShopTime.date(_day(period['from']), locale)}'
        ' – ${ShopTime.date(_day(period['to']), locale)}',
      ),
      _Totals([
        (l10n.reportOpening, _amount(j['opening_balance'])),
        (l10n.reportDebits, _amount(j['total_debits'])),
        (l10n.reportCredits, _amount(j['total_credits'])),
        (l10n.reportClosing, _amount(j['closing_balance'])),
      ]),
      if (lines.isEmpty) _Message(l10n.reportNothing),
      for (final line in lines)
        _Row(
          title: line['description'] as String,
          subtitle:
              '${ShopTime.date(_day(line['date']), locale)} · '
              '${l10n.reportBalanceAfter(Money.format(_amount(line['balance']), compact: true))}',
          cents: _amount(line['debit']) > 0
              ? _amount(line['debit'])
              : _amount(line['credit']),
          sign: _amount(line['debit']) > 0 ? '+' : '−',
          color: _amount(line['debit']) > 0
              ? AppColors.debtRed
              : AppColors.paymentGreen,
        ),
    ];
  }

  static List<Map<String, dynamic>> _list(Object? v) =>
      (v as List<dynamic>? ?? const []).cast<Map<String, dynamic>>();

  static int _amount(Object? v) => v == null ? 0 : Money.parse(v as String);

  /// A date the server sends as a day: its calendar day, as UTC midnight.
  static DateTime _day(Object? v) {
    final d = DateTime.parse(v! as String);
    return DateTime.utc(d.year, d.month, d.day);
  }
}

/// When the report was read, and whether this is the copy kept from then.
class _AsOf extends ConsumerWidget {
  final ReportResult result;

  const _AsOf(this.result);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final when = ref
        .watch(shopTimeProvider)
        .dateTime(result.asOf, Localizations.localeOf(context).toLanguageTag());
    return Container(
      width: double.infinity,
      color: result.isCached
          ? AppColors.primaryLight.withValues(alpha: 0.4)
          : null,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Text(
        result.isCached ? l10n.reportKeptCopy(when) : l10n.reportAsOf(when),
        style: theme.textTheme.bodyMedium,
      ),
    );
  }
}

class _Totals extends StatelessWidget {
  final List<(String, int)> items;

  const _Totals(this.items);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            children: [
              for (final (i, (label, cents)) in items.indexed)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          label,
                          style: i == 0
                              ? theme.textTheme.titleMedium
                              : theme.textTheme.bodyMedium,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        Money.format(cents, compact: true),
                        style: i == 0
                            ? theme.textTheme.titleMedium
                            : theme.textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  final String text;

  const _Heading(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.md,
      AppSpacing.md,
      AppSpacing.md,
      AppSpacing.xs,
    ),
    child: Text(text, style: Theme.of(context).textTheme.titleMedium),
  );
}

class _Note extends StatelessWidget {
  final String text;

  const _Note(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
    child: Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
    ),
  );
}

class _Row extends StatelessWidget {
  final String title;
  final String subtitle;
  final int cents;
  final String sign;
  final Color? color;
  final VoidCallback? onTap;

  const _Row({
    required this.title,
    required this.subtitle,
    required this.cents,
    this.sign = '',
    this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) => ListTile(
    onTap: onTap,
    title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
    subtitle: subtitle.isEmpty
        ? null
        : Text(subtitle, maxLines: 3, overflow: TextOverflow.ellipsis),
    trailing: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 140),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          '${sign.isEmpty ? '' : '$sign '}${Money.format(cents, compact: true)}',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(color: color),
        ),
      ),
    ),
  );
}

class _Message extends StatelessWidget {
  final String text;
  final VoidCallback? onRetry;

  const _Message(this.text, {this.onRetry});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        children: [
          Text(
            text,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          if (onRetry != null) ...[
            const SizedBox(height: AppSpacing.md),
            OutlinedButton(
              onPressed: onRetry,
              child: Text(l10n.updateTryAgain),
            ),
          ],
        ],
      ),
    );
  }
}
