import 'package:blob/utils/colors.dart';
import 'package:flutter/material.dart';

class MySwitch extends StatelessWidget {
  const MySwitch({super.key, required this.value, this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  // ---------- OPT: shared static helpers / constants ----------
  static const _animDuration = Duration(milliseconds: 150);

  static Color _thumbColor(Set<MaterialState> states) {
    if (states.contains(MaterialState.disabled)) {
      return lightColor.withOpacity(0.4);
    }
    if (states.contains(MaterialState.selected)) {
      return lightColor.withOpacity(0.8);
    }
    return darkColor;
  }

  static Color _trackColor(Set<MaterialState> states) {
    return states.contains(MaterialState.selected)
        ? darkColor
        : lightColor.withOpacity(0.3);
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      // OPT: isolate scale animation from ancestors
      child: Focus(
        child: Semantics(
          toggled: value,
          label: 'Toggle switch',
          value: value ? 'On' : 'Off',
          child: AnimatedScale(
            scale: value ? 1.05 : 1.0,
            duration: _animDuration,
            child: Switch(
              value: value,
              onChanged: onChanged,
              thumbColor: MaterialStateProperty.resolveWith(
                _thumbColor,
              ), // OPT: static resolver
              trackColor: MaterialStateProperty.resolveWith(
                _trackColor,
              ), // OPT: static resolver
              mouseCursor: SystemMouseCursors.click,
              focusColor: darkColor.withOpacity(0.2),
              hoverColor: Colors.transparent,
              splashRadius: 0,
            ),
          ),
        ),
      ),
    );
  }
}
