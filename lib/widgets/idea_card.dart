import 'package:blob/utils/colors.dart';
import 'package:flutter/material.dart';

class IdeaCard extends StatefulWidget {
  const IdeaCard({
    super.key,
    required this.width,
    required this.text,
    required this.isSelected,
    required this.onTap,
    required this.onMarkUsed,
    this.source,
  });

  final double width;
  final String text;
  final String? source;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onMarkUsed;

  @override
  State<IdeaCard> createState() => _IdeaCardState();
}

class _IdeaCardState extends State<IdeaCard> {
  bool isHovered = false;
  bool isFocused = false;

  // OPT: Re-use objects instead of rebuilding each frame
  static const _containerDuration = Duration(milliseconds: 200);
  static const _iconScaleDuration = Duration(milliseconds: 150);

  @override
  Widget build(BuildContext context) {
    final borderColor =
        widget.isSelected ? darkColor : lightColor.withOpacity(0.5);
    final bgColor =
        widget.isSelected ? lightColor.withOpacity(0.25) : Colors.white;
    final sourceColor = darkColor.withOpacity(0.5);

    return Focus(
      onFocusChange: (focus) {
        if (focus != isFocused) setState(() => isFocused = focus); // OPT: guard
      },
      child: Semantics(
        label: 'Idea: ${widget.text}',
        button: true,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) {
            if (!isHovered) setState(() => isHovered = true);
          },
          onExit: (_) {
            if (isHovered) setState(() => isHovered = false);
          },
          child: GestureDetector(
            onTap: widget.onTap,
            child: RepaintBoundary(
              // OPT: isolate hover/scale animation
              child: AnimatedContainer(
                duration: _containerDuration,
                margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: bgColor,
                  border: Border.all(
                    color: borderColor,
                    width: widget.isSelected ? 2 : 1,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // ------- Text & optional source -----------
                    SizedBox(
                      width: widget.width * 0.66,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.text,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              height: 1.5,
                              color: darkColor,
                            ),
                          ),
                          if (widget.source != null &&
                              widget.source!.trim().isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                '- ${widget.source}',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontStyle: FontStyle.italic,
                                  color: sourceColor,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),

                    // ------- Delete / Mark-used button --------
                    AnimatedScale(
                      duration: _iconScaleDuration,
                      scale: (isHovered || isFocused) ? 1.1 : 1.0,
                      child: IconButton(
                        onPressed: widget.onMarkUsed,
                        tooltip: 'Delete Idea',
                        icon: const Icon(
                          Icons.cancel_outlined,
                          size: 20,
                          color: Colors.red,
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
