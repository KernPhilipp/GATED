import 'email_draft_launcher.dart';

class EmailDraft {
  const EmailDraft({
    required this.to,
    required this.subject,
    required this.body,
  });

  final String to;
  final String subject;
  final String body;

  Uri toUri() {
    return Uri(
      scheme: 'mailto',
      path: to,
      queryParameters: {'subject': subject, 'body': body},
    );
  }
}

class EmailDraftService {
  const EmailDraftService();

  Future<bool> openDraft(EmailDraft draft) {
    return launchEmailDraft(draft.toUri());
  }
}
