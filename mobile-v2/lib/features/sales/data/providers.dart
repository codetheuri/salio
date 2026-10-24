import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_provider.dart';
import '../../../core/session/session_controller.dart';
import '../../../core/time/clock_provider.dart';
import '../../../core/time/shop_time.dart';
import 'sales_repository.dart';

final salesRepositoryProvider = Provider<SalesRepository>(
  (ref) => SalesRepository(
    ref.watch(databaseProvider),
    ref.watch(serverClockProvider),
    ref.watch(sessionProvider).requireValue!.account.userId,
  ),
);

/// How far back the sales list reaches: the last 30 days of the shop's
/// calendar. Older sales are in the reports (M5).
const salesListDays = 30;

final salesProvider = StreamProvider<List<SaleWithCustomer>>((ref) {
  final shop = ref.watch(shopTimeProvider);
  final today = ref.watch(shopTodayProvider);
  return ref
      .watch(salesRepositoryProvider)
      .watchSince(
        shop.startOf(today.subtract(const Duration(days: salesListDays - 1))),
      );
});

final saleProvider = StreamProvider.family<SaleWithCustomer?, String>(
  (ref, id) => ref.watch(salesRepositoryProvider).watchSale(id),
);
