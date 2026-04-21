import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'autofill_focus_events.dart';

mixin AutofillFocusRecovery<T extends StatefulWidget> on State<T> {
  static const Duration _focusRecoveryWindow = Duration(seconds: 60);
  static const Duration _autofillDetectionWindow = Duration(seconds: 5);
  static const Duration _domSyncInterval = Duration(milliseconds: 150);
  static const Duration _domSyncWindow = Duration(seconds: 3);

  final Set<FocusNode> _registeredFocusNodes = <FocusNode>{};
  final Map<TextEditingController, String> _controllerValues =
      <TextEditingController, String>{};
  final Map<TextEditingController, FocusNode?> _controllerFocusNodes =
      <TextEditingController, FocusNode?>{};
  final Map<TextEditingController, VoidCallback?> _autofillCallbacks =
      <TextEditingController, VoidCallback?>{};
  final Map<TextEditingController, List<String>> _controllerBrowserHints =
      <TextEditingController, List<String>>{};

  FocusNode? _lastInteractedFocusNode;
  DateTime? _lastInteractionAt;
  FocusNode? _pendingRecoveryFocusNode;
  VoidCallback? _disposePageReturnListener;
  Timer? _domSyncTimer;
  DateTime? _domSyncUntil;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      _disposePageReturnListener = listenForAutofillPageReturn(
        _handlePageReturn,
      );
    }
  }

  @override
  void dispose() {
    _domSyncTimer?.cancel();
    _disposePageReturnListener?.call();
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
      }
    });
  }

  @protected
  void registerAutofillController(
    TextEditingController controller, {
    FocusNode? focusNode,
    List<String> browserAutofillHints = const [],
    VoidCallback? onAutofillDetected,
  }) {
    _controllerValues[controller] = controller.text;
    _controllerFocusNodes[controller] = focusNode;
    _autofillCallbacks[controller] = onAutofillDetected;
    _controllerBrowserHints[controller] = browserAutofillHints;

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
    _pendingRecoveryFocusNode = focusNode;
    _startDomAutofillSync(_focusRecoveryWindow);
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

  void _handlePageReturn() {
    if (!kIsWeb || !mounted) {
      return;
    }

    final focusNode = _pendingRecoveryFocusNode ?? _lastInteractedFocusNode;
    if (focusNode == null ||
        !_isWithinInteractionWindow(_focusRecoveryWindow)) {
      return;
    }

    _lastInteractionAt = DateTime.now();
    _pendingRecoveryFocusNode = focusNode;
    _startDomAutofillSync(_domSyncWindow);
  }

  void _startDomAutofillSync(Duration duration) {
    _domSyncUntil = DateTime.now().add(duration);
    _syncDomAutofillValues();
    _domSyncTimer ??= Timer.periodic(_domSyncInterval, (_) {
      final syncUntil = _domSyncUntil;
      if (syncUntil == null || DateTime.now().isAfter(syncUntil)) {
        _domSyncTimer?.cancel();
        _domSyncTimer = null;
        return;
      }

      _syncDomAutofillValues();
    });
  }

  void _syncDomAutofillValues() {
    if (!kIsWeb || !mounted) {
      return;
    }

    for (final entry in _controllerBrowserHints.entries) {
      final controller = entry.key;
      final domValue = readAutofillDomValue(entry.value);
      if (domValue == null || domValue.isEmpty || domValue == controller.text) {
        continue;
      }

      controller.value = TextEditingValue(
        text: domValue,
        selection: TextSelection.collapsed(offset: domValue.length),
      );
    }
  }
}
