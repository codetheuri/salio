import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';

import '../../../core/database/database_provider.dart';
import '../../../core/session/session_controller.dart';
import '../../../core/time/clock_provider.dart';
import '../../ledger/data/ledger_repository.dart';
import 'customer_repository.dart';

final customerRepositoryProvider = Provider<CustomerRepository>(
  (ref) => CustomerRepository(
    ref.watch(databaseProvider),
    ref.watch(serverClockProvider),
    ref.watch(sessionProvider).requireValue!.account.userId,
  ),
);

final ledgerRepositoryProvider = Provider<LedgerRepository>(
  (ref) => LedgerRepository(
    ref.watch(databaseProvider),
    ref.watch(serverClockProvider),
    ref.watch(sessionProvider).requireValue!.account.userId,
  ),
);

final customersProvider = StreamProvider<List<CustomerBalance>>(
  (ref) => ref.watch(customerRepositoryProvider).watchAll(),
);

final customerProvider = StreamProvider.family<CustomerBalance?, String>(
  (ref, id) => ref.watch(customerRepositoryProvider).watch(id),
);

final entriesProvider = StreamProvider.family<List<LedgerEntryRow>, String>(
  (ref, customerId) => ref.watch(ledgerRepositoryProvider).watchFor(customerId),
);
