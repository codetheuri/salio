import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_provider.dart';
import '../../../core/time/clock_provider.dart';
import '../../../core/time/shop_time.dart';
import '../../customers/data/providers.dart';
import 'home_repository.dart';

final homeRepositoryProvider = Provider<HomeRepository>(
  (ref) => HomeRepository(
    ref.watch(databaseProvider),
    ref.watch(customerRepositoryProvider),
  ),
);

/// The shop's figures, as the server's summary computes them.
final shopFiguresProvider = StreamProvider<ShopFigures>(
  (ref) => ref
      .watch(homeRepositoryProvider)
      .watchFigures(ref.watch(serverClockProvider).now()),
);

/// Money in since the shop's day began.
final todayMoneyProvider = StreamProvider<TodayMoney>((ref) {
  final shop = ref.watch(shopTimeProvider);
  return ref
      .watch(homeRepositoryProvider)
      .watchTodayMoney(shop.startOf(ref.watch(shopTodayProvider)));
});

/// Overdue and due today, largest first.
final todayListProvider = StreamProvider<List<TodayItem>>(
  (ref) => ref
      .watch(homeRepositoryProvider)
      .watchToday(ref.watch(shopTodayProvider)),
);
