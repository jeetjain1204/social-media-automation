import 'package:blob/utils/colors.dart';
import 'package:flutter/material.dart';

class MyTextField extends StatefulWidget {
  const MyTextField({
    super.key,
    required this.width,
    required this.controller,
    required this.hintText,
    this.labelText,
    this.height,
    this.padding,
    this.margin,
    this.color,
    this.borderColor,
    this.shadowColor,
    this.enabled,
    this.type,
    this.onChanged,
    this.textInputAction,
    this.maxLength,
    this.errorText,
    this.autoFocus = false,
  });

  final double width;
  final double? height;
  final TextEditingController controller;
  final String hintText;
  final String? labelText;
  final double? padding;
  final double? margin;
  final Color? color;
  final Color? borderColor;
  final Color? shadowColor;
  final bool? enabled;
  final TextInputType? type;
  final TextInputAction? textInputAction;
  final int? maxLength;
  final String? errorText;
  final ValueChanged<String>? onChanged;
  final bool autoFocus;

  @override
  State<MyTextField> createState() => _MyTextFieldState();
}

class _MyTextFieldState extends State<MyTextField> {
  late final FocusNode _focusNode;
  bool _isFocused = false;

  // ---------- OPT: shared constants ----------
  static const _animDuration = Duration(milliseconds: 200);
  static const _radius = 16.0;
  static const _verticalPadding = 15.0;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(debugLabel: 'MyTextFieldFocus')
      ..addListener(_handleFocusChange);
  }

  void _handleFocusChange() {
    if (_focusNode.hasFocus != _isFocused) {
      setState(() => _isFocused = _focusNode.hasFocus);
    }
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_handleFocusChange)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled ?? true;
    final fillColor = widget.color ?? Colors.white;
    final baseBorderColor = widget.errorText != null
        ? Colors.red
        : (widget.borderColor ?? lightColor.withOpacity(0.4));
    final activeBorderColor = widget.errorText != null ? Colors.red : darkColor;

    final double height = widget.textInputAction == TextInputAction.newline
        ? (widget.height ?? 120) // sensible multiline default
        : (widget.height ?? 50);

    final double horizontalPadding = widget.padding ?? 16;
    final EdgeInsets margin = EdgeInsets.all(
      widget.margin ?? 6,
    ); // --space-2-ish

    return Semantics(
      label: widget.hintText,
      textField: true,
      child: RepaintBoundary(
        // OPT: prevent text cursor repaint bubbling up
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AnimatedContainer(
              duration: _animDuration,
              width: widget.width,
              height: height,
              margin: margin,
              decoration: BoxDecoration(
                color: enabled ? fillColor : fillColor.withOpacity(0.5),
                borderRadius: BorderRadius.circular(_radius),
                border: Border.all(
                  color: _isFocused ? activeBorderColor : baseBorderColor,
                  width: 1.5,
                ),
                boxShadow: _isFocused
                    ? [
                        BoxShadow(
                          color: (widget.shadowColor ?? darkColor).withOpacity(
                            0.1,
                          ),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : const [],
              ),
              child: TextField(
                focusNode: _focusNode,
                controller: widget.controller,
                enabled: enabled,
                keyboardType: widget.type ?? TextInputType.text,
                textInputAction: widget.textInputAction ?? TextInputAction.done,
                maxLength: widget.maxLength,
                autofocus: widget.autoFocus,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: darkColor,
                ),
                decoration: InputDecoration(
                  hintText: widget.hintText,
                  labelText: widget.labelText,
                  hintStyle: TextStyle(
                    color: darkColor,
                    fontWeight: FontWeight.w400,
                  ),
                  counterText: '', // hide maxLength counter
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: horizontalPadding,
                    vertical: _verticalPadding,
                  ),
                ),
                onChanged: widget.onChanged,
                maxLines: widget.textInputAction == TextInputAction.newline
                    ? null
                    : 1,
              ),
            ),
            if (widget.errorText != null) const SizedBox(height: 4),
            if (widget.errorText != null)
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Text(
                  widget.errorText!,
                  style: const TextStyle(
                    color: Colors.red,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
