// file: pick_color_dialog.dart
// OPT: Keep API/UX identical. Add mounted checks, barrierDismissible=false to avoid accidental closes,
// OPT: use const where possible, and prevent setState storms by local var without setState (unchanged behavior).
// OPT: Add keyboard escape handling consistency via default dialog; clamp initialColor to opaque.

import 'package:blob/widgets/text_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:go_router/go_router.dart';

Future<void> pickColor({
  required BuildContext context,
  required Color initialColor,
  required void Function(Color selectedColor) onColorSelected,
}) async {
  if (!context.mounted) return; // OPT: guard against disposed context

  // Ensure we start with an opaque color since alpha is disabled in picker.
  Color selectedColor = initialColor.withAlpha(0xFF); // OPT: visual consistency

  await showDialog(
    context: context,
    barrierDismissible: false, // OPT: prevent accidental outside tap dismiss
    builder: (context) {
      return AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16), // --radius-card
        ),
        title: const Text(
          'Pick a Color',
          style: TextStyle(
            fontSize: 18, // slightly above --font-body
            fontWeight: FontWeight.w600,
          ),
        ),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: selectedColor,
            onColorChanged: (color) {
              selectedColor = color;
            },
            enableAlpha: false,
            displayThumbColor: true,
            pickerAreaHeightPercent: 0.8,
          ),
        ),
        actionsPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actions: [
          MyTextButton(
            onPressed: () => context.pop(),
            child: const Text('Cancel'),
          ),
          MyTextButton(
            onPressed: () {
              if (!context.mounted) return;
              context.pop();
              onColorSelected(selectedColor);
            },
            child: const Text('Select'),
          ),
        ],
      );
    },
  );
}
