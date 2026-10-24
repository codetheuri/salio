import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/l10n/generated/app_localizations.dart';
import '../../../app/router/app_router.dart';
import '../../../core/session/session_controller.dart';
import 'register_screen.dart';
import 'widgets/auth_page.dart';

/// Joins a shop as staff with the invite code the owner shared, and signs
/// in. Needs a connection once.
class JoinScreen extends ConsumerStatefulWidget {
  const JoinScreen({super.key});

  @override
  ConsumerState<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends ConsumerState<JoinScreen> {
  final _form = GlobalKey<FormState>();
  final _code = TextEditingController();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_code, _name, _phone, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(sessionProvider.notifier)
          .join(
            code: _code.text,
            name: _name.text,
            phone: _phone.text,
            password: _password.text,
          );
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() => _error = accountFailure(AppLocalizations.of(context), e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AuthPage(
      formKey: _form,
      title: l10n.joinTitle,
      fields: [
        TextFormField(
          controller: _code,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]')),
            LengthLimitingTextInputFormatter(10),
          ],
          decoration: InputDecoration(
            labelText: l10n.joinCode,
            helperText: l10n.joinCodeHint,
          ),
          validator: (v) =>
              v == null || v.trim().length < 4 ? l10n.fieldRequired : null,
        ),
        NameField(controller: _name, label: l10n.registerYourName),
        PhoneField(controller: _phone, label: l10n.signInPhone),
        NewPasswordField(controller: _password, onSubmitted: _submit),
      ],
      error: _error,
      buttonLabel: l10n.joinButton,
      busy: _busy,
      onSubmit: _submit,
      links: [
        AuthLink(
          l10n.signInButton,
          onPressed: _busy ? null : () => context.go(AppRoutes.signIn),
        ),
      ],
    );
  }
}
