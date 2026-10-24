import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/l10n/generated/app_localizations.dart';
import '../../../app/router/app_router.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/session/session_controller.dart';
import '../../../core/widgets/failure_text.dart';
import '../../../core/widgets/password_field.dart';
import 'widgets/auth_page.dart';

/// Sign in with a phone number and password. Also where an account comes
/// back to after the server ended its session, with the phone filled in.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _form = GlobalKey<FormState>();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;
  Map<String, String> _fieldErrors = const {};

  @override
  void initState() {
    super.initState();
    final ended = ref.read(sessionProvider).value;
    if (ended != null) _phone.text = ended.account.phone;
  }

  @override
  void dispose() {
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
      _fieldErrors = const {};
    });
    try {
      await ref
          .read(sessionProvider.notifier)
          .signIn(phone: _phone.text, password: _password.text);
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _error = describeFailure(AppLocalizations.of(context), e);
        _fieldErrors = e is ApiException ? e.fieldErrors : const {};
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final ended = ref.watch(sessionProvider).value;
    String? required(String? v) =>
        v == null || v.trim().isEmpty ? l10n.fieldRequired : null;

    return AuthPage(
      formKey: _form,
      title: l10n.signInTitle,
      notice: ended == null
          ? null
          : Text(
              [
                l10n.signInAgain,
                if (ended.endedReason?.isNotEmpty ?? false) ended.endedReason!,
              ].join('\n'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
      fields: [
        TextFormField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          autofillHints: const [AutofillHints.telephoneNumber],
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ()-]')),
          ],
          decoration: InputDecoration(
            labelText: l10n.signInPhone,
            errorText: _fieldErrors['phone'],
          ),
          validator: required,
        ),
        PasswordField(
          controller: _password,
          label: l10n.signInPassword,
          errorText: _fieldErrors['password'],
          onSubmitted: _submit,
          validator: required,
        ),
      ],
      error: _error,
      buttonLabel: l10n.signInButton,
      busy: _busy,
      onSubmit: _submit,
      // An account signing in again returns to its own shop.
      links: ended != null
          ? const []
          : [
              AuthLink(
                l10n.signInNoAccount,
                onPressed: _busy ? null : () => context.go(AppRoutes.register),
              ),
              AuthLink(
                l10n.signInHaveInvite,
                onPressed: _busy ? null : () => context.go(AppRoutes.join),
              ),
            ],
    );
  }
}
