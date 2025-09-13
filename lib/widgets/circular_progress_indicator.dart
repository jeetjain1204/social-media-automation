import 'package:blob/utils/colors.dart';
import 'package:flutter/material.dart';

class MyCircularProgressIndicator extends StatelessWidget {
  const MyCircularProgressIndicator({super.key, this.size, this.color});

  final double? size;
  final Color? color;

  static const _strokeWidth = 3.0; // OPT: reuse constant to avoid new doubles

  @override
  Widget build(BuildContext context) {
    final indicator = CircularProgressIndicator(
      color: color ?? darkColor,
      strokeCap: StrokeCap.round,
      strokeWidth: _strokeWidth,
    );

    final spinnerWidget = size != null
        ? SizedBox(
            width: size,
            height: size,
            child: Center(child: indicator),
          )
        : Center(child: indicator);

    // OPT: Removed AnimatedOpacity (opacity never changes) → less compositing cost
    // OPT: Added RepaintBoundary so the spinning animation doesn’t repaint ancestors
    return Semantics(
      label: 'Loading...',
      child: RepaintBoundary(child: spinnerWidget),
    );
  }
}
