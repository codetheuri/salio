import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/l10n/generated/app_localizations.dart';
import '../../../../core/money/money.dart';
import '../../../../core/time/shop_time.dart';
import '../../domain/payment_reference.dart';

/// Form pieces every money screen shares: debts, payments, sales and
/// supplier bills ask for amounts, dates and references the same way.

/// An amount in shillings: digits and one decimal point, above zero, at
/// most two decimals, as the server reads money.
class AmountField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? helperText;
  final ValueChanged<String>? onChanged;

  /// Empty is accepted, for amounts that may be left out.
  final bool optional;

  /// On for screens where the amount is the first thing typed.
  final bool autofocus;

  const AmountField({
    super.key,
    required this.controller,
    required this.label,
    this.helperText,
    this.onChanged,
    this.optional = false,
    this.autofocus = true,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return TextFormField(
      controller: controller,
      autofocus: autofocus,
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

/// An optional calendar day something is to be paid by, from [today] up
/// to a year ahead, held as UTC midnight.
class DueDateTile extends StatelessWidget {
  final DateTime? value;
  final DateTime today;
  final ValueChanged<DateTime?> onChanged;

  const DueDateTile({
    super.key,
    required this.value,
    required this.today,
    required this.onChanged,
  });

  Future<void> _pick(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: value ?? today.add(const Duration(days: 7)),
      firstDate: today,
      lastDate: today.add(const Duration(days: 366)),
    );
    if (picked != null) {
      onChanged(DateTime.utc(picked.year, picked.month, picked.day));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final due = value;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.event_outlined),
      title: Text(l10n.dueDate),
      subtitle: Text(
        due == null ? l10n.dueDateNone : ShopTime.date(due, locale),
      ),
      onTap: () => unawaited(_pick(context)),
      trailing: due == null
          ? null
          : IconButton(
              tooltip: l10n.dueDateClear,
              icon: const Icon(Icons.clear),
              onPressed: () => onChanged(null),
            ),
    );
  }
}

/// The M-Pesa code or bank reference of money that moved, checked as it
/// is typed by the server's rule: a code with one character wrong matches
/// no SMS. Nothing to show for cash.
class ReferenceField extends StatelessWidget {
  final PaymentMethod method;
  final TextEditingController controller;

  const ReferenceField({
    super.key,
    required this.method,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final mpesa = method == PaymentMethod.mpesa;
    return TextFormField(
      key: ValueKey(method),
      controller: controller,
      textCapitalization: mpesa
          ? TextCapitalization.characters
          : TextCapitalization.none,
      inputFormatters: [
        if (mpesa) ...[
          FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]')),
          LengthLimitingTextInputFormatter(10),
        ] else
          LengthLimitingTextInputFormatter(PaymentReference.maxLength),
      ],
      autovalidateMode: AutovalidateMode.onUserInteraction,
      decoration: InputDecoration(
        labelText: mpesa ? l10n.mpesaCode : l10n.bankReference,
        helperText: mpesa ? l10n.mpesaCodeHint : null,
      ),
      validator: (v) =>
          switch (PaymentReference.check(method, v ?? '').problem) {
            ReferenceProblem.mpesaCode => l10n.mpesaCodeInvalid,
            ReferenceProblem.tooLong => l10n.referenceTooLong,
            _ => null,
          },
    );
  }
}

/// Choice chips for how money moved. They wrap to two rows at the largest
/// text on a small phone.
class MethodChips<T> extends StatelessWidget {
  final List<T> values;
  final T selected;
  final String Function(T) label;
  final ValueChanged<T> onSelected;

  const MethodChips({
    super.key,
    required this.values,
    required this.selected,
    required this.label,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final m in values)
        ChoiceChip(
          label: Text(label(m)),
          selected: selected == m,
          onSelected: (_) => onSelected(m),
        ),
    ],
  );
}

String paymentMethodLabel(AppLocalizations l10n, PaymentMethod m) =>
    switch (m) {
      PaymentMethod.cash => l10n.methodCash,
      PaymentMethod.mpesa => l10n.methodMpesa,
      PaymentMethod.bank => l10n.methodBank,
    };

/// Asks before a debt takes [name] past their credit limit: a warning,
/// not a rule, because the shop knows its customers, and the server
/// records it either way. True to go ahead.
Future<bool> confirmOverLimit(
  BuildContext context, {
  required String name,
  required int newBalanceCents,
  required int limitCents,
}) async {
  final l10n = AppLocalizations.of(context);
  final go = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      content: Text(
        l10n.limitWarning(
          name,
          Money.format(newBalanceCents, compact: true),
          Money.format(limitCents, compact: true),
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
  return go == true;
}
