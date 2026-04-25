import 'dart:ui';

import 'package:flutter/material.dart';

class HorizontalTableScrollView extends StatefulWidget {
  const HorizontalTableScrollView({super.key, required this.child});

  final Widget child;

  @override
  State<HorizontalTableScrollView> createState() =>
      _HorizontalTableScrollViewState();
}

class _HorizontalTableScrollViewState extends State<HorizontalTableScrollView> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final behavior = ScrollConfiguration.of(context);

    return ScrollConfiguration(
      behavior: behavior.copyWith(
        dragDevices: {...behavior.dragDevices, PointerDeviceKind.mouse},
      ),
      child: Scrollbar(
        controller: _scrollController,
        thumbVisibility: true,
        trackVisibility: true,
        interactive: true,
        scrollbarOrientation: ScrollbarOrientation.bottom,
        child: SingleChildScrollView(
          controller: _scrollController,
          scrollDirection: Axis.horizontal,
          child: widget.child,
        ),
      ),
    );
  }
}
