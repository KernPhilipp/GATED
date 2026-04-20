import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

mixin AutofillFocusRecovery<T extends StatefulWidget> on State<T> {
  static const Duration _focusRecoveryDelay = Duration(milliseconds: 180);
  static const Duration _focusRecoveryWindow = Duration(milliseconds: 1500);
  static const Duration _autofillDetectionWindow = Duration(milliseconds: 900);

  final Set<FocusNode> _registeredFocusNodes = <FocusNode>{};
  final Map<TextEditingController, String> _controllerValues =
      <TextEditingController, String>{};
  final Map<TextEditingController, FocusNode?> _controllerFocusNodes =
      <TextEditingController, FocusNode?>{};
  final Map<TextEditingController, VoidCallback?> _autofillCallbacks =
      <TextEditingController, VoidCallback?>{};

  FocusNode? _lastInteractedFocusNode;
  DateTime? _lastInteractionAt;
  Timer? _restoreTimer;

  @override
  void dispose() {
    _restoreTimer?.cancel();
    super.dispose();
  }

  @protected
  void registerAutofillFocusNode(FocusNode focusNode) {
    if (!_registeredFocusNodes.add(focusNode)) {
      return;
    }

    focusNode.addListener(() {
      if (focusNode.hasFocus) {
        markAutofillInteraction(focusNode);
        return;
      }

      _scheduleFocusRecovery(focusNode);
    });
  }

  @protected
  void registerAutofillController(
    TextEditingController controller, {
    FocusNode? focusNode,
    VoidCallback? onAutofillDetected,
  }) {
    _controllerValues[controller] = controller.text;
    _controllerFocusNodes[controller] = focusNode;
    _autofillCallbacks[controller] = onAutofillDetected;

    controller.addListener(() {
      final previousValue = _controllerValues[controller] ?? '';
      final currentValue = controller.text;
      if (previousValue == currentValue) {
        return;
      }

      _controllerValues[controller] = currentValue;
      if (!_isLikelyAutofillChange(
        focusNode: focusNode,
        previousValue: previousValue,
        currentValue: currentValue,
      )) {
        return;
      }

      _autofillCallbacks[controller]?.call();
    });
  }

  @protected
  void markAutofillInteraction(FocusNode focusNode) {
    if (!kIsWeb) {
      return;
    }

    _lastInteractedFocusNode = focusNode;
    _lastInteractionAt = DateTime.now();
    _restoreTimer?.cancel();
  }

  bool _isLikelyAutofillChange({
    required FocusNode? focusNode,
    required String previousValue,
    required String currentValue,
  }) {
    if (!kIsWeb || !_isWithinInteractionWindow(_autofillDetectionWindow)) {
      return false;
    }

    final lengthDelta = (currentValue.length - previousValue.length).abs();
    final changedOutsideFocusedField =
        focusNode != null &&
        !focusNode.hasFocus &&
        currentValue != previousValue;

    return lengthDelta > 1 || changedOutsideFocusedField;
  }

  bool _isWithinInteractionWindow(Duration window) {
    final interactionAt = _lastInteractionAt;
    if (interactionAt == null) {
      return false;
    }

    return DateTime.now().difference(interactionAt) <= window;
  }

  void _scheduleFocusRecovery(FocusNode focusNode) {
    if (!kIsWeb ||
        !mounted ||
        _lastInteractedFocusNode != focusNode ||
        focusNode.hasFocus ||
        !_isWithinInteractionWindow(_focusRecoveryWindow)) {
      return;
    }

    _restoreTimer?.cancel();
    _restoreTimer = Timer(_focusRecoveryDelay, () {
      if (!mounted || focusNode.hasFocus || !focusNode.canRequestFocus) {
        return;
      }

      final hasTrackedFocus = _registeredFocusNodes.any(
        (node) => node.hasFocus,
      );
      if (hasTrackedFocus) {
        return;
      }

      FocusScope.of(context).requestFocus(focusNode);
    });
  }
}
