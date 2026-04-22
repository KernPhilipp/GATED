import 'dart:js_interop';

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

class BrowserAutofillTextField extends StatefulWidget {
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
  final VoidCallback? onInteraction;
  final ValueChanged<String>? onFieldSubmitted;
  final FormFieldValidator<String>? validator;

  @override
  State<BrowserAutofillTextField> createState() =>
      _BrowserAutofillTextFieldState();
}

class _BrowserAutofillTextFieldState extends State<BrowserAutofillTextField> {
  web.HTMLInputElement? _input;
  late final web.EventListener _inputListener;
  late final web.EventListener _changeListener;
  late final web.EventListener _focusListener;
  late final web.EventListener _blurListener;
  late final web.EventListener _keyDownListener;

  bool _isFocused = false;
  FormFieldState<String>? _fieldState;

  @override
  void initState() {
    super.initState();
    _inputListener = ((web.Event _) => _syncFromInput()).toJS;
    _changeListener = ((web.Event _) => _syncFromInput()).toJS;
    _focusListener = ((web.Event _) => _handleFocusChange(true)).toJS;
    _blurListener = ((web.Event _) => _handleFocusChange(false)).toJS;
    _keyDownListener = _handleKeyDown.toJS;
    widget.controller.addListener(_syncToInput);
  }

  @override
  void didUpdateWidget(BrowserAutofillTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_syncToInput);
      widget.controller.addListener(_syncToInput);
      _syncToInput();
    }
    _applyInputAttributes();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncToInput);
    _removeInputListeners();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return FormField<String>(
      initialValue: widget.controller.text,
      validator: widget.validator,
      enabled: widget.enabled,
      builder: (field) {
        _fieldState = field;
        final decoration = widget.decoration
            .applyDefaults(theme.inputDecorationTheme)
            .copyWith(errorText: field.errorText);

        return InputDecorator(
          decoration: decoration,
          isFocused: _isFocused,
          isEmpty: widget.controller.text.isEmpty,
          child: SizedBox(
            height: 24,
            child: HtmlElementView.fromTagName(
              tagName: 'input',
              onElementCreated: _handleElementCreated,
            ),
          ),
        );
      },
    );
  }

  void _handleElementCreated(Object element) {
    final input = element as web.HTMLInputElement;
    _removeInputListeners();
    _input = input;
    _applyInputAttributes();
    _syncToInput();
    input.addEventListener('input', _inputListener);
    input.addEventListener('change', _changeListener);
    input.addEventListener('focus', _focusListener);
    input.addEventListener('blur', _blurListener);
    input.addEventListener('keydown', _keyDownListener);
  }

  void _applyInputAttributes() {
    final input = _input;
    if (input == null) {
      return;
    }

    input.type = _effectiveInputType;
    input.autocomplete = widget.autocomplete;
    input.name = widget.autocomplete;
    input.disabled = !widget.enabled;
    input.spellcheck = false;
    input.setAttribute('autocapitalize', 'none');
    input.setAttribute('autocorrect', widget.autocorrect ? 'on' : 'off');

    final style = input.style;
    style.width = '100%';
    style.height = '100%';
    style.boxSizing = 'border-box';
    style.border = '0';
    style.outline = '0';
    style.margin = '0';
    style.padding = '0';
    style.background = 'transparent';
    style.color = 'inherit';
    style.font = 'inherit';
    style.fontSize = '16px';
    style.minWidth = '0';
    style.setProperty('-webkit-appearance', 'none');
  }

  String get _effectiveInputType {
    if (widget.inputType == 'password' && !widget.obscureText) {
      return 'text';
    }

    return widget.inputType;
  }

  void _syncFromInput() {
    final input = _input;
    if (input == null) {
      return;
    }

    widget.onInteraction?.call();
    final value = input.value;
    if (widget.controller.text != value) {
      widget.controller.value = TextEditingValue(
        text: value,
        selection: TextSelection.collapsed(offset: value.length),
      );
    }
    _fieldState?.didChange(value);
  }

  void _syncToInput() {
    final input = _input;
    if (input == null) {
      return;
    }

    final value = widget.controller.text;
    if (input.value != value) {
      input.value = value;
    }
    _fieldState?.didChange(value);
  }

  void _handleFocusChange(bool isFocused) {
    widget.onInteraction?.call();
    if (_isFocused == isFocused) {
      return;
    }

    setState(() => _isFocused = isFocused);
  }

  void _handleKeyDown(web.Event event) {
    if (!event.isA<web.KeyboardEvent>()) {
      return;
    }

    final keyboardEvent = event as web.KeyboardEvent;
    if (keyboardEvent.key != 'Enter') {
      return;
    }

    widget.onFieldSubmitted?.call(widget.controller.text);
  }

  void _removeInputListeners() {
    final input = _input;
    if (input == null) {
      return;
    }

    input.removeEventListener('input', _inputListener);
    input.removeEventListener('change', _changeListener);
    input.removeEventListener('focus', _focusListener);
    input.removeEventListener('blur', _blurListener);
    input.removeEventListener('keydown', _keyDownListener);
    _input = null;
  }
}
