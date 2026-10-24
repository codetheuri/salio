import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/l10n/generated/app_localizations.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../core/database/app_database.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/phone/phone.dart';
import '../../../core/quantity/quantity.dart';
import '../../../core/session/current_user.dart';
import '../../../core/session/permissions.dart';
import '../../../core/widgets/failure_text.dart';
import '../../../core/widgets/form_page.dart';
import '../../../core/widgets/suggest_field.dart';
import '../../suppliers/data/providers.dart';
import '../../suppliers/data/supplier_repository.dart';
import '../data/providers.dart';
import '../data/purchase_order_api.dart';

/// Places a purchase order with a supplier (owners), online: the server
/// numbers it and keeps it, and the PDF goes to the supplier.
///
/// Every product needs a quantity: that is where a note that something ran
/// out becomes an order anyone can fill. The order's id is made once and
/// kept while the user retries, so a retry after a lost answer finds the
/// order already placed instead of placing a second one (B8).
class PlaceOrderScreen extends ConsumerStatefulWidget {
  const PlaceOrderScreen({super.key});

  @override
  ConsumerState<PlaceOrderScreen> createState() => _PlaceOrderScreenState();
}

class _Extra {
  final product = TextEditingController();
  final quantity = TextEditingController();

  void dispose() {
    product.dispose();
    quantity.dispose();
  }
}

class _PlaceOrderScreenState extends ConsumerState<PlaceOrderScreen> {
  final _form = GlobalKey<FormState>();
  final _supplier = TextEditingController();
  final _supplierPhone = TextEditingController();
  final _notes = TextEditingController();

  /// Quantities typed for stock notes, by note id; a note left out is not
  /// on this order.
  final _quantities = <String, TextEditingController>{};
  final _included = <String>{};
  final _extras = <_Extra>[];
  final _orderId = PurchaseOrderApi.newId();
  var _seenNotes = <String>{};
  String? _error;
  var _placing = false;

  @override
  void dispose() {
    for (final c in [
      _supplier,
      _supplierPhone,
      _notes,
      ..._quantities.values,
    ]) {
      c.dispose();
    }
    for (final e in _extras) {
      e.dispose();
    }
    super.dispose();
  }

  /// New notes arriving (a sync, another phone) start included.
  void _take(List<StockRequestRow> notes) {
    for (final n in notes) {
      _quantities.putIfAbsent(n.id, TextEditingController.new);
      if (!_seenNotes.contains(n.id)) _included.add(n.id);
    }
    _seenNotes = {for (final n in notes) n.id};
    _included.retainAll(_seenNotes);
  }

  String? _quantityError(AppLocalizations l10n, String? v) {
    try {
      return Quantity.parse(v ?? '') > 0 ? null : l10n.orderQuantityRequired;
    } on FormatException {
      return l10n.orderQuantityRequired;
    }
  }

  Future<void> _place(List<StockRequestRow> notes) async {
    final l10n = AppLocalizations.of(context);
    setState(() => _error = null);
    if (!_form.currentState!.validate()) return;
    final lines = [
      for (final n in notes)
        if (_included.contains(n.id))
          OrderLine(
            productName: n.productName,
            quantity: Quantity.parse(_quantities[n.id]!.text),
            stockRequestId: n.id,
          ),
      for (final e in _extras)
        OrderLine(
          productName: e.product.text,
          quantity: Quantity.parse(e.quantity.text),
        ),
    ];
    if (lines.isEmpty) {
      setState(() => _error = l10n.orderNoProducts);
      return;
    }
    setState(() => _placing = true);
    try {
      final order = await ref
          .read(purchaseOrderApiProvider)
          .place(
            id: _orderId,
            supplierName: _supplier.text,
            supplierPhone: _supplierPhone.text,
            notes: _notes.text,
            lines: lines,
          );
      ref.invalidate(purchaseOrdersProvider);
      if (mounted) context.go('/stock/orders/${order.id}');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _placing = false;
        _error = describeFailure(l10n, e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final notes = ref.watch(toOrderProvider).value ?? const [];
    _take(notes);
    final List<SupplierBalance> suppliers =
        ref.watch(currentUserProvider).can(Permission.suppliersRead)
        ? ref.watch(suppliersProvider).value ?? const []
        : const [];
    final error = _error;

    return FormPage(
      title: l10n.orderPlace,
      formKey: _form,
      actionLabel: _placing ? l10n.orderPlacing : l10n.orderPlace,
      onAction: _placing ? null : () => unawaited(_place(notes)),
      fields: [
        Text(l10n.orderNeedsConnection, style: theme.textTheme.bodyMedium),
        SuggestField(
          controller: _supplier,
          suggestions: [for (final s in suppliers) s.supplier.name],
          label: l10n.orderSupplier,
          textCapitalization: TextCapitalization.words,
          maxLength: 255,
          validator: (v) =>
              v == null || v.trim().isEmpty ? l10n.fieldRequired : null,
          // A supplier already on the books brings their phone along.
          onSelected: (name) {
            final phone = suppliers
                .where((s) => s.supplier.name == name)
                .firstOrNull
                ?.supplier
                .phone;
            if (phone != null) _supplierPhone.text = Phone.display(phone);
          },
        ),
        TextFormField(
          controller: _supplierPhone,
          keyboardType: TextInputType.phone,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ()-]')),
          ],
          decoration: InputDecoration(labelText: l10n.orderSupplierPhone),
        ),
        Text(l10n.orderProductsTitle, style: theme.textTheme.titleMedium),
        if (notes.isEmpty && _extras.isEmpty)
          Text(l10n.orderNoNotes, style: theme.textTheme.bodyMedium),
        for (final n in notes)
          _LineRow(
            included: _included.contains(n.id),
            onIncluded: (v) => setState(
              () => v ? _included.add(n.id) : _included.remove(n.id),
            ),
            product: Text(
              n.productName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyLarge,
            ),
            quantity: TextFormField(
              controller: _quantities[n.id],
              enabled: _included.contains(n.id),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              decoration: InputDecoration(labelText: l10n.saleQuantity),
              validator: (v) =>
                  _included.contains(n.id) ? _quantityError(l10n, v) : null,
            ),
          ),
        for (final (i, e) in _extras.indexed)
          _LineRow(
            onRemove: () => setState(() => _extras.removeAt(i).dispose()),
            product: TextFormField(
              controller: e.product,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(labelText: l10n.saleProduct),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? l10n.fieldRequired : null,
            ),
            quantity: TextFormField(
              controller: e.quantity,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              decoration: InputDecoration(labelText: l10n.saleQuantity),
              validator: (v) => _quantityError(l10n, v),
            ),
          ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: () => setState(() => _extras.add(_Extra())),
            icon: const Icon(Icons.add),
            label: Text(l10n.orderAddProduct),
          ),
        ),
        TextFormField(
          controller: _notes,
          textCapitalization: TextCapitalization.sentences,
          maxLength: 1000,
          minLines: 1,
          maxLines: 4,
          decoration: InputDecoration(labelText: l10n.paymentNote),
        ),
        if (error != null)
          Text(
            error,
            style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.error),
          ),
      ],
    );
  }
}

/// One product on the order: its name and its quantity side by side, or
/// one above the other when the text is large or the phone narrow.
class _LineRow extends StatelessWidget {
  final Widget product;
  final Widget quantity;
  final bool? included;
  final ValueChanged<bool>? onIncluded;
  final VoidCallback? onRemove;

  const _LineRow({
    required this.product,
    required this.quantity,
    this.included,
    this.onIncluded,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final leading = onIncluded != null
        ? Checkbox(
            value: included ?? false,
            onChanged: (v) => onIncluded!(v ?? false),
          )
        : IconButton(
            tooltip: l10n.orderRemoveProduct,
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: onRemove,
          );
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow =
            constraints.maxWidth < 420 ||
            MediaQuery.textScalerOf(context).scale(1) > 1.2;
        final fields = narrow
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  product,
                  const SizedBox(height: AppSpacing.xs),
                  quantity,
                ],
              )
            : Row(
                children: [
                  Expanded(flex: 3, child: product),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(flex: 2, child: quantity),
                ],
              );
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            leading,
            const SizedBox(width: AppSpacing.xs),
            Expanded(child: fields),
          ],
        );
      },
    );
  }
}
