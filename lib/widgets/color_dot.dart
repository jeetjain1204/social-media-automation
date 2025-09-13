import 'package:blob/utils/colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ColorDot extends StatefulWidget {
  const ColorDot({
    super.key,
    required this.color,
    required this.label,
    required this.onTap,
  });

  final String? color;
  final String label;
  final VoidCallback onTap;

  @override
  State<ColorDot> createState() => _ColorDotState();
}

class _ColorDotState extends State<ColorDot> {
  bool isFocused = false;
  bool isHovered = false;

  static const _dotSize = 28.0; // OPT: reuse constant size
  static const _animDuration = Duration(milliseconds: 150);

  @override
  Widget build(BuildContext context) {
    final parsedColor = widget.color != null
        ? Color(int.parse(widget.color!.replaceFirst('#', '0xFF')))
        : lightColor.withOpacity(0.3);

    return RepaintBoundary(
      // OPT: isolate hover animation from parent repaints
      child: Semantics(
        label: widget.label,
        button: true,
        child: Focus(
          onFocusChange: (focused) {
            if (focused != isFocused) {
              setState(() => isFocused = focused); // OPT: skip redundant builds
            }
          },
          onKey: (node, event) {
            if (event.isKeyPressed(LogicalKeyboardKey.enter) ||
                event.isKeyPressed(LogicalKeyboardKey.space)) {
              widget.onTap();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) {
              if (!isHovered) setState(() => isHovered = true);
            },
            onExit: (_) {
              if (isHovered) setState(() => isHovered = false);
            },
            child: Tooltip(
              message: widget.label,
              waitDuration: const Duration(milliseconds: 200),
              child: GestureDetector(
                onTap: widget.onTap,
                onTapDown: (_) {
                  if (!isHovered) setState(() => isHovered = true);
                },
                onTapUp: (_) {
                  if (isHovered) setState(() => isHovered = false);
                },
                child: AnimatedScale(
                  duration: _animDuration,
                  scale: (isHovered || isFocused) ? 1.1 : 1.0,
                  child: Container(
                    width: _dotSize,
                    height: _dotSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: parsedColor,
                      border: Border.all(
                        width: 1,
                        color: lightColor.withOpacity(0.5),
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
}
