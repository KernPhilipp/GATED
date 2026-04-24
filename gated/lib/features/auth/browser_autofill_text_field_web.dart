import 'dart:js_interop';

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import 'browser_autofill_text_field_keys.dart';

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
    _syncBrowserFormRegistration();
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
    if (oldWidget.browserFormId != widget.browserFormId ||
        oldWidget.onBrowserSubmit != widget.onBrowserSubmit) {
      _disposeBrowserSubmitForm(
        formId: oldWidget.browserFormId,
        onSubmit: oldWidget.onBrowserSubmit,
      );
      _syncBrowserFormRegistration();
    }
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
    _disposeBrowserSubmitForm(
      formId: widget.browserFormId,
      onSubmit: widget.onBrowserSubmit,
    );
    _removeInputListeners();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.preferFlutterField) {
      _removeInputListeners();
      return KeyedSubtree(
        key: browserAutofillFlutterFieldKey,
        child: _buildFlutterTextFormField(),
      );
    }

    final theme = Theme.of(context);
    _applyInputAttributes();

    return KeyedSubtree(
      key: browserAutofillBrowserFieldKey,
      child: Focus(
        focusNode: widget.focusNode,
        child: FormField<String>(
          initialValue: widget.controller.text,
          validator: widget.validator,
          enabled: widget.enabled,
          builder: (field) {
            _fieldState = field;
            final decoration = widget.decoration
                .applyDefaults(theme.inputDecorationTheme)
                .copyWith(
                  errorText: field.errorText,
                  floatingLabelBehavior:
                      widget.decoration.floatingLabelBehavior ??
                      FloatingLabelBehavior.always,
                );

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
        ),
      ),
    );
  }

  Widget _buildFlutterTextFormField() {
    return TextFormField(
      controller: widget.controller,
      focusNode: widget.focusNode,
      selectAllOnFocus: false,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      autofillHints: widget.autofillHints,
      obscureText: widget.obscureText,
      enableSuggestions: widget.enableSuggestions,
      autocorrect: widget.autocorrect,
      enabled: widget.enabled,
      decoration: widget.decoration,
      onTap: widget.onInteraction,
      onFieldSubmitted: widget.onFieldSubmitted,
      validator: widget.validator,
    );
  }

  void _syncBrowserFormRegistration() {
    _ensureBrowserSubmitForm(
      formId: widget.browserFormId,
      onSubmit: widget.onBrowserSubmit,
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
    if (widget.browserFormId != null && widget.browserFormId!.isNotEmpty) {
      input.setAttribute('form', widget.browserFormId!);
    } else {
      input.removeAttribute('form');
    }

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
    if (isFocused) {
      widget.focusNode.requestFocus();
    } else if (widget.focusNode.hasFocus) {
      widget.focusNode.unfocus();
    }
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

    keyboardEvent.preventDefault();
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

final Map<String, _BrowserSubmitFormBridge> _browserSubmitForms =
    <String, _BrowserSubmitFormBridge>{};

class _BrowserSubmitFormBridge {
  _BrowserSubmitFormBridge({
    required this.form,
    required this.submitListener,
    required this.onSubmit,
  });

  final web.HTMLFormElement form;
  final web.EventListener submitListener;
  VoidCallback onSubmit;
  int refCount = 0;
}

void _ensureBrowserSubmitForm({
  required String? formId,
  required VoidCallback? onSubmit,
}) {
  if (formId == null || formId.isEmpty || onSubmit == null) {
    return;
  }

  final existingBridge = _browserSubmitForms[formId];
  if (existingBridge != null) {
    existingBridge.refCount++;
    existingBridge.onSubmit = onSubmit;
    return;
  }

  final form = web.document.createElement('form') as web.HTMLFormElement;
  form.id = formId;
  form.noValidate = true;
  final style = form.style;
  style.position = 'fixed';
  style.width = '0';
  style.height = '0';
  style.opacity = '0';
  style.pointerEvents = 'none';
  style.overflow = 'hidden';
  style.inset = '0';

  final submitButton =
      web.document.createElement('button') as web.HTMLButtonElement;
  submitButton.type = 'submit';
  submitButton.tabIndex = -1;
  submitButton.textContent = 'submit';
  submitButton.setAttribute('aria-hidden', 'true');
  form.appendChild(submitButton);

  late final _BrowserSubmitFormBridge bridge;
  final submitListener = ((web.Event event) {
    event.preventDefault();
    bridge.onSubmit();
  }).toJS;

  bridge = _BrowserSubmitFormBridge(
    form: form,
    submitListener: submitListener,
    onSubmit: onSubmit,
  )..refCount = 1;

  form.addEventListener('submit', submitListener);
  web.document.body?.appendChild(form);
  _browserSubmitForms[formId] = bridge;
}

void _disposeBrowserSubmitForm({
  required String? formId,
  required VoidCallback? onSubmit,
}) {
  if (formId == null || formId.isEmpty || onSubmit == null) {
    return;
  }

  final bridge = _browserSubmitForms[formId];
  if (bridge == null) {
    return;
  }

  bridge.refCount--;
  if (bridge.refCount > 0) {
    return;
  }

  bridge.form.removeEventListener('submit', bridge.submitListener);
  bridge.form.remove();
  _browserSubmitForms.remove(formId);
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
  background-color: transparent !important;
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
