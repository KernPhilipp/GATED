import 'dart:async';
import 'package:flutter/material.dart';

final Expando<Timer> _snackBarTimers = Expando<Timer>('snackbar_timers');

void showAppSnackBar(
  BuildContext context, {
  required String message,
  bool isError = false,
  bool withCloseAction = false,
  Duration duration = const Duration(seconds: 3),
}) {
  final messenger = ScaffoldMessenger.of(context);
  final theme = Theme.of(context);

  _snackBarTimers[messenger]?.cancel();
  messenger.clearSnackBars();
  messenger.showSnackBar(
    SnackBar(
      content: Text(message),
      duration: duration,
      backgroundColor: isError ? theme.colorScheme.error : null,
      action: withCloseAction
          ? SnackBarAction(
              label: 'Schließen',
              textColor: isError ? theme.colorScheme.onError : null,
              onPressed: () {
                _snackBarTimers[messenger]?.cancel();
                messenger.hideCurrentSnackBar();
              },
            )
          : null,
    ),
  );

  _snackBarTimers[messenger] = Timer(duration, () {
    if (messenger.mounted) {
      messenger.hideCurrentSnackBar();
    }
  });
}
