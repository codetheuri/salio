import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/l10n/generated/app_localizations.dart';
import '../../../core/money/money.dart';
import '../../../core/sync/sync_controller.dart';
import '../../../core/widgets/form_page.dart';
import '../../customers/data/providers.dart';

/// Records a debt on this phone. It is saved at once, offline or not, and
/// sent with the next sync. Due dates and the credit-limit warning come in
/// M3.
class RecordDebtScreen extends ConsumerStatefulWidget {
  final String customerId;

  const RecordDebtScreen({super.key, required this.customerId});

  @override
  ConsumerState<RecordDebtScreen> createState() => _RecordDebtScreenState();
}

class _RecordDebtScreenState extends ConsumerState<RecordDebtScreen> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _description = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    await ref
        .read(ledgerRepositoryProvider)
        .recordDebt(
          customerId: widget.customerId,
          amountCents: Money.parse(_amount.text),
          description: _description.text,
        );
    ref.read(syncProvider.notifier).requestSoon();
    if (mounted) context.go('/customers/${widget.customerId}');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final name = ref.watch(customerProvider(widget.customerId)).value;
    return FormPage(
      title: name == null
          ? l10n.recordDebt
          : '${l10n.recordDebt}: ${name.customer.name}',
      formKey: _form,
      actionLabel: l10n.save,
      onAction: _saving ? null : _save,
      fields: [
        TextFormField(
          controller: _amount,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
          ],
          decoration: InputDecoration(labelText: l10n.debtAmount),
          validator: (v) {
            final cents = Money.tryParse(v ?? '');
            if (cents == null) return l10n.amountInvalid;
            if (cents <= 0) return l10n.amountPositive;
            return null;
          },
        ),
        TextFormField(
          controller: _description,
          textCapitalization: TextCapitalization.sentences,
          maxLength: 500,
          decoration: InputDecoration(labelText: l10n.debtDescription),
          validator: (v) =>
              v == null || v.trim().isEmpty ? l10n.fieldRequired : null,
        ),
      ],
    );
  }
}
