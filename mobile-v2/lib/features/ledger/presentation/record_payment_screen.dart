import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/l10n/generated/app_localizations.dart';
import '../../../core/money/money.dart';
import '../../../core/sync/sync_controller.dart';
import '../../../core/widgets/form_page.dart';
import '../../customers/data/providers.dart';
import '../domain/payment_reference.dart';
import 'record_debt_screen.dart';

/// Records a payment on this phone: how much and how it came in. An M-Pesa
/// code is checked as it is typed, and is optional; a payment above what
/// is owed is kept as an advance, and the screen says so before saving.
class RecordPaymentScreen extends ConsumerStatefulWidget {
  final String customerId;

  const RecordPaymentScreen({super.key, required this.customerId});

  @override
  ConsumerState<RecordPaymentScreen> createState() =>
      _RecordPaymentScreenState();
}

class _RecordPaymentScreenState extends ConsumerState<RecordPaymentScreen> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _reference = TextEditingController();
  final _note = TextEditingController();
  var _method = PaymentMethod.cash;
  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    _note.dispose();
    super.dispose();
  }

  String _methodLabel(AppLocalizations l10n, PaymentMethod m) => switch (m) {
    PaymentMethod.cash => l10n.methodCash,
    PaymentMethod.mpesa => l10n.methodMpesa,
    PaymentMethod.bank => l10n.methodBank,
  };

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _saving = true);
    await ref
        .read(ledgerRepositoryProvider)
        .recordPayment(
          customerId: widget.customerId,
          amountCents: Money.parse(_amount.text),
          method: _method,
          reference: _method == PaymentMethod.cash ? '' : _reference.text,
          // The server needs a description on every entry; the method is
          // the plainest one when the user gives none.
          description: _note.text.trim().isEmpty
              ? _methodLabel(l10n, _method)
              : _note.text,
        );
    ref.read(syncProvider.notifier).requestSoon();
    if (mounted) context.go('/customers/${widget.customerId}');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final customer = ref.watch(customerProvider(widget.customerId)).value;
    final owed = customer?.balanceCents ?? 0;
    final paid = Money.tryParse(_amount.text) ?? 0;
    final extra = paid - (owed > 0 ? owed : 0);

    return FormPage(
      title: customer == null
          ? l10n.recordPayment
          : '${l10n.recordPayment}: ${customer.customer.name}',
      formKey: _form,
      actionLabel: l10n.save,
      onAction: _saving ? null : _save,
      fields: [
        AmountField(
          controller: _amount,
          label: l10n.paymentAmount,
          onChanged: (_) => setState(() {}),
          helperText: paid > 0 && extra > 0
              ? l10n.paymentAdvance(Money.format(extra, compact: true))
              : null,
        ),
        // Wraps to two rows at the largest text on a small phone.
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final m in PaymentMethod.values)
              ChoiceChip(
                label: Text(_methodLabel(l10n, m)),
                selected: _method == m,
                onSelected: (_) => setState(() {
                  _method = m;
                  _reference.clear();
                }),
              ),
          ],
        ),
        if (_method != PaymentMethod.cash)
          TextFormField(
            key: ValueKey(_method),
            controller: _reference,
            textCapitalization: _method == PaymentMethod.mpesa
                ? TextCapitalization.characters
                : TextCapitalization.none,
            inputFormatters: [
              if (_method == PaymentMethod.mpesa) ...[
                FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]')),
                LengthLimitingTextInputFormatter(10),
              ] else
                LengthLimitingTextInputFormatter(PaymentReference.maxLength),
            ],
            // Checked as it is typed once ten characters are in: a code with
            // one character wrong matches no SMS.
            autovalidateMode: AutovalidateMode.onUserInteraction,
            decoration: InputDecoration(
              labelText: _method == PaymentMethod.mpesa
                  ? l10n.mpesaCode
                  : l10n.bankReference,
              helperText: _method == PaymentMethod.mpesa
                  ? l10n.mpesaCodeHint
                  : null,
            ),
            validator: (v) =>
                switch (PaymentReference.check(_method, v ?? '').problem) {
                  ReferenceProblem.mpesaCode => l10n.mpesaCodeInvalid,
                  ReferenceProblem.tooLong => l10n.referenceTooLong,
                  _ => null,
                },
          ),
        TextFormField(
          controller: _note,
          textCapitalization: TextCapitalization.sentences,
          maxLength: 500,
          decoration: InputDecoration(labelText: l10n.paymentNote),
        ),
      ],
    );
  }
}
