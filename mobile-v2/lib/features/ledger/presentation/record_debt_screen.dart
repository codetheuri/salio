import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/l10n/generated/app_localizations.dart';
import '../../../core/money/money.dart';
import '../../../core/sync/sync_controller.dart';
import '../../../core/time/shop_time.dart';
import '../../../core/widgets/form_page.dart';
import '../../customers/data/providers.dart';
import 'widgets/money_fields.dart';

/// Records a debt on this phone: saved at once, offline or not, and sent
/// with the next sync. The description is required (a field-test request),
/// the due date is optional, and going over the credit limit asks first.
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
  DateTime? _due;
  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final cents = Money.parse(_amount.text);
    final customer = ref.read(customerProvider(widget.customerId)).value;
    // A warning, not a rule: the shop knows its customers. The server
    // records it either way.
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
    if (!mounted) return;
    setState(() => _saving = true);
    await ref
        .read(ledgerRepositoryProvider)
        .recordDebt(
          customerId: widget.customerId,
          amountCents: cents,
          description: _description.text,
          dueDate: _due,
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
        AmountField(controller: _amount, label: l10n.debtAmount),
        TextFormField(
          controller: _description,
          textCapitalization: TextCapitalization.sentences,
          maxLength: 500,
          decoration: InputDecoration(labelText: l10n.debtDescription),
          validator: (v) =>
              v == null || v.trim().isEmpty ? l10n.fieldRequired : null,
        ),
        DueDateTile(
          value: _due,
          today: ref.watch(shopTodayProvider),
          onChanged: (d) => setState(() => _due = d),
        ),
      ],
    );
  }
}
