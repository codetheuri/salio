import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_native_contact_picker/flutter_native_contact_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';

import '../../../app/l10n/generated/app_localizations.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../core/database/app_database.dart';
import '../../../core/phone/phone.dart';
import '../../../core/sync/sync_controller.dart';
import '../../../core/widgets/form_page.dart';
import '../data/providers.dart';

final _log = Logger('customers');

/// A contact the user picked: Android's own contact screen, so Salio never
/// asks to read the whole address book.
typedef PickedContact = ({String? name, String? phone});

/// Opens the phone's contact picker. Replaced in tests, which have none.
final contactPickerProvider = Provider<Future<PickedContact?> Function()>(
  (ref) => () async {
    try {
      final c = await FlutterNativeContactPicker().selectPhoneNumber();
      return c == null
          ? null
          : (name: c.fullName, phone: c.selectedPhoneNumber);
    } on PlatformException catch (e) {
      _log.info('contact picker failed: $e');
      return null;
    }
  },
);

/// Adds a customer, or edits one when [customerId] is given.
///
/// The phone number is required (a field-test request), picked from
/// contacts or typed in any form, and stored in one form (B15). A walk-in
/// customer with no phone is a deliberate choice, not a field left empty.
class CustomerFormScreen extends ConsumerStatefulWidget {
  final String? customerId;

  const CustomerFormScreen({super.key, this.customerId});

  @override
  ConsumerState<CustomerFormScreen> createState() => _CustomerFormState();
}

class _CustomerFormState extends ConsumerState<CustomerFormScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _notes = TextEditingController();
  var _noPhone = false;
  var _saving = false;
  CustomerRow? _original;

  /// Another customer who already has the number typed.
  CustomerRow? _existing;

  bool get _editing => widget.customerId != null;

  @override
  void initState() {
    super.initState();
    final id = widget.customerId;
    if (id != null) unawaited(_load(id));
  }

  Future<void> _load(String id) async {
    final c = await ref.read(customerRepositoryProvider).watch(id).first;
    if (!mounted || c == null) return;
    final row = c.customer;
    setState(() {
      _original = row;
      _name.text = row.name;
      _phone.text = row.phone == null ? '' : Phone.display(row.phone!);
      _notes.text = row.notes ?? '';
      _noPhone = row.phone == null;
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
        _noPhone = false;
      }
      _existing = null;
    });
    _form.currentState?.validate();
  }

  Future<void> _save() async {
    setState(() => _existing = null);
    if (!_form.currentState!.validate()) return;
    final repo = ref.read(customerRepositoryProvider);
    final phone = _noPhone ? '' : _phone.text;
    if (phone.isNotEmpty) {
      final other = await repo.findByPhone(phone, except: widget.customerId);
      if (!mounted) return;
      if (other != null) {
        setState(() => _existing = other);
        return;
      }
    }
    setState(() => _saving = true);
    final String id;
    final original = _original;
    if (original == null) {
      id = await repo.add(name: _name.text, phone: phone);
    } else {
      id = original.id;
      // Only what changed, so another phone's edit to the rest survives.
      final stored = phone.isEmpty ? null : Phone.normalize(phone);
      await repo.update(
        id,
        name: _name.text.trim() == original.name ? null : _name.text,
        phone: stored == original.phone ? null : phone,
        notes: _notes.text.trim() == (original.notes ?? '')
            ? null
            : _notes.text,
      );
    }
    ref.read(syncProvider.notifier).requestSoon();
    if (mounted) context.go('/customers/$id');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final existing = _existing;
    return FormPage(
      title: _editing ? l10n.customerEdit : l10n.customerAdd,
      formKey: _form,
      actionLabel: l10n.save,
      onAction: _saving || (_editing && _original == null) ? null : _save,
      fields: [
        TextFormField(
          controller: _name,
          autofocus: !_editing,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(labelText: l10n.customerName),
          validator: (v) =>
              v == null || v.trim().isEmpty ? l10n.fieldRequired : null,
        ),
        TextFormField(
          controller: _phone,
          enabled: !_noPhone,
          keyboardType: TextInputType.phone,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ()-]')),
          ],
          onChanged: (_) {
            if (_existing != null) setState(() => _existing = null);
          },
          decoration: InputDecoration(
            labelText: l10n.customerPhone,
            suffixIcon: IconButton(
              tooltip: l10n.customerPickContact,
              icon: const Icon(Icons.contacts_outlined),
              onPressed: _noPhone ? null : _pick,
            ),
          ),
          validator: (v) {
            if (_noPhone) return null;
            if (v == null || v.trim().isEmpty) {
              return l10n.customerPhoneRequired;
            }
            return Phone.normalize(v) == null ? l10n.phoneInvalid : null;
          },
        ),
        if (existing != null)
          Card(
            child: ListTile(
              leading: const Icon(Icons.person_search_outlined),
              title: Text(l10n.customerExists(existing.name)),
              trailing: TextButton(
                onPressed: () => context.go('/customers/${existing.id}'),
                child: Text(l10n.customerOpenExisting),
              ),
            ),
          ),
        CheckboxListTile(
          value: _noPhone,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: Text(l10n.customerNoPhone),
          onChanged: (v) => setState(() {
            _noPhone = v ?? false;
            _existing = null;
            if (_noPhone) _phone.clear();
          }),
        ),
        if (_editing) ...[
          const SizedBox(height: AppSpacing.xs),
          TextFormField(
            controller: _notes,
            minLines: 2,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(labelText: l10n.customerNotes),
            style: theme.textTheme.bodyLarge,
          ),
        ],
      ],
    );
  }
}
