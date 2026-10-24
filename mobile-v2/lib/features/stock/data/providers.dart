import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/database_provider.dart';
import '../../../core/network/api_provider.dart';
import '../../../core/session/session_controller.dart';
import '../../../core/time/clock_provider.dart';
import '../../../core/time/shop_time.dart';
import 'purchase_order_api.dart';
import 'stock_repository.dart';

final stockRepositoryProvider = Provider<StockRepository>(
  (ref) => StockRepository(
    ref.watch(databaseProvider),
    ref.watch(serverClockProvider),
    ref.watch(shopTimeProvider),
    ref.watch(sessionProvider).requireValue!.account.userId,
  ),
);

final purchaseOrderApiProvider = Provider<PurchaseOrderApi>(
  (ref) => PurchaseOrderApi(ref.watch(apiClientProvider)),
);

/// Stock notes not yet ordered: the draft order.
final toOrderProvider = StreamProvider<List<StockRequestRow>>(
  (ref) => ref.watch(stockRepositoryProvider).watchToOrder(),
);

final stockNoteProvider = StreamProvider.family<StockRequestRow?, String>(
  (ref, id) => ref.watch(stockRepositoryProvider).watchNote(id),
);

/// Purchase orders, read online. Refreshed by invalidating it after an
/// order is placed or cancelled, or by pulling the list down.
///
/// Never retried by itself: Riverpod would retry for about a minute and
/// report loading the whole time, so an owner with no signal would watch a
/// spinner instead of reading that orders need a connection. The screen
/// says so at once and offers Try again.
final purchaseOrdersProvider = FutureProvider<List<PurchaseOrder>>(
  (ref) => ref.watch(purchaseOrderApiProvider).list(),
  retry: _noRetry,
);

final purchaseOrderProvider = FutureProvider.family<PurchaseOrder, String>(
  (ref, id) => ref.watch(purchaseOrderApiProvider).get(id),
  retry: _noRetry,
);

Duration? _noRetry(int count, Object error) => null;
