import 'package:flutter/material.dart';

import '../../app/theme/app_spacing.dart';
import '../layout/breakpoints.dart';

/// A form screen: fields that scroll, and the Save button in a bar at the
/// bottom that rides above the keyboard, so on a 320 × 640 phone it is
/// never hidden while typing (docs/10, §5).
class FormPage extends StatelessWidget {
  final String title;
  final GlobalKey<FormState> formKey;
  final List<Widget> fields;
  final String actionLabel;
  final VoidCallback? onAction;

  const FormPage({
    super.key,
    required this.title,
    required this.formKey,
    required this.fields,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ReadableWidth(
        child: Form(
          key: formKey,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              for (final f in fields) ...[
                f,
                const SizedBox(height: AppSpacing.md),
              ],
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
            AppSpacing.sm + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: Breakpoints.formWidth,
              ),
              child: ElevatedButton(
                onPressed: onAction,
                child: Text(actionLabel),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
