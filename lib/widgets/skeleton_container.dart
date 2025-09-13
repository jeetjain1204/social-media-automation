import 'package:flutter/material.dart';
import 'package:blob/utils/colors.dart';

class MySkeletonContainer extends StatefulWidget {
  const MySkeletonContainer({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = 24,
    this.baseColor,
    this.effectColor,
    this.duration = const Duration(milliseconds: 1200),
    this.isLoading = true,
    this.margin,
    this.padding,
    this.highlightWidthFactor = 0.35, // 0–1
  });

  final double width;
  final double height;
  final double borderRadius;
  final Color? baseColor; // defaults to lightColor
  final Color? effectColor; // defaults to darkColor
  final Duration duration;
  final bool isLoading;
  final EdgeInsetsGeometry? margin;
  final EdgeInsetsGeometry? padding;
  final double highlightWidthFactor;

  @override
  MySkeletonContainerState createState() => MySkeletonContainerState();
}

class MySkeletonContainerState extends State<MySkeletonContainer>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller;
  late final Animation<double> slide;

  @override
  void initState() {
    super.initState();
    controller = AnimationController(vsync: this, duration: widget.duration);
    slide = Tween<double>(
      begin: -1,
      end: 1,
    ).animate(CurvedAnimation(parent: controller, curve: Curves.linear));
    controller.repeat();
  }

  @override
  void didUpdateWidget(covariant MySkeletonContainer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.duration != widget.duration) {
      controller.duration = widget.duration;
      controller
        ..reset()
        ..repeat();
    }
    if (!widget.isLoading) controller.stop();
    if (widget.isLoading && !controller.isAnimating) controller.repeat();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = widget.baseColor ?? lightColor;
    final effect = widget.effectColor ?? darkColor;

    return Container(
      width: widget.width,
      height: widget.height,
      margin: widget.margin,
      padding: widget.padding,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Base layer
            Container(color: base),
            // Shimmer sweep
            AnimatedBuilder(
              animation: slide,
              builder: (context, _) {
                return Align(
                  alignment: Alignment(slide.value, 0),
                  child: FractionallySizedBox(
                    widthFactor: widget.highlightWidthFactor.clamp(0.05, 1.0),
                    heightFactor: 1,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            Colors.transparent,
                            effect.withOpacity(0.30),
                            effect.withOpacity(0.50),
                            effect.withOpacity(0.30),
                            Colors.transparent,
                          ],
                          stops: const [0.0, 0.35, 0.50, 0.65, 1.0],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
