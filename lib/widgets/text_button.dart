import 'package:blob/utils/colors.dart';
import 'package:flutter/material.dart';

class MyTextButton extends StatelessWidget {
  const MyTextButton({
    super.key,
    required this.child,
    required this.onPressed,
    this.icon,
    this.gap = 6,
  });

  final Widget child;
  final void Function() onPressed;
  final Widget? icon; // let this be any widget, not just Icon
  final double gap;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      style: TextButton.styleFrom(
        foregroundColor: darkColor,
        backgroundColor: lightColor,
        elevation: 0,
        shadowColor: Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        minimumSize: const Size(0, 40), // no min width, 40px min height
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      onPressed: onPressed,
      child: Row(
        mainAxisSize: MainAxisSize.min, // <-- critical: shrink to content
        children: [
          if (icon != null) ...[icon!, SizedBox(width: gap)],
          child,
        ],
      ),
    );
  }
}
