import 'package:flutter/material.dart';

import 'browser_autofill_text_field_keys.dart';

class BrowserAutofillTextField extends StatelessWidget {
  const BrowserAutofillTextField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.autocomplete,
    required this.inputType,
    required this.decoration,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.obscureText = false,
    this.enableSuggestions = true,
    this.autocorrect = true,
    this.enabled = true,
    this.preferFlutterField = false,
    this.browserFormId,
    this.onBrowserSubmit,
    this.onInteraction,
    this.onFieldSubmitted,
    this.validator,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String autocomplete;
  final String inputType;
  final InputDecoration decoration;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final bool obscureText;
  final bool enableSuggestions;
  final bool autocorrect;
  final bool enabled;
  final bool preferFlutterField;
  final String? browserFormId;
  final VoidCallback? onBrowserSubmit;
  final VoidCallback? onInteraction;
  final ValueChanged<String>? onFieldSubmitted;
  final FormFieldValidator<String>? validator;

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: preferFlutterField
          ? browserAutofillFlutterFieldKey
          : browserAutofillBrowserFieldKey,
      child: TextFormField(
        controller: controller,
        focusNode: focusNode,
        selectAllOnFocus: false,
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        autofillHints: autofillHints,
        obscureText: obscureText,
        enableSuggestions: enableSuggestions,
        autocorrect: autocorrect,
        enabled: enabled,
        decoration: decoration,
        onTap: onInteraction,
        onFieldSubmitted: onFieldSubmitted,
        validator: validator,
      ),
    );
  }
}
