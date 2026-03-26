import 'package:flutter/material.dart';

import '../../services/auth_service.dart';

Future<void> redirectToLoginAfterSessionExpired(
  BuildContext context, {
  required AuthService authService,
  required String message,
}) async {
  await authService.clearToken();

  if (!context.mounted) {
    return;
  }

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

  if (!context.mounted) {
    return;
  }

  Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
}
