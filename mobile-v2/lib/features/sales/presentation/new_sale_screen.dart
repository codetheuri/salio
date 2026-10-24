import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/l10n/generated/app_localizations.dart';
import '../../../app/theme/app_colors.dart';
import '../../../core/money/money.dart';
import '../../../core/quantity/quantity.dart';
import '../../../core/sync/sync_controller.dart';
import '../../../core/time/shop_time.dart';
import '../../../core/widgets/form_page.dart';
import '../../../core/widgets/suggest_field.dart';
import '../../customers/data/providers.dart';
import '../../ledger/domain/payment_reference.dart';
import '../../ledger/presentation/widgets/money_fields.dart';
import '../data/providers.dart';
import '../data/sales_repository.dart';
import 'customer_picker.dart';
import 'sales_screen.dart';

/// Records a sale on this phone: what, how many, the total, and how it was
/// paid. Saved at once, offline or not.
///
/// A credit sale needs a customer and puts the amount on their account at
/// once, warning first when that passes their credit limit. Opened from a
/// customer ([customerId]), it starts as a credit sale for them and goes
/// back to them.
class NewSaleScreen extends ConsumerStatefulWidget {
  final String? customerId;

  const NewSaleScreen({super.key, this.customerId});

  @override
  ConsumerState<NewSaleScreen> createState() => _NewSaleScreenState();
}

class _NewSaleScreenState extends ConsumerState<NewSaleScreen> {
  final _form = GlobalKey<FormState>();
  final _product = TextEditingController();
  final _quantity = TextEditingController(text: '1');
  final _amount = TextEditingController();
  final _reference = TextEditingController();
  final _notes = TextEditingController();
  late var _method = widget.customerId == null
      ? SaleMethod.cash
      : SaleMethod.credit;
  late String? _customerId = widget.customerId;
  DateTime? _due;
  var _products = const <String>[];
  var _needsCustomer = false;
  var _saving = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadProducts());
  }

  Future<void> _loadProducts() async {
    final products = await ref.read(salesRepositoryProvider).recentProducts();
    if (mounted) setState(() => _products = products);
  }

  @override
  void dispose() {
    for (final c in [_product, _quantity, _amount, _reference, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _chooseCustomer() async {
    final id = await pickCustomer(context);
    if (id != null && mounted) {
      setState(() {
        _customerId = id;
        _needsCustomer = false;
      });
    }
  }

  Future<void> _save() async {
    final credit = _method == SaleMethod.credit;
    final valid = _form.currentState!.validate();
    setState(() => _needsCustomer = credit && _customerId == null);
    if (!valid || _needsCustomer) return;

    final cents = Money.parse(_amount.text);
    final customerId = _customerId;
    if (credit && customerId != null) {
      final customer = await ref
          .read(customerRepositoryProvider)
          .watch(customerId)
          .first;
      if (!mounted) return;
      if (customer != null &&
          customer.wouldExceedLimit(cents) &&
          !await confirmOverLimit(
            context,
            name: customer.customer.name,
            newBalanceCents: customer.balanceCents + cents,
            limitCents: customer.creditLimitCents!,
          )) {
        return;
      }
    }
    if (!mounted) return;
    setState(() => _saving = true);
    await ref
        .read(salesRepositoryProvider)
        .record(
          productName: _product.text,
          quantity: Quantity.parse(_quantity.text),
          amountCents: cents,
          method: _method,
          // A cash or M-Pesa sale may name the customer too; a credit sale
          // must.
          customerId: customerId,
          reference: _method.payment == null ? '' : _reference.text,
          dueDate: credit ? _due : null,
          notes: _notes.text,
        );
    ref.read(syncProvider.notifier).requestSoon();
    if (!mounted) return;
    context.go(
      widget.customerId == null ? '/sales' : '/customers/${widget.customerId}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final customerId = _customerId;
    final customer = customerId == null
        ? null
        : ref.watch(customerProvider(customerId)).value;
    final credit = _method == SaleMethod.credit;
    final payment = _method.payment;

    return FormPage(
      title: l10n.saleNew,
      formKey: _form,
      actionLabel: l10n.save,
      onAction: _saving ? null : _save,
      fields: [
        SuggestField(
          controller: _product,
          suggestions: _products,
          label: l10n.saleProduct,
          autofocus: true,
          maxLength: 255,
          validator: (v) =>
              v == null || v.trim().isEmpty ? l10n.fieldRequired : null,
        ),
        TextFormField(
          controller: _quantity,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
          ],
          decoration: InputDecoration(
            labelText: l10n.saleQuantity,
            helperText: l10n.saleQuantityHint,
          ),
          validator: (v) {
            try {
              return Quantity.parse(v ?? '') > 0 ? null : l10n.amountPositive;
            } on FormatException {
              return l10n.saleQuantityInvalid;
            }
          },
        ),
        AmountField(
          controller: _amount,
          label: l10n.saleAmount,
          autofocus: false,
        ),
        MethodChips(
          values: SaleMethod.values,
          selected: _method,
          label: (m) => saleMethodLabel(l10n, m),
          onSelected: (m) => setState(() {
            _method = m;
            _reference.clear();
            _needsCustomer = false;
          }),
        ),
        if (payment != null && payment != PaymentMethod.cash)
          ReferenceField(method: payment, controller: _reference),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.person_outline),
          title: Text(
            customer?.customer.name ??
                (credit ? l10n.saleChooseCustomer : l10n.saleCustomerOptional),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: _needsCustomer
              ? Text(
                  l10n.saleCreditNeedsCustomer,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.error,
                  ),
                )
              : credit
              ? Text(l10n.saleCreditHint)
              : null,
          trailing: customerId != null && widget.customerId == null
              ? IconButton(
                  tooltip: l10n.saleCustomerClear,
                  icon: const Icon(Icons.clear),
                  onPressed: () => setState(() => _customerId = null),
                )
              : const Icon(Icons.chevron_right),
          onTap: widget.customerId == null
              ? () => unawaited(_chooseCustomer())
              : null,
        ),
        if (credit)
          DueDateTile(
            value: _due,
            today: ref.watch(shopTodayProvider),
            onChanged: (d) => setState(() => _due = d),
          ),
        TextFormField(
          controller: _notes,
          textCapitalization: TextCapitalization.sentences,
          maxLength: 500,
          decoration: InputDecoration(labelText: l10n.paymentNote),
        ),
      ],
    );
  }
}
