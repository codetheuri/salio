import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/l10n/generated/app_localizations.dart';
import '../../../core/money/money.dart';
import '../../../core/sync/sync_controller.dart';
import '../../../core/time/shop_time.dart';
import '../../../core/widgets/form_page.dart';
import '../../customers/data/providers.dart';

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

  Future<void> _pickDue() async {
    final today = ref.read(shopTodayProvider);
    final picked = await showDatePicker(
      context: context,
      initialDate: _due ?? today.add(const Duration(days: 7)),
      firstDate: today,
      lastDate: today.add(const Duration(days: 366)),
    );
    if (picked != null && mounted) setState(() => _due = picked);
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final cents = Money.parse(_amount.text);
    final customer = ref.read(customerProvider(widget.customerId)).value;
    // A warning, not a rule: the shop knows its customers. The server
    // records it either way.
    if (customer != null && customer.wouldExceedLimit(cents)) {
      final l10n = AppLocalizations.of(context);
      final go = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          content: Text(
            l10n.limitWarning(
              customer.customer.name,
              Money.format(customer.balanceCents + cents, compact: true),
              Money.format(customer.creditLimitCents!, compact: true),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l10n.recordAnyway),
            ),
          ],
        ),
      );
      if (go != true || !mounted) return;
    }
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
    final locale = Localizations.localeOf(context).toLanguageTag();
    final name = ref.watch(customerProvider(widget.customerId)).value;
    final due = _due;
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
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.event_outlined),
          title: Text(l10n.dueDate),
          subtitle: Text(
            due == null ? l10n.dueDateNone : ShopTime.date(due, locale),
          ),
          onTap: () => unawaited(_pickDue()),
          trailing: due == null
              ? null
              : IconButton(
                  tooltip: l10n.dueDateClear,
                  icon: const Icon(Icons.clear),
                  onPressed: () => setState(() => _due = null),
                ),
        ),
      ],
    );
  }
}

/// An amount in shillings: digits and one decimal point, above zero, at
/// most two decimals, as the server reads money.
class AmountField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? helperText;
  final ValueChanged<String>? onChanged;

  /// Empty is accepted, for amounts that may be left out.
  final bool optional;

  const AmountField({
    super.key,
    required this.controller,
    required this.label,
    this.helperText,
    this.onChanged,
    this.optional = false,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return TextFormField(
      controller: controller,
      autofocus: true,
      onChanged: onChanged,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
      decoration: InputDecoration(
        labelText: label,
        // The currency in the box, so the empty field reads as an amount.
        prefixText: 'KES ',
        helperText: helperText,
        helperMaxLines: 3,
      ),
      validator: (v) {
        if (optional && (v ?? '').trim().isEmpty) return null;
        final cents = Money.tryParse(v ?? '');
        if (cents == null) return l10n.amountInvalid;
        if (cents <= 0) return l10n.amountPositive;
        return null;
      },
    );
  }
}
