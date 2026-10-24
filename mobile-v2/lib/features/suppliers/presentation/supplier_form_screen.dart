import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/l10n/generated/app_localizations.dart';
import '../../../core/database/app_database.dart';
import '../../../core/phone/phone.dart';
import '../../../core/sync/sync_controller.dart';
import '../../../core/widgets/form_page.dart';
import '../../customers/presentation/customer_form_screen.dart';
import '../data/providers.dart';

/// Adds a supplier, or edits one ([supplierId]). The phone is optional;
/// picked from contacts or typed in any form, it is stored as E.164.
class SupplierFormScreen extends ConsumerStatefulWidget {
  final String? supplierId;

  const SupplierFormScreen({super.key, this.supplierId});

  @override
  ConsumerState<SupplierFormScreen> createState() => _SupplierFormState();
}

class _SupplierFormState extends ConsumerState<SupplierFormScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _notes = TextEditingController();
  SupplierRow? _original;
  var _saving = false;

  bool get _editing => widget.supplierId != null;

  @override
  void initState() {
    super.initState();
    final id = widget.supplierId;
    if (id != null) unawaited(_load(id));
  }

  Future<void> _load(String id) async {
    final s = await ref.read(supplierRepositoryProvider).watch(id).first;
    if (!mounted || s == null) return;
    final row = s.supplier;
    setState(() {
      _original = row;
      _name.text = row.name;
      _phone.text = row.phone == null ? '' : Phone.display(row.phone!);
      _notes.text = row.notes ?? '';
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final picked = await ref.read(contactPickerProvider)();
    if (!mounted || picked == null) return;
    setState(() {
      if (_name.text.trim().isEmpty && (picked.name?.isNotEmpty ?? false)) {
        _name.text = picked.name!;
      }
      final number = picked.phone;
      if (number != null) {
        final stored = Phone.normalize(number);
        _phone.text = stored == null ? number : Phone.display(stored);
      }
    });
    _form.currentState?.validate();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    final repo = ref.read(supplierRepositoryProvider);
    final original = _original;
    final String id;
    if (original == null) {
      id = await repo.add(
        name: _name.text,
        phone: _phone.text,
        notes: _notes.text,
      );
    } else {
      id = original.id;
      await repo.update(
        id,
        name: _name.text,
        phone: _phone.text,
        notes: _notes.text,
      );
    }
    ref.read(syncProvider.notifier).requestSoon();
    if (mounted) context.go('/suppliers/$id');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return FormPage(
      title: _editing ? l10n.supplierEdit : l10n.supplierAdd,
      formKey: _form,
      actionLabel: l10n.save,
      onAction: _saving || (_editing && _original == null) ? null : _save,
      fields: [
        TextFormField(
          controller: _name,
          autofocus: !_editing,
          textCapitalization: TextCapitalization.words,
          maxLength: 255,
          decoration: InputDecoration(
            labelText: l10n.customerName,
            hintText: l10n.supplierNameHint,
          ),
          validator: (v) =>
              v == null || v.trim().isEmpty ? l10n.fieldRequired : null,
        ),
        TextFormField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ()-]')),
          ],
          decoration: InputDecoration(
            labelText: l10n.orderSupplierPhone,
            suffixIcon: IconButton(
              tooltip: l10n.customerPickContact,
              icon: const Icon(Icons.contacts_outlined),
              onPressed: _pick,
            ),
          ),
          validator: (v) => v == null || v.trim().isEmpty
              ? null
              : Phone.normalize(v) == null
              ? l10n.phoneInvalid
              : null,
        ),
        TextFormField(
          controller: _notes,
          minLines: 2,
          maxLines: 5,
          maxLength: 1000,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(labelText: l10n.customerNotes),
        ),
      ],
    );
  }
}
