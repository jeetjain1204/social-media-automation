// file: my_snack_bar.dart
// FIXED: Enhanced snackbar with error handling integration

import 'package:blob/utils/colors.dart';
import 'package:blob/utils/error_handler.dart';
import 'package:flutter/material.dart';

void mySnackBar(BuildContext context, String text, {int? duration}) {
  if (!context.mounted) return;

  final snackBar = SnackBar(
    behavior: SnackBarBehavior.floating,
    backgroundColor: darkColor,
    duration: Duration(seconds: duration ?? 2),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
    ),
    margin: const EdgeInsets.symmetric(
      horizontal: 20,
      vertical: 16,
    ),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    content: Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: Colors.white,
      ),
    ),
  );

  final messenger = ScaffoldMessenger.of(context);
  messenger.clearSnackBars();
  messenger.showSnackBar(snackBar);
}

/// Show error snackbar with proper error handling
void showErrorSnackBar(BuildContext context, AppError error, {int? duration}) {
  if (!context.mounted) return;

  mySnackBar(context, error.message, duration: duration);
}

/// Show success snackbar
void showSuccessSnackBar(BuildContext context, String message,
    {int? duration}) {
  if (!context.mounted) return;

  final snackBar = SnackBar(
    behavior: SnackBarBehavior.floating,
    backgroundColor: Colors.green,
    duration: Duration(seconds: duration ?? 2),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
    ),
    margin: const EdgeInsets.symmetric(
      horizontal: 20,
      vertical: 16,
    ),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    content: Text(
      message,
      textAlign: TextAlign.center,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: Colors.white,
      ),
    ),
  );

  final messenger = ScaffoldMessenger.of(context);
  messenger.clearSnackBars();
  messenger.showSnackBar(snackBar);
}
