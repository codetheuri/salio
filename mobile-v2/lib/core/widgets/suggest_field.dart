import 'package:flutter/material.dart';

/// A text box that suggests what was typed before, as it is typed: product
/// names, suppliers. Picking a suggestion keeps names spelt one way, so
/// lists and reports group them. Anything new may still be typed.
class SuggestField extends StatefulWidget {
  final TextEditingController controller;
  final List<String> suggestions;
  final String label;
  final String? hint;
  final bool autofocus;
  final int? maxLength;
  final TextCapitalization textCapitalization;
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onSelected;

  const SuggestField({
    super.key,
    required this.controller,
    required this.suggestions,
    required this.label,
    this.hint,
    this.autofocus = false,
    this.maxLength,
    this.textCapitalization = TextCapitalization.sentences,
    this.validator,
    this.onSelected,
  });

  @override
  State<SuggestField> createState() => _SuggestFieldState();
}

class _SuggestFieldState extends State<SuggestField> {
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => RawAutocomplete<String>(
      textEditingController: widget.controller,
      focusNode: _focus,
      optionsBuilder: (value) {
        final typed = value.text.trim().toLowerCase();
        if (typed.isEmpty) return const <String>[];
        return widget.suggestions
            .where((s) {
              final l = s.toLowerCase();
              return l.contains(typed) && l != typed;
            })
            .take(6);
      },
      onSelected: widget.onSelected,
      fieldViewBuilder: (context, controller, focusNode, onSubmitted) =>
          TextFormField(
            controller: controller,
            focusNode: focusNode,
            autofocus: widget.autofocus,
            textCapitalization: widget.textCapitalization,
            maxLength: widget.maxLength,
            buildCounter:
                (
                  context, {
                  required currentLength,
                  required isFocused,
                  required maxLength,
                }) => null,
            decoration: InputDecoration(
              labelText: widget.label,
              hintText: widget.hint,
            ),
            validator: widget.validator,
          ),
      optionsViewBuilder: (context, onSelected, options) => Align(
        alignment: AlignmentDirectional.topStart,
        child: Material(
          elevation: 4,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: 240,
              maxWidth: constraints.maxWidth,
            ),
            child: ListView(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              children: [
                for (final s in options)
                  ListTile(
                    title: Text(
                      s,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => onSelected(s),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
