import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/l10n/generated/app_localizations.dart';
import '../../../core/money/money.dart';
import '../../../core/sync/sync_controller.dart';
import '../../../core/time/shop_time.dart';
import '../../../core/widgets/form_page.dart';
import '../../ledger/domain/payment_reference.dart';
import '../../ledger/presentation/widgets/money_fields.dart';
import '../data/providers.dart';

/// Records a bill from a supplier (goods received on credit, with an
/// optional day it is due) or a payment to one (with how it was paid).
/// The description is required, as on the server: "Invoice 4471: 20 x DAP".
class SupplierEntryFormScreen extends ConsumerStatefulWidget {
  final String supplierId;
  final bool payment;

  const SupplierEntryFormScreen({
    super.key,
    required this.supplierId,
    required this.payment,
  });

  @override
  ConsumerState<SupplierEntryFormScreen> createState() =>
      _SupplierEntryFormState();
}

class _SupplierEntryFormState extends ConsumerState<SupplierEntryFormScreen> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _description = TextEditingController();
  final _reference = TextEditingController();
  var _method = PaymentMethod.cash;
  DateTime? _due;
  var _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    _description.dispose();
    _reference.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    final repo = ref.read(supplierRepositoryProvider);
    final cents = Money.parse(_amount.text);
    if (widget.payment) {
      await repo.recordPayment(
        supplierId: widget.supplierId,
        amountCents: cents,
        method: _method,
        reference: _method == PaymentMethod.cash ? '' : _reference.text,
        description: _description.text,
      );
    } else {
      await repo.recordBill(
        supplierId: widget.supplierId,
        amountCents: cents,
        description: _description.text,
        dueDate: _due,
      );
    }
    ref.read(syncProvider.notifier).requestSoon();
    if (mounted) context.go('/suppliers/${widget.supplierId}');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final supplier = ref.watch(supplierProvider(widget.supplierId)).value;
    final title = widget.payment
        ? l10n.supplierRecordPayment
        : l10n.supplierRecordBill;
    return FormPage(
      title: supplier == null ? title : '$title: ${supplier.supplier.name}',
      formKey: _form,
      actionLabel: l10n.save,
      onAction: _saving ? null : _save,
      fields: [
        AmountField(
          controller: _amount,
          label: widget.payment ? l10n.paymentAmount : l10n.debtAmount,
        ),
        TextFormField(
          controller: _description,
          textCapitalization: TextCapitalization.sentences,
          maxLength: 500,
          decoration: InputDecoration(
            labelText: l10n.entryDescription,
            hintText: widget.payment
                ? l10n.supplierPaymentHint
                : l10n.supplierBillHint,
          ),
          validator: (v) =>
              v == null || v.trim().isEmpty ? l10n.fieldRequired : null,
        ),
        if (widget.payment) ...[
          MethodChips(
            values: PaymentMethod.values,
            selected: _method,
            label: (m) => paymentMethodLabel(l10n, m),
            onSelected: (m) => setState(() {
              _method = m;
              _reference.clear();
            }),
          ),
          if (_method != PaymentMethod.cash)
            ReferenceField(method: _method, controller: _reference),
        ] else
          DueDateTile(
            value: _due,
            today: ref.watch(shopTodayProvider),
            onChanged: (d) => setState(() => _due = d),
          ),
      ],
    );
  }
}
