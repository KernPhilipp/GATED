import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

VoidCallback listenForAutofillPageReturn(VoidCallback onReturn) {
  void scheduleReturnCallback() {
    Timer.run(onReturn);
  }

  void handleWindowReturn(web.Event _) {
    scheduleReturnCallback();
  }

  void handleVisibilityChange(web.Event _) {
    if (web.document.visibilityState == 'visible') {
      scheduleReturnCallback();
    }
  }

  final focusListener = handleWindowReturn.toJS;
  final pageshowListener = handleWindowReturn.toJS;
  final visibilityListener = handleVisibilityChange.toJS;

  web.window.addEventListener('focus', focusListener);
  web.window.addEventListener('pageshow', pageshowListener);
  web.document.addEventListener('visibilitychange', visibilityListener);

  return () {
    web.window.removeEventListener('focus', focusListener);
    web.window.removeEventListener('pageshow', pageshowListener);
    web.document.removeEventListener('visibilitychange', visibilityListener);
  };
}

String? readAutofillDomValue(List<String> browserHints) {
  final hints = browserHints.map((hint) => hint.toLowerCase()).toSet();
  if (hints.isEmpty) {
    return null;
  }

  String? lastNonEmptyValue;
  final inputs = web.document.querySelectorAll('input');
  for (var i = 0; i < inputs.length; i++) {
    final node = inputs.item(i);
    if (node == null || !node.isA<web.HTMLInputElement>()) {
      continue;
    }

    final input = node as web.HTMLInputElement;
    if (!_matchesAutofillHint(input, hints)) {
      continue;
    }

    final value = input.value;
    if (value.isNotEmpty) {
      lastNonEmptyValue = value;
    }
  }

  return lastNonEmptyValue;
}

bool _matchesAutofillHint(
  web.HTMLInputElement input,
  Set<String> browserHints,
) {
  final autocomplete = input.autocomplete.toLowerCase();
  final name = input.name.toLowerCase();
  final id = input.id.toLowerCase();
  return browserHints.contains(autocomplete) ||
      browserHints.contains(name) ||
      browserHints.contains(id);
}
