import 'package:web/web.dart' as web;

Future<bool> openMailtoFallback(Uri uri) async {
  web.window.open(uri.toString(), '_self');
  return true;
}
