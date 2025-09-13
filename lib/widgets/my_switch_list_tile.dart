import 'package:blob/utils/colors.dart';
import 'package:blob/widgets/my_switch.dart';
import 'package:flutter/material.dart';

class MySwitchListTile extends StatelessWidget {
  const MySwitchListTile({
    super.key,
    required this.width,
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final double width;
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  // OPT: static constants = no per-build allocation
  static const _tilePadding = EdgeInsets.symmetric(
    horizontal: 16,
    vertical: 12,
  );
  static const _tileMargin = EdgeInsets.symmetric(vertical: 8);
  static const _animDuration = Duration(milliseconds: 200);
  static const _titleStyle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w500,
    color: Colors.black,
  );

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: '$title toggle',
      value: value ? 'On' : 'Off',
      button: true,
      toggled: value,
      child: RepaintBoundary(
        // OPT: isolate anim
        child: Container(
          width: width,
          decoration: BoxDecoration(
            color: lightColor.withOpacity(0.08),
            border: Border.all(color: lightColor.withOpacity(0.2), width: 1),
            borderRadius: BorderRadius.circular(16),
          ),
          padding: _tilePadding,
          margin: _tileMargin,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Tooltip(
                message: 'Toggle $title',
                child: Text(title, style: _titleStyle), // OPT: const text
              ),
              GestureDetector(
                onTap: () => onChanged(!value),
                child: AnimatedScale(
                  scale: value ? 1.05 : 1.0,
                  duration: _animDuration,
                  child: MySwitch(value: value, onChanged: onChanged),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
