import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'manual_password_autofill_suppressor.dart';

class ManualPasswordAutofillSuppressorImpl
    extends ManualPasswordAutofillSuppressor {
  ManualPasswordAutofillSuppressorImpl() : super.internal();

  JSExportedDartFunction? _focusInListener;

  @override
  void install() {
    if (_focusInListener != null) {
      return;
    }

    _focusInListener = _handleFocusIn.toJS;
    web.document.addEventListener('focusin', _focusInListener);
    _suppressExistingPasswordInputs();
  }

  @override
  void dispose() {
    final focusInListener = _focusInListener;
    if (focusInListener == null) {
      return;
    }

    web.document.removeEventListener('focusin', focusInListener);
    _focusInListener = null;
  }

  void _handleFocusIn(web.Event event) {
    final target = event.target;
    if (target != null && target.isA<web.HTMLInputElement>()) {
      _suppressPasswordInput(target as web.HTMLInputElement);
      return;
    }

    _suppressExistingPasswordInputs();
  }

  void _suppressExistingPasswordInputs() {
    final inputs = web.document.querySelectorAll('input');
    for (var index = 0; index < inputs.length; index++) {
      final node = inputs.item(index);
      if (node != null && node.isA<web.HTMLInputElement>()) {
        _suppressPasswordInput(node as web.HTMLInputElement);
      }
    }
  }

  void _suppressPasswordInput(web.HTMLInputElement input) {
    if (input.type.toLowerCase() != 'password') {
      return;
    }

    input.autocomplete = 'new-password';
    input.name = 'gated-manual-secret';
    input.id = 'gated-manual-secret';
    input.setAttribute('autocomplete', 'new-password');
    input.setAttribute('name', 'gated-manual-secret');
    input.setAttribute('id', 'gated-manual-secret');
    input.setAttribute('data-lpignore', 'true');
    input.setAttribute('data-1p-ignore', 'true');
    input.setAttribute('data-bwignore', 'true');
    input.setAttribute('data-form-type', 'other');
  }
}
