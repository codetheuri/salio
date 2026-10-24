import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/time/server_clock.dart';

/// The reports the server renders (docs/10, §2.3), each also as a PDF.
enum ReportKind {
  ageing('/reports/ageing'),
  sales('/reports/sales'),
  collections('/reports/collections'),
  payables('/reports/payables'),
  statement('/reports/customers/{id}/statement');

  final String path;

  const ReportKind(this.path);

  /// Reports over a period of days: the rest are as of now.
  bool get hasPeriod =>
      this == sales || this == collections || this == statement;
}

/// One report, for one period (and one customer, for a statement). Equal
/// requests are one provider and one cached copy.
class ReportRequest {
  final ReportKind kind;

  /// Calendar days, inclusive, as UTC midnight; null lets the server choose
  /// (30 days, or 90 for a statement, ending today).
  final DateTime? from;
  final DateTime? to;
  final String? customerId;

  const ReportRequest(this.kind, {this.from, this.to, this.customerId});

  String get path => kind.path.replaceFirst('{id}', customerId ?? '');

  Map<String, Object?> get query => {
    if (from != null) 'from': _day(from!),
    if (to != null) 'to': _day(to!),
    if (kind == ReportKind.payables) 'within_days': 7,
  };

  /// The cache's key: the report and everything that changes its answer.
  String get key => [
    kind.name,
    ?customerId,
    if (from != null) _day(from!),
    if (to != null) _day(to!),
  ].join(':');

  static String _day(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  @override
  bool operator ==(Object other) => other is ReportRequest && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

/// A report's answer, fresh or the last copy kept.
class ReportResult {
  final Map<String, dynamic> data;

  /// When the server answered it.
  final DateTime asOf;

  /// Set when this is the kept copy because the server could not be
  /// reached now.
  final ApiException? offline;

  const ReportResult(this.data, this.asOf, {this.offline});

  bool get isCached => offline != null;
}

/// Reads reports online and keeps the last copy of each, so a report read
/// once stays readable without a connection, with the time it was read.
class ReportRepository {
  final ApiClient api;
  final AppDatabase db;
  final ServerClock clock;

  ReportRepository(this.api, this.db, this.clock);

  /// The report from the server, kept for later; without a connection, the
  /// copy kept last time. Anything else (no permission, a customer deleted)
  /// is not hidden behind an old copy.
  Future<ReportResult> load(ReportRequest request) async {
    try {
      final data =
          await api.get(request.path, query: request.query)
              as Map<String, dynamic>;
      final now = clock.now();
      await db
          .into(db.reportCache)
          .insertOnConflictUpdate(
            ReportCacheRow(
              key: request.key,
              body: jsonEncode(data),
              fetchedAt: now,
            ),
          );
      return ReportResult(data, now);
    } on ApiException catch (e) {
      if (e.kind != ApiFailure.offline && e.kind != ApiFailure.timeout) {
        rethrow;
      }
      final kept = await (db.select(
        db.reportCache,
      )..where((r) => r.key.equals(request.key))).getSingleOrNull();
      if (kept == null) rethrow;
      return ReportResult(
        jsonDecode(kept.body) as Map<String, dynamic>,
        kept.fetchedAt,
        offline: e,
      );
    }
  }

  /// The same report as a PDF, with the shop's letterhead.
  Future<List<int>> pdf(ReportRequest request) =>
      api.getBytes('${request.path}/pdf', query: request.query);

  /// Removes kept copies older than [age]: a report's period moves with
  /// the days, so old keys are never read again.
  Future<void> prune({Duration age = const Duration(days: 60)}) =>
      (db.delete(db.reportCache)..where(
            (r) => r.fetchedAt.isSmallerThanValue(clock.now().subtract(age)),
          ))
          .go();
}
