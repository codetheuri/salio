import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/database_provider.dart';
import '../../../core/session/session_controller.dart';
import '../../../core/time/clock_provider.dart';
import 'supplier_repository.dart';

final supplierRepositoryProvider = Provider<SupplierRepository>(
  (ref) => SupplierRepository(
    ref.watch(databaseProvider),
    ref.watch(serverClockProvider),
    ref.watch(sessionProvider).requireValue!.account.userId,
  ),
);

/// The search typed above the supplier list, kept while a supplier is open.
final supplierSearchProvider = NotifierProvider<SupplierSearch, String>(
  SupplierSearch.new,
);

class SupplierSearch extends Notifier<String> {
  @override
  String build() => '';

  void set(String text) => state = text;
}

final suppliersProvider = StreamProvider<List<SupplierBalance>>(
  (ref) => ref
      .watch(supplierRepositoryProvider)
      .watchList(search: ref.watch(supplierSearchProvider)),
);

final supplierProvider = StreamProvider.family<SupplierBalance?, String>(
  (ref, id) => ref.watch(supplierRepositoryProvider).watch(id),
);

final supplierEntriesProvider =
    StreamProvider.family<List<SupplierEntryRow>, String>(
      (ref, id) => ref.watch(supplierRepositoryProvider).watchEntries(id),
    );

final supplierEntryProvider = StreamProvider.family<SupplierEntryRow?, String>(
  (ref, id) => ref.watch(supplierRepositoryProvider).watchEntry(id),
);
