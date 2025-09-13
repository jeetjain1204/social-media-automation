import 'package:blob/utils/colors.dart';
import 'package:flutter/material.dart';

class MySlider extends StatelessWidget {
  const MySlider({
    super.key,
    required this.min,
    required this.max,
    required this.divisions,
    required this.valueNotifier,
    required this.tooltip,
    this.enabled = true,
    this.onChanged,
  });

  final double min, max;
  final int divisions;
  final ValueNotifier<double> valueNotifier;
  final bool enabled;
  final String tooltip;
  final ValueChanged<double>? onChanged;

  // OPT: static - reuse one RegExp + avoid repeated allocations.
  static final _trailingZeros = RegExp(r'([.]*0+)(?!.*\d)');

  static String _formatValue(double value) {
    return ((value * 100).roundToDouble() / 100)
        .toStringAsFixed(2)
        .replaceAll(_trailingZeros, '');
  }

  // OPT: shared slider parts (const) to avoid rebuild allocations
  static const _thumbShape = RoundSliderThumbShape(enabledThumbRadius: 8);
  static const _overlayShape = RoundSliderOverlayShape(overlayRadius: 16);
  static const _valueIndicatorStyle = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: Colors.white,
  );

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      // OPT: isolate slider repaint from parent lists
      child: ValueListenableBuilder<double>(
        valueListenable: valueNotifier,
        builder: (_, value, __) {
          final formatted = _formatValue(value);

          return Tooltip(
            message: enabled ? 'Adjust $tooltip' : 'Slider is disabled',
            child: Semantics(
              label: 'Slider control',
              value: 'Current value: $formatted',
              increasedValue:
                  'Increase to ${_formatValue((value + 1).clamp(min, max))}',
              decreasedValue:
                  'Decrease to ${_formatValue((value - 1).clamp(min, max))}',
              enabled: enabled,
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 4,
                  thumbShape: _thumbShape, // OPT: const reuse
                  overlayShape: _overlayShape, // OPT: const reuse
                  valueIndicatorTextStyle: _valueIndicatorStyle,
                ),
                child: Slider(
                  min: min,
                  max: max,
                  divisions: divisions,
                  value: value,
                  label: formatted,
                  onChanged: enabled
                      ? (v) {
                          valueNotifier.value = v;
                          onChanged?.call(v);
                        }
                      : null,
                  activeColor: darkColor,
                  inactiveColor: darkColor.withOpacity(0.2),
                  thumbColor: lightColor,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
