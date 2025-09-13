import 'package:flutter/material.dart';

class SafeScrollbar extends StatefulWidget {
  const SafeScrollbar({
    super.key,
    required this.controller,
    required this.axis,
    required this.builder,
    this.thumbVisibleWhen,
  });

  final ScrollController controller;
  final Axis axis;
  final Widget Function(ScrollController controller) builder;
  final bool Function()? thumbVisibleWhen;

  @override
  State<SafeScrollbar> createState() => _SafeScrollbarState();
}

class _SafeScrollbarState extends State<SafeScrollbar> {
  late final VoidCallback _rebuild;

  @override
  void initState() {
    super.initState();
    _rebuild = () {
      if (mounted) setState(() {});
    };

    WidgetsBinding.instance.addPostFrameCallback((_) => _rebuild());
    widget.controller.addListener(_rebuild);
  }

  @override
  void didUpdateWidget(covariant SafeScrollbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_rebuild);
      widget.controller.addListener(_rebuild);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_rebuild);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final child = widget.builder(widget.controller);
    if (!widget.controller.hasClients) return child;
    return Scrollbar(
      controller: widget.controller,
      notificationPredicate: (n) => n.metrics.axis == widget.axis,
      thumbVisibility: widget.thumbVisibleWhen?.call() ?? false,
      child: child,
    );
  }
}
