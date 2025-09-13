import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:blob/widgets/circular_progress_indicator.dart';
import 'package:blob/utils/colors.dart';

class MyButton extends StatefulWidget {
  const MyButton({
    super.key,
    required this.width,
    required this.text,
    required this.onTap,
    required this.isLoading,
    this.height,
    this.padding,
    this.margin,
    this.borderRadius,
  });

  final double width;
  final double? height;
  final String text;
  final VoidCallback? onTap;
  final bool isLoading;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? borderRadius;

  @override
  State<MyButton> createState() => _MyButtonState();
}

class _MyButtonState extends State<MyButton> {
  bool isHovering = false;
  bool isFocused = false;
  bool isPressed = false;

  static const _animDuration = Duration(milliseconds: 160);

  @override
  Widget build(BuildContext context) {
    final height = widget.height ?? 50.0;
    final radius = widget.borderRadius ?? 16.0;

    // One switch to rule them all
    final interactive = !widget.isLoading && widget.onTap != null;

    // Derived, gated states
    final hovering = interactive && isHovering;
    final pressed = interactive && isPressed;

    return Focus(
      onFocusChange: (f) {
        if (f != isFocused) setState(() => isFocused = f);
      },
      child: MouseRegion(
        cursor:
            interactive ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (_) {
          if (!interactive) return;
          if (!isHovering) setState(() => isHovering = true);
        },
        onExit: (_) {
          if (!interactive) return;
          if (isHovering) setState(() => isHovering = false);
        },
        child: Semantics(
          label: widget.isLoading ? 'Loading' : widget.text,
          button: true,
          enabled: interactive,
          child: GestureDetector(
            onTap: interactive ? widget.onTap : null,
            onTapDown: (_) {
              if (!interactive) return;
              if (!isPressed) setState(() => isPressed = true);
            },
            onTapUp: (_) {
              if (!interactive) return;
              if (isPressed) setState(() => isPressed = false);
            },
            onTapCancel: () {
              if (!interactive) return;
              if (isPressed) setState(() => isPressed = false);
            },
            child: RepaintBoundary(
              child: Transform(
                alignment: Alignment.center,
                transform: _buildTransform(
                  hovering: hovering,
                  pressed: pressed,
                ),
                child: AnimatedContainer(
                  duration: _animDuration,
                  curve: Curves.easeOut,
                  width: widget.width,
                  height: height,
                  margin: widget.margin,
                  padding: widget.padding ??
                      const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: darkColor,
                    borderRadius: BorderRadius.circular(radius),
                    boxShadow:
                        hovering ? _buildHoverShadow() : const <BoxShadow>[],
                  ),
                  child: widget.isLoading
                      ? MyCircularProgressIndicator(
                          size: height * 0.5,
                          color: Colors.white,
                        )
                      : Center(
                          child: Text(
                            widget.text,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(
                              fontSize: height * 0.4,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Matrix4 _buildTransform({required bool hovering, required bool pressed}) {
    if (pressed && hovering) {
      return (Matrix4.identity()
        ..translate(0.0, -2.0)
        ..scale(0.96));
    }
    if (pressed) {
      return (Matrix4.identity()..scale(0.96));
    }
    if (hovering) {
      return Matrix4.translationValues(0, -2, 0);
    }
    return Matrix4.identity();
  }

  List<BoxShadow> _buildHoverShadow() => <BoxShadow>[
        BoxShadow(
          color: darkColor.withOpacity(0.25),
          blurRadius: 8,
          offset: const Offset(0, 4),
        ),
      ];
}
