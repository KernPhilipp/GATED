import 'package:flutter/foundation.dart';

import 'autofill_focus_events_stub.dart'
    if (dart.library.html) 'autofill_focus_events_web.dart'
    as impl;

VoidCallback listenForAutofillPageReturn(VoidCallback onReturn) {
  return impl.listenForAutofillPageReturn(onReturn);
}

String? readAutofillDomValue(List<String> browserHints) {
  return impl.readAutofillDomValue(browserHints);
}
