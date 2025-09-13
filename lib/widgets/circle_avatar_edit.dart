import 'package:blob/utils/colors.dart';
import 'package:flutter/material.dart';

class CircleAvatarEdit extends StatefulWidget {
  const CircleAvatarEdit({
    super.key,
    required this.width,
    required this.onTap,
    this.icon,
    this.imageUrl,
    this.path,
  });

  final double width;
  final VoidCallback onTap; // OPT: use typedef already in Flutter
  final IconData? icon;
  final String? imageUrl;
  final String? path;

  @override
  State<CircleAvatarEdit> createState() => _CircleAvatarEditState();
}

// OPT: RepaintBoundary isolates the whole avatar from ancestor repaints.
class _CircleAvatarEditState extends State<CircleAvatarEdit> {
  bool isHoveringImage = false;
  bool isFocused = false;

  // OPT: Durations declared once to avoid new objects per frame.
  static const _animDuration = Duration(milliseconds: 200);

  @override
  Widget build(BuildContext context) {
    final double radius = widget.width * 0.05;
    final double iconSize = widget.width * 0.05;
    final double overlaySize = radius * 2;

    return RepaintBoundary(
      // ⬆ isolates hover/scale animations from the rest of the UI
      child: Semantics(
        label: 'Edit profile picture',
        button: true,
        child: Focus(
          onFocusChange: (focus) {
            if (focus != isFocused) {
              setState(() => isFocused = focus); // OPT: skip redundant builds
            }
          },
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) {
              if (!isHoveringImage) {
                setState(() => isHoveringImage = true);
              }
            },
            onExit: (_) {
              if (isHoveringImage) {
                setState(() => isHoveringImage = false);
              }
            },
            child: GestureDetector(
              onTap: widget.onTap,
              child: Tooltip(
                message: 'Click to change this photo',
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircleAvatar(
                      radius: radius,
                      backgroundColor: lightColor.withOpacity(0.5),
                      backgroundImage: widget.imageUrl != null
                          ? NetworkImage(widget.imageUrl!)
                          : null,
                      child: widget.imageUrl == null && !isHoveringImage
                          ? Icon(
                              widget.icon ?? Icons.camera_alt_outlined,
                              color: darkColor,
                              size: iconSize,
                            )
                          : null,
                    ),
                    // OPT: Combine opacity + scale using AnimatedScale + Opacity child
                    AnimatedScale(
                      duration: _animDuration,
                      scale: isHoveringImage || isFocused ? 1.0 : 0.8,
                      child: Opacity(
                        opacity: (isHoveringImage || isFocused) ? 1.0 : 0.0,
                        child: Container(
                          width: overlaySize,
                          height: overlaySize,
                          decoration: BoxDecoration(
                            color: darkColor.withOpacity(0.6),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.camera_alt_outlined,
                            color: Colors.white,
                            size: iconSize * 0.9,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
