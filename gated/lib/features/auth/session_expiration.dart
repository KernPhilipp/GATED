import 'package:flutter/material.dart';

import '../../services/auth_service.dart';

Future<void> redirectToLoginAfterSessionExpired(
  BuildContext context, {
  required AuthService authService,
  required String message,
  AuthSessionEndReason reason = AuthSessionEndReason.expired,
}) async {
  await authService.clearTokens(reason: reason);

  if (!context.mounted) {
    return;
  }

  if (reason == AuthSessionEndReason.expired) {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Sitzung abgelaufen'),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
              child: const Text('Zum Login'),
            ),
          ],
        );
      },
    );
  }

  if (!context.mounted) {
    return;
  }

  Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
}
