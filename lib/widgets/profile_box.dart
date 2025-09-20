import 'package:blob/utils/colors.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class ProfileBox extends StatelessWidget {
  const ProfileBox({
    super.key,
    required this.width,
    this.editPath,
    this.value,
    this.label,
    this.items,
  });

  final double width;
  final String? editPath;
  final String? label;
  final String? value;
  final List? items;

  // ---------- OPT: shared constants ----------
  static const _radius = 16.0;
  static const _outerPadding = EdgeInsets.symmetric(
    vertical: 12,
    horizontal: 16,
  );
  static const _outerMargin = EdgeInsets.symmetric(horizontal: 12);
  static const _labelStyle = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
  );
  static const _valueStyle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w500,
    color: darkColor,
  );
  static const _badgeTextStyle = TextStyle(
    color: Colors.white,
    fontWeight: FontWeight.w500,
    fontSize: 14,
  );

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Semantics(
        label: label ?? 'Profile box value',
        container: true,
        child: RepaintBoundary(
          // OPT: isolate hover/edits from list repaints
          child: Container(
            alignment: label != null ? Alignment.centerLeft : Alignment.center,
            decoration: BoxDecoration(
              color: lightColor.withOpacity(0.125),
              border: Border.all(color: lightColor.withOpacity(0.25), width: 1),
              borderRadius: BorderRadius.circular(_radius),
            ),
            padding: _outerPadding,
            margin: _outerMargin,
            child: Stack(
              alignment: Alignment.centerRight,
              children: [
                _buildContent(),
                if (editPath != null)
                  IconButton(
                    onPressed: () => context.go('$editPath?isEditing=true'),
                    icon: Icon(
                      Icons.edit_outlined,
                      color: darkColor.withOpacity(0.25),
                    ),
                    iconSize: 20,
                    splashRadius: 20,
                    tooltip: 'Edit',
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------- OPT: split content builder for clarity ----------
  Widget _buildContent() {
    if (label != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label!,
              style: _labelStyle.copyWith(
                color: darkColor.withOpacity(0.5),
              ),
            ),
            const SizedBox(height: 12),
            if (value != null)
              Text(value!, style: _valueStyle)
            else if (items != null)
              _buildItems()
            else
              const SizedBox.shrink(),
          ],
        ),
      );
    }
    if (value != null) {
      return Text(value!, style: _valueStyle);
    }
    return const SizedBox.shrink();
  }

  // ---------- OPT: reusable items/badges ----------
  Widget _buildItems() {
    const int visibleCount = 4;
    final total = items!.length;
    final bool hasExtra = total > visibleCount;
    final displayItems = hasExtra ? items!.sublist(0, visibleCount) : items!;
    final int extraCount = hasExtra ? total - visibleCount : 0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var item in displayItems)
          _buildChip(
            item.toString(),
          ),
        if (hasExtra) _buildExtraBadge(extraCount),
      ],
    );
  }

  Widget _buildChip(String text) {
    return Container(
      decoration: BoxDecoration(
        color: darkColor.withOpacity(0.95),
        border: Border.all(width: 0.5, color: darkColor),
        borderRadius: BorderRadius.circular(_radius),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      margin: const EdgeInsets.symmetric(horizontal: 4),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(text, style: _badgeTextStyle),
      ),
    );
  }

  Widget _buildExtraBadge(int extra) {
    return Container(
      decoration: BoxDecoration(
        color: darkColor,
        border: Border.all(width: 1, color: lightColor),
        shape: BoxShape.circle,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      margin: const EdgeInsets.symmetric(horizontal: 4),
      child: Center(
        child: Text(
          '+$extra',
          textAlign: TextAlign.center,
          style: _badgeTextStyle.copyWith(color: lightColor),
        ),
      ),
    );
  }
}
