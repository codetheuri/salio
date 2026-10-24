import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/l10n/generated/app_localizations.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/layout/breakpoints.dart';
import '../../../../core/phone/phone.dart';

/// The frame of the signed-out screens: the name, a title, the fields, one
/// button and the links to the other two. Scrolls, so the button is
/// reachable above the keyboard on a 320 × 640 phone.
class AuthPage extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final String title;
  final Widget? notice;
  final List<Widget> fields;
  final String? error;
  final String buttonLabel;
  final bool busy;
  final VoidCallback onSubmit;
  final List<Widget> links;

  const AuthPage({
    super.key,
    required this.formKey,
    required this.title,
    required this.fields,
    required this.buttonLabel,
    required this.busy,
    required this.onSubmit,
    this.notice,
    this.error,
    this.links = const [],
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: Breakpoints.formWidth,
              ),
              child: Form(
                key: formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Salio',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.displayLarge?.copyWith(
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium,
                    ),
                    if (notice != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      notice!,
                    ],
                    const SizedBox(height: AppSpacing.lg),
                    for (final (i, field) in fields.indexed) ...[
                      if (i > 0) const SizedBox(height: AppSpacing.md),
                      field,
                    ],
                    if (error != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        error!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: AppColors.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.lg),
                    ElevatedButton(
                      onPressed: busy ? null : onSubmit,
                      child: busy
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(buttonLabel),
                    ),
                    if (links.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.md),
                      ...links,
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A phone field for the signed-out screens, checked by the same rule the
/// server stores numbers by (B15).
class PhoneField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? serverError;

  const PhoneField({
    super.key,
    required this.controller,
    required this.label,
    this.serverError,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.phone,
      autofillHints: const [AutofillHints.telephoneNumber],
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ()-]')),
      ],
      decoration: InputDecoration(labelText: label, errorText: serverError),
      validator: (v) {
        if (v == null || v.trim().isEmpty) return l10n.fieldRequired;
        return Phone.normalize(v) == null ? l10n.phoneInvalid : null;
      },
    );
  }
}

/// A link to another signed-out screen.
class AuthLink extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;

  const AuthLink(this.label, {super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: onPressed,
    child: Text(label, textAlign: TextAlign.center),
  );
}
