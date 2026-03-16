const Set<String> allowedEmails = {
  'philipp.kern.student@htl-hallein.at',
  'tobi.halwax@icloud.com',
  'felix.haader.student@htl-hallein.at',
};

String normalizeEmail(String email) => email.trim().toLowerCase();

bool isEmailAllowed(String email) {
  final normalized = normalizeEmail(email);
  return allowedEmails.contains(normalized);
}
