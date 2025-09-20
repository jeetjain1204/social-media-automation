import 'package:blob/utils/colors.dart';
import 'package:blob/widgets/my_slider.dart';
import 'package:blob/widgets/my_switch.dart';
import 'package:blob/widgets/my_textfield.dart';
import 'package:flutter/material.dart';

class EditWithLabelContainer extends StatefulWidget {
  const EditWithLabelContainer({
    super.key,
    required this.width,
    required this.label,
    required this.child,
    this.switchBool,
    this.onChanged,
    this.description,
  });

  final double width;
  final String label;
  final Widget child;
  final bool? switchBool;
  final ValueChanged<bool>? onChanged;
  final String? description;

  @override
  State<EditWithLabelContainer> createState() => _EditWithLabelContainerState();
}

class _EditWithLabelContainerState extends State<EditWithLabelContainer> {
  bool isHovering = false;
  bool isFocused = false;

  // OPT: Static constants avoid repeated allocations.
  static const _outerAnimDuration = Duration(milliseconds: 180);
  static const _iconAnimDuration = Duration(milliseconds: 150);
  static const _titleStyle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w500,
    color: darkColor, // cannot be const but matches style token
  );

  @override
  Widget build(BuildContext context) {
    final bool hasContent =
        widget.child is! SizedBox && widget.child is! Container;

    return Semantics(
      label: widget.label,
      child: AnimatedContainer(
        duration: _outerAnimDuration, // OPT: reuse constant
        width: widget.width,
        decoration: BoxDecoration(
          color: lightColor.withOpacity(0.08),
          border: Border.all(
            width: 1,
            color: lightColor.withOpacity(0.2),
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        padding: const EdgeInsets.all(16),
        margin: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text(widget.label, style: _titleStyle),
                    if (widget.description != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: RepaintBoundary(
                          // OPT: isolate hover anim
                          child: Focus(
                            onFocusChange: (f) {
                              if (f != isFocused) {
                                setState(() => isFocused = f);
                              }
                            },
                            child: MouseRegion(
                              cursor: SystemMouseCursors.help,
                              onEnter: (_) {
                                if (!isHovering) {
                                  setState(() => isHovering = true);
                                }
                              },
                              onExit: (_) {
                                if (isHovering) {
                                  setState(() => isHovering = false);
                                }
                              },
                              child: Tooltip(
                                message: widget.description!,
                                waitDuration: const Duration(milliseconds: 200),
                                child: Semantics(
                                  label: widget.description,
                                  child: AnimatedScale(
                                    duration: _iconAnimDuration,
                                    scale:
                                        (isHovering || isFocused) ? 1.1 : 1.0,
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

                // ---- Right-side control ---------------------------------
                if (widget.switchBool != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: MySwitch(
                      value: widget.switchBool!,
                      onChanged: widget.onChanged,
                    ),
                  )
                else if (hasContent &&
                    widget.child is! MySlider &&
                    widget.child is! MyTextField)
                  widget.child
                else
                  const SizedBox.shrink(),
              ],
            ),

            // ---- Inline slider / textfield when switch absent OR true ----
            if (hasContent &&
                widget.switchBool != null &&
                (widget.child is MySlider || widget.child is MyTextField))
              const SizedBox(height: 12),

            if (hasContent &&
                widget.switchBool == null &&
                (widget.child is MySlider || widget.child is MyTextField))
              widget.child,
          ],
        ),
      ),
    );
  }
}
