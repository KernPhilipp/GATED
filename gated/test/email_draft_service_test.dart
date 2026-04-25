import 'package:flutter_test/flutter_test.dart';
import 'package:gated/services/email_draft_service.dart';

void main() {
  test('email draft URI encodes spaces without plus signs', () {
    final uri = EmailDraft(
      to: 'user@example.com',
      subject: 'GATED Passwort zuruecksetzen',
      body: 'Sehr geehrte Damen und Herren,\n\nVielen Dank.',
    ).toUri();

    expect(
      uri.toString(),
      contains('subject=GATED%20Passwort%20zuruecksetzen'),
    );
    expect(
      uri.toString(),
      contains('body=Sehr%20geehrte%20Damen%20und%20Herren'),
    );
    expect(uri.toString(), isNot(contains('+')));
  });
}
