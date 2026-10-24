import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_provider.dart';
import 'sync_issue_repository.dart';

final syncIssueRepositoryProvider = Provider<SyncIssueRepository>(
  (ref) => SyncIssueRepository(ref.watch(databaseProvider)),
);

final syncIssuesProvider = StreamProvider<List<SyncIssueView>>(
  (ref) => ref.watch(syncIssueRepositoryProvider).watchAll(),
);

final syncIssueCountProvider = StreamProvider<int>(
  (ref) => ref.watch(syncIssueRepositoryProvider).watchCount(),
);
