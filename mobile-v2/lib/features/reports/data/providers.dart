import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_provider.dart';
import '../../../core/network/api_provider.dart';
import '../../../core/time/clock_provider.dart';
import 'report_repository.dart';

final reportRepositoryProvider = Provider<ReportRepository>(
  (ref) => ReportRepository(
    ref.watch(apiClientProvider),
    ref.watch(databaseProvider),
    ref.watch(serverClockProvider),
  ),
);

/// A report, fresh or the kept copy. Never retried by itself: offline it
/// answers at once with the kept copy or the failure, instead of a minute
/// of "loading" (see purchaseOrdersProvider).
final reportProvider = FutureProvider.family<ReportResult, ReportRequest>(
  (ref, request) => ref.watch(reportRepositoryProvider).load(request),
  retry: (_, _) => null,
);
