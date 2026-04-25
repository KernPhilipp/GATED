import 'package:url_launcher/url_launcher.dart';

import 'email_draft_launcher_stub.dart'
    if (dart.library.html) 'email_draft_launcher_web.dart'
    as platform;

Future<bool> launchEmailDraft(Uri uri) async {
  try {
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (opened) {
      return true;
    }
  } catch (_) {
    // Fall through to the generic launcher and web fallback.
  }

  try {
    final opened = await launchUrl(uri);
    if (opened) {
      return true;
    }
  } catch (_) {
    // Fall through to the platform fallback.
  }

  return platform.openMailtoFallback(uri);
}
