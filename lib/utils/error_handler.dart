// lib/utils/error_handler.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum ErrorType {
  network,
  authentication,
  validation,
  database,
  unknown,
}

class AppError {
  final String message;
  final ErrorType type;
  final String? code;
  final dynamic originalError;
  final StackTrace? stackTrace;

  AppError({
    required this.message,
    required this.type,
    this.code,
    this.originalError,
    this.stackTrace,
  });

  @override
  String toString() => 'AppError($type): $message';
}

class ErrorHandler {
  static final List<ErrorHandler> _handlers = [];

  /// Register a custom error handler
  static void register(ErrorHandler handler) {
    _handlers.add(handler);
  }

  /// Handle an error with proper logging and user feedback
  static Future<void> handleError(
    dynamic error,
    StackTrace? stackTrace, {
    String? context,
    bool showToUser = true,
    BuildContext? buildContext,
  }) async {
    final appError = _categorizeError(error, stackTrace);

    // Log error for debugging
    _logError(appError, context);

    // Notify registered handlers
    for (final handler in _handlers) {
      try {
        await handler.onError(appError);
      } catch (e) {
        debugPrint('Error in error handler: $e');
      }
    }

    // Show user-friendly message if requested
    if (showToUser && buildContext != null && buildContext.mounted) {
      _showUserMessage(buildContext, appError);
    }
  }

  /// Categorize error and create AppError
  static AppError _categorizeError(dynamic error, StackTrace? stackTrace) {
    if (error is AppError) return error;

    String message = 'An unexpected error occurred';
    ErrorType type = ErrorType.unknown;
    String? code;

    if (error is TimeoutException) {
      message =
          'Request timed out. Please check your connection and try again.';
      type = ErrorType.network;
    } else if (error is AuthException) {
      message = _getAuthErrorMessage(error);
      type = ErrorType.authentication;
      code = error.code;
    } else if (error is PostgrestException) {
      message = _getDatabaseErrorMessage(error);
      type = ErrorType.database;
      code = error.code;
    } else if (error is FormatException) {
      message = 'Invalid data format. Please try again.';
      type = ErrorType.validation;
    } else if (error is StateError) {
      message = error.message;
      type = ErrorType.validation;
    } else if (error is Exception) {
      message = error.toString();
    } else if (error is String) {
      message = error;
    }

    return AppError(
      message: message,
      type: type,
      code: code,
      originalError: error,
      stackTrace: stackTrace,
    );
  }

  /// Get user-friendly auth error message
  static String _getAuthErrorMessage(AuthException error) {
    switch (error.message) {
      case 'Invalid login credentials':
        return 'Invalid email or password';
      case 'User not found':
        return 'No account found with this email';
      case 'Email not confirmed':
        return 'Please verify your email before logging in';
      case 'Password should be at least 6 characters':
        return 'Password must be at least 6 characters long';
      case 'Signup is disabled':
        return 'Account creation is currently disabled';
      default:
        return error.message;
    }
  }

  /// Get user-friendly database error message
  static String _getDatabaseErrorMessage(PostgrestException error) {
    switch (error.code) {
      case '23505':
        return 'This information already exists. Please use different details.';
      case '23503':
        return 'Cannot delete this item as it is being used elsewhere.';
      case '23502':
        return 'Required information is missing. Please fill all fields.';
      case '42P01':
        return 'Database error. Please contact support.';
      default:
        return 'Database operation failed. Please try again.';
    }
  }

  /// Log error for debugging
  static void _logError(AppError error, String? context) {
    final logMessage =
        'Error${context != null ? ' in $context' : ''}: ${error.message}';

    if (kDebugMode) {
      debugPrint(logMessage);
      if (error.stackTrace != null) {
        debugPrint('Stack trace: ${error.stackTrace}');
      }
    }

    // In production, you would send this to a crash reporting service
    // like Firebase Crashlytics, Sentry, etc.
  }

  /// Show user-friendly error message
  static void _showUserMessage(BuildContext context, AppError error) {
    // Import mySnackBar here to avoid circular imports
    // This will be handled by the calling code
  }

  /// Handle error in async operations
  static Future<T?> handleAsync<T>(
    Future<T> Function() operation, {
    String? context,
    bool showToUser = true,
    BuildContext? buildContext,
    T? fallbackValue,
  }) async {
    try {
      return await operation();
    } catch (error, stackTrace) {
      await handleError(
        error,
        stackTrace,
        context: context,
        showToUser: showToUser,
        buildContext: buildContext,
      );
      return fallbackValue;
    }
  }

  /// Handle error in sync operations
  static T? handleSync<T>(
    T Function() operation, {
    String? context,
    bool showToUser = true,
    BuildContext? buildContext,
    T? fallbackValue,
  }) {
    try {
      return operation();
    } catch (error, stackTrace) {
      handleError(
        error,
        stackTrace,
        context: context,
        showToUser: showToUser,
        buildContext: buildContext,
      );
      return fallbackValue;
    }
  }

  /// Abstract method for custom error handlers
  Future<void> onError(AppError error) async {
    // Default implementation - can be overridden
  }
}

/// Default error handler for showing snackbars
class SnackBarErrorHandler extends ErrorHandler {
  @override
  Future<void> onError(AppError error) async {
    // This will be implemented by the UI layer
  }
}

/// Error handler for logging to external services
class LoggingErrorHandler extends ErrorHandler {
  @override
  Future<void> onError(AppError error) async {
    // Implement logging to external services like Firebase Crashlytics
    if (kReleaseMode) {
      // Send to crash reporting service
      debugPrint('Sending error to crash reporting service: ${error.message}');
    }
  }
}
