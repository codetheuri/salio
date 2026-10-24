import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/database_provider.dart';
import '../../../core/session/session_controller.dart';
import '../../../core/time/clock_provider.dart';
import '../../../core/time/shop_time.dart';
import '../../ledger/data/ledger_repository.dart';
import '../../team/data/staff_repository.dart';
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

final staffRepositoryProvider = Provider<StaffRepository>(
  (ref) => StaffRepository(ref.watch(databaseProvider)),
);

/// What the customer list is showing: the search text and the filter. Kept
/// while the user opens a customer and comes back.
class CustomerQuery {
  final String search;
  final CustomerFilter filter;

  const CustomerQuery({this.search = '', this.filter = CustomerFilter.all});
}

final customerQueryProvider =
    NotifierProvider<CustomerQueryController, CustomerQuery>(
      CustomerQueryController.new,
    );

class CustomerQueryController extends Notifier<CustomerQuery> {
  @override
  CustomerQuery build() => const CustomerQuery();

  void search(String text) =>
      state = CustomerQuery(search: text, filter: state.filter);

  void filter(CustomerFilter filter) =>
      state = CustomerQuery(search: state.search, filter: filter);
}

final customersProvider = StreamProvider<List<CustomerBalance>>((ref) {
  final query = ref.watch(customerQueryProvider);
  return ref
      .watch(customerRepositoryProvider)
      .watchList(
        today: ref.watch(shopTodayProvider),
        search: query.search,
        filter: query.filter,
      );
});

final customerProvider = StreamProvider.family<CustomerBalance?, String>(
  (ref, id) => ref
      .watch(customerRepositoryProvider)
      .watch(id, today: ref.watch(shopTodayProvider)),
);

final entriesProvider = StreamProvider.family<List<LedgerEntryRow>, String>(
  (ref, customerId) => ref.watch(ledgerRepositoryProvider).watchFor(customerId),
);

final entryProvider = StreamProvider.family<LedgerEntryRow?, String>(
  (ref, id) => ref.watch(ledgerRepositoryProvider).watchEntry(id),
);

/// Who recorded what: names by user id, from the cached team list.
final staffNamesProvider = StreamProvider<Map<String, String>>(
  (ref) => ref.watch(staffRepositoryProvider).watchNames(),
);
