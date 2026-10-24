import 'package:uuid/uuid.dart';

import '../../../core/quantity/quantity.dart';

/// The debt a credit sale puts on the customer's account.
///
/// The phone makes it itself, offline, so the balance moves at once, and
/// never sends it: the server makes its own from the sale. Both must be
/// the same row, so the id is derived from the sale's (server-v2's
/// `domain.SaleDebtID`: UUIDv5 over the sale id's text) and the words are
/// the server's (`sales.DebtDescription`). testdata/shared/sale_debt.json
/// pins both sides.
abstract final class SaleDebt {
  static const namespace = '7b3e5c1a-0d4f-4e8a-9a6b-2f1c8d5e4a90';

  static String idFor(String saleId) =>
      const Uuid().v5(namespace, saleId.toLowerCase());

  static String description(String product, int quantity) =>
      'Sale: ${product.trim()} x ${Quantity.toWire(quantity)}';
}
