import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

mixin AutofillFocusRecovery<T extends StatefulWidget> on State<T> {
  static const Duration _focusRecoveryDelay = Duration(milliseconds: 180);
  static const Duration _focusRecoveryWindow = Duration(seconds: 5);

  AppLifecycleListener? _appLifecycleListener;
  FocusNode? _lastInteractedFocusNode;
  DateTime? _lastInteractionAt;
  Timer? _restoreTimer;

  @override
  void initState() {
    super.initState();
    _appLifecycleListener = AppLifecycleListener(
      onResume: _handleAppResumed,
    );
  }

  @override
  void dispose() {
    _restoreTimer?.cancel();
    _appLifecycleListener?.dispose();
    super.dispose();
  }

  @protected
  void registerAutofillFocusNode(FocusNode focusNode) {
    focusNode.addListener(() {
      if (focusNode.hasFocus) {
        markAutofillInteraction(focusNode);
      }
    });
  }

  @protected
  void markAutofillInteraction(FocusNode focusNode) {
    if (!kIsWeb) {
      return;
    }

    _lastInteractedFocusNode = focusNode;
    _lastInteractionAt = DateTime.now();
  }

  void _handleAppResumed() {
    if (!kIsWeb) {
      return;
    }

    final targetFocusNode = _lastInteractedFocusNode;
    final interactionAt = _lastInteractionAt;
    if (!mounted ||
        targetFocusNode == null ||
        interactionAt == null ||
        targetFocusNode.hasFocus) {
      return;
    }

    final elapsed = DateTime.now().difference(interactionAt);
    if (elapsed > _focusRecoveryWindow) {
      return;
    }

    _restoreTimer?.cancel();
    _restoreTimer = Timer(_focusRecoveryDelay, () {
      if (!mounted || targetFocusNode.hasFocus) {
        return;
      }

      FocusScope.of(context).requestFocus(targetFocusNode);
    });
  }
}
