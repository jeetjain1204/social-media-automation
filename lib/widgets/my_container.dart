import 'package:flutter/material.dart';
import 'package:blob/utils/colors.dart';

class MyContainer extends StatelessWidget {
  const MyContainer({
    super.key,
    required this.width,
    required this.child,
    this.padding,
    this.margin,
    this.color,
    this.borderColor,
    this.widgetShadowColor,
    this.semanticLabel,
  });

  final double width;
  final Widget child;
  final double? padding;
  final double? margin;
  final Color? color;
  final Color? borderColor;
  final Color? widgetShadowColor;
  final String? semanticLabel;

  // OPT: reuse constant instead of new object every build
  static const _animDuration = Duration(milliseconds: 200);

  @override
  Widget build(BuildContext context) {
    final double pad = padding ?? 16; // --space-4
    final double mar = margin ?? 12; // --space-3

    return Semantics(
      label: semanticLabel,
      container: true,
      child: RepaintBoundary(
        // OPT: isolates inner repaint
        child: AnimatedContainer(
          duration: _animDuration, // OPT: static const
          curve: Curves.easeOutCubic,
          width: width,
          margin: EdgeInsets.all(mar),
          padding: EdgeInsets.all(pad),
          decoration: BoxDecoration(
            color: color ?? whiteColor,
            borderRadius: BorderRadius.circular(16), // --radius-card
            border: Border.all(color: borderColor ?? grey200, width: 1),
            boxShadow: _buildShadow(), // OPT: helper avoids new list when none
          ),
          child: child,
        ),
      ),
    );
  }

  // OPT: returns const empty list when no shadow change → zero allocation
  List<BoxShadow> _buildShadow() {
    final Color effectiveShadowColor =
        widgetShadowColor ?? shadowColor.withOpacity(0.08);
    if (effectiveShadowColor.opacity == 0) return const <BoxShadow>[];
    return <BoxShadow>[
      BoxShadow(
        color: effectiveShadowColor,
        blurRadius: 4,
        offset: const Offset(0, 2),
      ),
    ];
  }
}
