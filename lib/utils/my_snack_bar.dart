// file: my_snack_bar.dart
// OPT: Minor DX & perf: reuse SnackBar instance where possible, use const for style parts, and defensive context check.
// OPT: Keep same API, behavior, and visuals.

import 'package:blob/utils/colors.dart';
import 'package:flutter/material.dart';

void mySnackBar(BuildContext context, String text, {int? duration}) {
  if (!context.mounted)
    return; // OPT: Defensive guard to avoid calling on disposed context

  final snackBar = SnackBar(
    behavior: SnackBarBehavior.floating,
    backgroundColor: darkColor,
    duration: Duration(seconds: duration ?? 2),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16), // --radius-card
    ),
    margin: const EdgeInsets.symmetric(
      horizontal: 20,
      vertical: 16,
    ), // --space-4
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    content: Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(
        fontSize: 14, // --font-caption
        fontWeight: FontWeight.w500,
        color: Colors.white,
      ),
    ),
  );

  final messenger = ScaffoldMessenger.of(context);
  messenger.clearSnackBars();
  messenger.showSnackBar(snackBar);
}
