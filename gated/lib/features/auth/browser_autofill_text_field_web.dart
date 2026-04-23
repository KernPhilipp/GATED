import 'dart:js_interop';

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

const _authInputClassName = 'gated-auth-browser-input';
const _authInputStyleElementId = 'gated-auth-browser-input-style';

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
    _ensureAutofillStyles();
    _inputListener = ((web.Event _) => _syncFromInput()).toJS;
    _changeListener = ((web.Event _) {
      _syncFromInput(collapseSelection: true);
    }).toJS;
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
    _applyInputAttributes();

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
    input.className = _authInputClassName;
    input.disabled = !widget.enabled;
    input.spellcheck = false;
    input.setAttribute('autocapitalize', 'none');
    input.setAttribute('autocorrect', widget.autocorrect ? 'on' : 'off');

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textColor = widget.enabled
        ? theme.textTheme.bodyLarge?.color ?? colorScheme.onSurface
        : theme.disabledColor;
    final cursorColor =
        theme.textSelectionTheme.cursorColor ?? theme.colorScheme.primary;
    final selectionBackground =
        theme.textSelectionTheme.selectionColor ??
        colorScheme.primary.withValues(alpha: 0.32);
    final selectionTextColor = widget.enabled
        ? colorScheme.onPrimary
        : colorScheme.onSurface.withValues(alpha: 0.38);
    final backgroundColor = colorScheme.surface;
    final textColorCss = _cssColor(textColor);

    final style = input.style;
    style.width = '100%';
    style.height = '100%';
    style.boxSizing = 'border-box';
    style.border = '0';
    style.outline = '0';
    style.margin = '0';
    style.padding = '0';
    style.background = 'transparent';
    style.color = textColorCss;
    style.font = 'inherit';
    style.fontSize = '16px';
    style.minWidth = '0';
    style.setProperty('caret-color', _cssColor(cursorColor));
    style.setProperty('-webkit-text-fill-color', textColorCss);
    style.setProperty('--gated-auth-input-color', textColorCss);
    style.setProperty('--gated-auth-input-caret-color', _cssColor(cursorColor));
    style.setProperty(
      '--gated-auth-input-background',
      _cssColor(backgroundColor),
    );
    style.setProperty(
      '--gated-auth-input-selection-background',
      _cssColor(selectionBackground),
    );
    style.setProperty(
      '--gated-auth-input-selection-color',
      _cssColor(selectionTextColor),
    );
    style.setProperty('-webkit-appearance', 'none');
  }

  String get _effectiveInputType {
    if (widget.inputType == 'password' && !widget.obscureText) {
      return 'text';
    }

    return widget.inputType;
  }

  void _syncFromInput({bool collapseSelection = false}) {
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
    if (collapseSelection) {
      _collapseInputSelection();
    }
  }

  void _syncToInput() {
    final input = _input;
    if (input == null) {
      return;
    }

    final value = widget.controller.text;
    if (input.value != value) {
      input.value = value;
      _collapseInputSelection();
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

  void _collapseInputSelection() {
    final input = _input;
    if (input == null) {
      return;
    }

    final offset = input.value.length;
    try {
      input.setSelectionRange(offset, offset);
    } catch (_) {
      // Some input types do not allow selection ranges.
    }
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

void _ensureAutofillStyles() {
  if (web.document.getElementById(_authInputStyleElementId) != null) {
    return;
  }

  final styleElement = web.document.createElement('style');
  styleElement.id = _authInputStyleElementId;
  styleElement.textContent =
      '''
input.$_authInputClassName:-webkit-autofill,
input.$_authInputClassName:-webkit-autofill:hover,
input.$_authInputClassName:-webkit-autofill:focus,
input.$_authInputClassName:-webkit-autofill:active {
  -webkit-text-fill-color: var(--gated-auth-input-color) !important;
  caret-color: var(--gated-auth-input-caret-color) !important;
  -webkit-box-shadow: 0 0 0 1000px var(--gated-auth-input-background) inset !important;
  box-shadow: 0 0 0 1000px var(--gated-auth-input-background) inset !important;
  transition: background-color 999999s ease-in-out 0s !important;
}

input.$_authInputClassName::selection {
  background: var(--gated-auth-input-selection-background);
  color: var(--gated-auth-input-selection-color);
}
''';
  web.document.head?.appendChild(styleElement);
}

String _cssColor(Color color) {
  final argb = color.toARGB32();
  final alpha = (argb >> 24) & 0xff;
  final red = (argb >> 16) & 0xff;
  final green = (argb >> 8) & 0xff;
  final blue = argb & 0xff;

  if (alpha == 0xff) {
    return 'rgb($red $green $blue)';
  }

  return 'rgba($red, $green, $blue, ${alpha / 255})';
}
