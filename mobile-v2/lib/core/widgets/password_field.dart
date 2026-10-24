import 'package:flutter/material.dart';

import '../../app/l10n/generated/app_localizations.dart';

/// A password box with an eye to show what was typed: on a phone keyboard a
/// mistyped password is otherwise found only after the server refuses it.
/// Hidden again whenever the screen is rebuilt from scratch.
class PasswordField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String? errorText;
  final Iterable<String> autofillHints;
  final FormFieldValidator<String>? validator;
  final VoidCallback? onSubmitted;

  const PasswordField({
    super.key,
    required this.controller,
    required this.label,
    this.errorText,
    this.autofillHints = const [AutofillHints.password],
    this.validator,
    this.onSubmitted,
  });

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  var _shown = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return TextFormField(
      controller: widget.controller,
      obscureText: !_shown,
      // Shown passwords must not be learned by the keyboard.
      enableSuggestions: false,
      autocorrect: false,
      autofillHints: widget.autofillHints,
      onFieldSubmitted: (_) => widget.onSubmitted?.call(),
      decoration: InputDecoration(
        labelText: widget.label,
        errorText: widget.errorText,
        suffixIcon: IconButton(
          tooltip: _shown ? l10n.passwordHide : l10n.passwordShow,
          icon: Icon(_shown ? Icons.visibility_off : Icons.visibility),
          onPressed: () => setState(() => _shown = !_shown),
        ),
      ),
      validator: widget.validator,
    );
  }
}
