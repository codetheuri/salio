import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/l10n/generated/app_localizations.dart';
import '../../../core/money/money.dart';
import '../../../core/sync/sync_controller.dart';
import '../../../core/widgets/form_page.dart';
import '../../ledger/presentation/widgets/money_fields.dart';
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
  var _hadLimit = false;
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
    if (!mounted || limit == null) return;
    setState(() {
      _hadLimit = true;
      _amount.text = Money.toWire(limit).replaceFirst(RegExp(r'\.00$'), '');
    });
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    final text = _amount.text.trim();
    await ref
        .read(customerRepositoryProvider)
        .setCreditLimit(
          widget.customerId,
          text.isEmpty ? null : Money.parse(text),
        );
    ref.read(syncProvider.notifier).requestSoon();
    if (mounted) context.go('/customers/${widget.customerId}');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // The amount is the whole point of the screen, so it is always there,
    // focused; empty means no limit, rather than a switch to find first.
    return FormPage(
      title: l10n.creditLimitSet,
      formKey: _form,
      actionLabel: l10n.save,
      onAction: _saving ? null : _save,
      fields: [
        AmountField(
          controller: _amount,
          label: l10n.creditLimitAmount,
          helperText: l10n.creditLimitHelp,
          optional: true,
          onChanged: (_) => setState(() {}),
        ),
        if (_hadLimit && _amount.text.isNotEmpty)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              icon: const Icon(Icons.block),
              label: Text(l10n.creditLimitRemove),
              onPressed: () => setState(_amount.clear),
            ),
          ),
      ],
    );
  }
}
