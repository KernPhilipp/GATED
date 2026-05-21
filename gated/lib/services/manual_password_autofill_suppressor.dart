import 'manual_password_autofill_suppressor_stub.dart'
    if (dart.library.html) 'manual_password_autofill_suppressor_web.dart'
    as impl;

abstract class ManualPasswordAutofillSuppressor {
  const ManualPasswordAutofillSuppressor.internal();

  factory ManualPasswordAutofillSuppressor() =
      impl.ManualPasswordAutofillSuppressorImpl;

  void install();

  void dispose();
}
