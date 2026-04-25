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
    final query = {'subject': subject, 'body': body}.entries
        .map((entry) {
          final key = Uri.encodeComponent(entry.key);
          final value = Uri.encodeComponent(entry.value);
          return '$key=$value';
        })
        .join('&');

    return Uri(scheme: 'mailto', path: to, query: query);
  }
}

class EmailDraftService {
  const EmailDraftService();

  Future<bool> openDraft(EmailDraft draft) {
    return launchEmailDraft(draft.toUri());
  }
}
