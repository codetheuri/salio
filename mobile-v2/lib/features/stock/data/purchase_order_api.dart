import 'package:uuid/uuid.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/quantity/quantity.dart';

/// One product on a purchase order.
class OrderLine {
  final String productName;

  /// In thousandths, as every quantity.
  final int quantity;

  /// The stock note it came from, if any.
  final String? stockRequestId;

  const OrderLine({
    required this.productName,
    required this.quantity,
    this.stockRequestId,
  });

  factory OrderLine.fromJson(Map<String, dynamic> j) => OrderLine(
    productName: j['product_name'] as String,
    quantity: Quantity.parse(j['quantity'] as String),
    stockRequestId: j['stock_request_id'] as String?,
  );

  /// A line from a stock note names only the note: the server copies the
  /// product's name as it stands when the order is placed.
  Map<String, Object?> toJson() => {
    if (stockRequestId != null)
      'stock_request_id': stockRequestId
    else
      'product_name': productName.trim(),
    'quantity': Quantity.toWire(quantity),
  };
}

class PurchaseOrder {
  final String id;

  /// What the supplier quotes back: "PO-0007".
  final String reference;
  final String supplierName;
  final String? supplierPhone;
  final String? notes;
  final bool cancelled;

  /// The calendar day it was placed, as UTC midnight.
  final DateTime orderedOn;
  final List<OrderLine> lines;

  const PurchaseOrder({
    required this.id,
    required this.reference,
    required this.supplierName,
    this.supplierPhone,
    this.notes,
    required this.cancelled,
    required this.orderedOn,
    required this.lines,
  });

  factory PurchaseOrder.fromJson(Map<String, dynamic> j) {
    final day = DateTime.parse(j['ordered_on'] as String);
    return PurchaseOrder(
      id: j['id'] as String,
      reference: j['reference'] as String,
      supplierName: j['supplier_name'] as String,
      supplierPhone: j['supplier_phone'] as String?,
      notes: j['notes'] as String?,
      cancelled: j['status'] == 'cancelled',
      orderedOn: DateTime.utc(day.year, day.month, day.day),
      lines: [
        for (final l in (j['lines'] as List? ?? const []))
          OrderLine.fromJson(l as Map<String, dynamic>),
      ],
    );
  }
}

/// Purchase orders: placed, read and cancelled online only, because the
/// server numbers them and an order is an instruction to a supplier
/// (docs/10, §2.3). Owners place and cancel; everyone with `stock.read`
/// sees them.
class PurchaseOrderApi {
  final ApiClient api;

  PurchaseOrderApi(this.api);

  /// A new id for an order about to be placed. The screen keeps it while
  /// the user retries, so a retry after a lost answer finds the order the
  /// first attempt placed (B8) instead of placing a second.
  static String newId() => const Uuid().v7();

  Future<PurchaseOrder> place({
    required String id,
    required String supplierName,
    String supplierPhone = '',
    String notes = '',
    required List<OrderLine> lines,
  }) async {
    final data =
        await api.post('/purchase-orders', {
              'id': id,
              'supplier_name': supplierName.trim(),
              if (supplierPhone.trim().isNotEmpty)
                'supplier_phone': supplierPhone.trim(),
              if (notes.trim().isNotEmpty) 'notes': notes.trim(),
              'lines': [for (final l in lines) l.toJson()],
            })
            as Map<String, dynamic>;
    return PurchaseOrder.fromJson(data);
  }

  /// Newest first.
  Future<List<PurchaseOrder>> list() async {
    final data = await api.get('/purchase-orders') as List<dynamic>;
    return [
      for (final o in data) PurchaseOrder.fromJson(o as Map<String, dynamic>),
    ];
  }

  Future<PurchaseOrder> get(String id) async => PurchaseOrder.fromJson(
    await api.get('/purchase-orders/$id') as Map<String, dynamic>,
  );

  /// Cancels an order; its stock notes go back on the list to order. An
  /// order already cancelled, as by a retry whose first answer was lost,
  /// counts as done.
  Future<void> cancel(String id) async {
    try {
      await api.post('/purchase-orders/$id/cancel', null);
    } on ApiException catch (e) {
      if (e.kind != ApiFailure.conflict) {
        rethrow;
      }
      if (!(await get(id)).cancelled) rethrow;
    }
  }

  /// The order as a PDF, with the shop's letterhead, to send the supplier.
  Future<List<int>> pdf(String id) => api.getBytes('/purchase-orders/$id/pdf');
}
