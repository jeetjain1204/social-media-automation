import 'package:blob/utils/colors.dart';
import 'package:flutter/material.dart';

class ControlTool extends StatefulWidget {
  const ControlTool({
    super.key,
    required this.title,
    required this.child,
    this.description,
  });

  final Widget child;
  final String title;
  final String? description;

  @override
  State<ControlTool> createState() => _ControlToolState();
}

class _ControlToolState extends State<ControlTool> {
  bool isHovering = false;
  bool isFocused = false;

  // OPT: Static values avoid repeated object creation
  static const _titleStyle = TextStyle(
    fontSize: 16, // --font-body
    fontWeight: FontWeight.w500,
    color: Colors.black,
  );
  static const _animDuration = Duration(milliseconds: 150);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (widget.title.isNotEmpty)
              Text(widget.title, style: _titleStyle), // OPT: const style

            if (widget.description != null)
              Padding(
                padding: const EdgeInsets.only(left: 8), // --space-2
                child: RepaintBoundary(
                  // OPT: isolate hover animation
                  child: Focus(
                    onFocusChange: (f) {
                      if (f != isFocused) {
                        setState(() => isFocused = f); // OPT: guard setState
                      }
                    },
                    child: MouseRegion(
                      cursor: SystemMouseCursors.help,
                      onEnter: (_) {
                        if (!isHovering) setState(() => isHovering = true);
                      },
                      onExit: (_) {
                        if (isHovering) setState(() => isHovering = false);
                      },
                      child: Tooltip(
                        message: widget.description!,
                        waitDuration: const Duration(milliseconds: 200),
                        child: Semantics(
                          label: widget.description,
                          child: AnimatedScale(
                            duration: _animDuration,
                            scale: (isHovering || isFocused) ? 1.1 : 1.0,
                            child: Icon(
                              Icons.help_outline,
                              size: 18,
                              color: darkColor.withOpacity(0.5),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12), // --space-3
        widget.child,
        const SizedBox(height: 24), // --space-6
      ],
    );
  }
}
