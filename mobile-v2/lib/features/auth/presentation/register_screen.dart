import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/l10n/generated/app_localizations.dart';
import '../../../app/router/app_router.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/session/session_controller.dart';
import '../../../core/widgets/failure_text.dart';
import '../../../core/widgets/password_field.dart';
import 'widgets/auth_page.dart';

/// Registers a new shop with its owner, who is then signed in. Needs a
/// connection once; everything after works offline.
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _form = GlobalKey<FormState>();
  final _shop = TextEditingController();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_shop, _name, _phone, _password]) {
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
          .register(
            businessName: _shop.text,
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
      title: l10n.registerTitle,
      fields: [
        NameField(controller: _shop, label: l10n.registerShopName),
        NameField(controller: _name, label: l10n.registerYourName),
        PhoneField(controller: _phone, label: l10n.signInPhone),
        NewPasswordField(controller: _password, onSubmitted: _submit),
      ],
      error: _error,
      buttonLabel: l10n.registerButton,
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

/// A name of at least two letters, as the server requires.
class NameField extends StatelessWidget {
  final TextEditingController controller;
  final String label;

  const NameField({super.key, required this.controller, required this.label});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return TextFormField(
      controller: controller,
      textCapitalization: TextCapitalization.words,
      maxLength: 255,
      buildCounter: _noCounter,
      decoration: InputDecoration(labelText: label),
      validator: (v) =>
          v == null || v.trim().length < 2 ? l10n.fieldRequired : null,
    );
  }
}

/// A new password: at least [minPasswordLength] characters, as the server
/// requires.
class NewPasswordField extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSubmitted;

  const NewPasswordField({
    super.key,
    required this.controller,
    required this.onSubmitted,
  });

  /// The server's minimum (server-v2, business/dto.go).
  static const minPasswordLength = 5;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return PasswordField(
      controller: controller,
      label: l10n.passwordNew,
      autofillHints: const [AutofillHints.newPassword],
      onSubmitted: onSubmitted,
      validator: (v) => v == null || v.length < minPasswordLength
          ? l10n.passwordTooShort
          : null,
    );
  }
}

Widget? _noCounter(
  BuildContext context, {
  required int currentLength,
  required bool isFocused,
  required int? maxLength,
}) => null;

/// Registering and joining fail in a few known ways, said in the app's
/// language rather than the server's English.
String accountFailure(AppLocalizations l10n, Object e) {
  if (e is ApiException) {
    if (e.kind == ApiFailure.conflict) return l10n.phoneTaken;
    if (e.fieldErrors.containsKey('phone')) return l10n.phoneInvalid;
    if (e.status == 400) return l10n.inviteUnusable;
  }
  return describeFailure(l10n, e);
}
