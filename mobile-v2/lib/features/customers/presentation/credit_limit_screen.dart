import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/l10n/generated/app_localizations.dart';
import '../../../core/money/money.dart';
import '../../../core/sync/sync_controller.dart';
import '../../../core/widgets/form_page.dart';
import '../../ledger/presentation/record_debt_screen.dart';
import '../data/providers.dart';

/// How much a customer may owe (owners). A warning when a debt goes past
/// it, never a refusal: the shop decides.
class CreditLimitScreen extends ConsumerStatefulWidget {
  final String customerId;

  const CreditLimitScreen({super.key, required this.customerId});

  @override
  ConsumerState<CreditLimitScreen> createState() => _CreditLimitScreenState();
}

class _CreditLimitScreenState extends ConsumerState<CreditLimitScreen> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController();
  var _none = true;
  var _saving = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final c = await ref
        .read(customerRepositoryProvider)
        .watch(widget.customerId)
        .first;
    final limit = c?.creditLimitCents;
    if (!mounted) return;
    setState(() {
      _none = limit == null;
      if (limit != null) {
        _amount.text = Money.toWire(limit).replaceFirst(RegExp(r'\.00$'), '');
      }
    });
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_none && !_form.currentState!.validate()) return;
    setState(() => _saving = true);
    await ref
        .read(customerRepositoryProvider)
        .setCreditLimit(
          widget.customerId,
          _none ? null : Money.parse(_amount.text),
        );
    ref.read(syncProvider.notifier).requestSoon();
    if (mounted) context.go('/customers/${widget.customerId}');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return FormPage(
      title: l10n.creditLimitSet,
      formKey: _form,
      actionLabel: l10n.save,
      onAction: _saving ? null : _save,
      fields: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.creditLimitNone),
          value: _none,
          onChanged: (v) => setState(() => _none = v),
        ),
        if (!_none)
          AmountField(controller: _amount, label: l10n.creditLimitAmount),
      ],
    );
  }
}
