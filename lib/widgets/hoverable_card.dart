import 'package:blob/utils/colors.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class HoverableCard extends StatefulWidget {
  const HoverableCard({
    super.key,
    required this.fatherProperty,
    required this.property,
    required this.onTap,
    this.isSelected = false,
    this.width,
    this.height,
  });

  final double? width;
  final double? height;
  final String fatherProperty;
  final String property;
  final VoidCallback onTap;
  final bool isSelected;

  @override
  State<HoverableCard> createState() => _HoverableCardState();
}

class _HoverableCardState extends State<HoverableCard> {
  bool isHovered = false;
  bool isFocused = false;

  // OPT: constants reused to avoid new object allocations
  static const _scaleDuration = Duration(milliseconds: 200);
  static const _containerDuration = Duration(milliseconds: 250);
  static const _iconSize = 14.0;
  static const _selectedBadgeSize = 24.0;

  @override
  Widget build(BuildContext context) {
    // OPT: compute once per build
    final borderColor = widget.isSelected
        ? darkColor
        : (isHovered
            ? darkColor.withOpacity(0.4)
            : lightColor.withOpacity(0.25));

    // OPT: pre-transform property name once
    final propertyKey = widget.property.replaceAll(RegExp(r'[ /\-]+'), '_');

    return Focus(
      onFocusChange: (focus) {
        if (focus != isFocused)
          setState(() => isFocused = focus); // OPT: guard setState
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) {
          if (!isHovered) setState(() => isHovered = true); // OPT: guard
        },
        onExit: (_) {
          if (isHovered) setState(() => isHovered = false);
        },
        child: Semantics(
          label: '${widget.property} option',
          button: true,
          child: GestureDetector(
            onTap: widget.onTap,
            child: RepaintBoundary(
              // OPT: isolate scaling & shadow anims
              child: AnimatedScale(
                scale: (isHovered || isFocused) ? 1.03 : 1.0,
                duration: _scaleDuration,
                curve: Curves.easeOutCubic,
                child: Stack(
                  alignment: Alignment.topRight,
                  children: [
                    AnimatedContainer(
                      width: widget.width,
                      height: widget.height,
                      padding: const EdgeInsets.all(16),
                      duration: _containerDuration,
                      curve: Curves.easeOutCubic,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: borderColor, width: 2),
                        boxShadow: isHovered
                            ? [
                                BoxShadow(
                                  color: darkColor.withOpacity(0.1),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                                BoxShadow(
                                  color: darkColor.withOpacity(0.06),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ]
                            : const [],
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final w = constraints.maxWidth;
                              return SizedBox(
                                width: w * 0.7,
                                height: w * 0.7,
                                child: AnimatedScale(
                                  scale: isHovered ? 1.1 : 1.0,
                                  duration: _containerDuration,
                                  curve: Curves.easeOutCubic,
                                  child: AspectRatio(
                                    aspectRatio: 1,
                                    child: Image.asset(
                                      kDebugMode
                                          ? 'icons/${widget.fatherProperty}/$propertyKey.png'
                                          : 'assets/icons/${widget.fatherProperty}/$propertyKey.png',
                                      fit: BoxFit.contain,
                                      excludeFromSemantics: true,
                                      errorBuilder: (_, __, ___) => Center(
                                        child: Icon(
                                          Icons.error_outline,
                                          size: 32,
                                          color: widget.isSelected
                                              ? darkColor
                                              : darkColor.withOpacity(0.6),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 12),
                          Text(
                            widget.property,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: widget.isSelected
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                              color: widget.isSelected
                                  ? darkColor
                                  : darkColor.withOpacity(isHovered ? 1 : 0.8),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (widget.isSelected)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: AnimatedScale(
                          scale: 1.15,
                          duration: _containerDuration,
                          curve: Curves.easeOutBack,
                          child: Container(
                            width: _selectedBadgeSize,
                            height: _selectedBadgeSize,
                            decoration: BoxDecoration(
                              color: darkColor,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.15),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.check,
                              color: Colors.white,
                              size: _iconSize,
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
