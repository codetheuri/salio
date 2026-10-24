import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/l10n/generated/app_localizations.dart';
import '../../../app/theme/app_colors.dart';
import '../../../core/database/app_database.dart';
import '../../../core/session/current_user.dart';
import '../../../core/session/permissions.dart';
import '../../../core/sync/sync_controller.dart';
import '../../../core/time/shop_time.dart';
import '../../../core/widgets/form_page.dart';
import '../../../core/widgets/record_detail.dart';
import '../data/providers.dart';

/// Notes a product that ran out, or edits one ([noteId]). A note already
/// on a purchase order is shown read-only: what the supplier holds is what
/// the order says, so only cancelling the order frees it.
class StockNoteScreen extends ConsumerStatefulWidget {
  final String? noteId;

  const StockNoteScreen({super.key, this.noteId});

  @override
  ConsumerState<StockNoteScreen> createState() => _StockNoteScreenState();
}

class _StockNoteScreenState extends ConsumerState<StockNoteScreen> {
  final _form = GlobalKey<FormState>();
  final _product = TextEditingController();
  final _notes = TextEditingController();
  late DateTime _ranOut = ref.read(shopTodayProvider);
  StockRequestRow? _original;
  var _saving = false;

  bool get _editing => widget.noteId != null;

  @override
  void initState() {
    super.initState();
    final id = widget.noteId;
    if (id != null) unawaited(_load(id));
  }

  Future<void> _load(String id) async {
    final row = await ref.read(stockRepositoryProvider).watchNote(id).first;
    if (!mounted || row == null) return;
    setState(() {
      _original = row;
      _product.text = row.productName;
      _notes.text = row.notes ?? '';
      _ranOut = row.neededOn;
    });
  }

  @override
  void dispose() {
    _product.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDay() async {
    final today = ref.read(shopTodayProvider);
    final picked = await showDatePicker(
      context: context,
      initialDate: _ranOut.isAfter(today) ? today : _ranOut,
      firstDate: today.subtract(const Duration(days: 365)),
      lastDate: today,
    );
    if (picked != null && mounted) {
      setState(
        () => _ranOut = DateTime.utc(picked.year, picked.month, picked.day),
      );
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    final repo = ref.read(stockRepositoryProvider);
    final original = _original;
    if (original == null) {
      await repo.add(
        productName: _product.text,
        neededOn: _ranOut,
        notes: _notes.text,
      );
    } else {
      await repo.update(
        original.id,
        productName: _product.text,
        neededOn: _ranOut,
        notes: _notes.text,
      );
    }
    ref.read(syncProvider.notifier).requestSoon();
    if (mounted) context.go('/stock');
  }

  Future<void> _remove() async {
    final l10n = AppLocalizations.of(context);
    if (!await confirmAction(
      context,
      message: l10n.stockNoteRemoveConfirm,
      action: l10n.stockNoteRemove,
    )) {
      return;
    }
    await ref.read(stockRepositoryProvider).remove(widget.noteId!);
    ref.read(syncProvider.notifier).requestSoon();
    if (mounted) context.go('/stock');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final user = ref.watch(currentUserProvider);
    final original = _original;
    final ordered = original?.purchaseOrderId != null;
    // Nothing to change until the note being edited has loaded.
    final canChange =
        user.can(Permission.stockRequest) &&
        !ordered &&
        (!_editing || original != null);

    return FormPage(
      title: _editing ? l10n.stockNoteEdit : l10n.stockNoteNew,
      formKey: _form,
      actionLabel: l10n.save,
      onAction: _saving || !canChange ? null : _save,
      fields: [
        if (ordered)
          Text(
            l10n.stockNoteOrdered,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        TextFormField(
          controller: _product,
          enabled: canChange,
          autofocus: !_editing,
          textCapitalization: TextCapitalization.sentences,
          maxLength: 255,
          decoration: InputDecoration(
            labelText: l10n.saleProduct,
            hintText: l10n.stockProductHint,
          ),
          validator: (v) =>
              v == null || v.trim().isEmpty ? l10n.fieldRequired : null,
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          enabled: canChange,
          leading: const Icon(Icons.event_outlined),
          title: Text(l10n.stockRanOutOn),
          subtitle: Text(ShopTime.date(_ranOut, locale)),
          onTap: () => unawaited(_pickDay()),
        ),
        TextFormField(
          controller: _notes,
          enabled: canChange,
          textCapitalization: TextCapitalization.sentences,
          maxLength: 500,
          minLines: 1,
          maxLines: 4,
          decoration: InputDecoration(labelText: l10n.paymentNote),
        ),
        if (_editing && canChange)
          VoidButton(
            label: l10n.stockNoteRemove,
            onPressed: () => unawaited(_remove()),
          ),
      ],
    );
  }
}
