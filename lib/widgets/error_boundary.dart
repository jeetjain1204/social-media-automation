// lib/widgets/error_boundary.dart
import 'package:flutter/material.dart';
import 'package:blob/utils/colors.dart';
import 'package:blob/utils/error_handler.dart';

class ErrorBoundary extends StatefulWidget {
  final Widget child;
  final Widget? fallback;
  final String? context;

  const ErrorBoundary({
    super.key,
    required this.child,
    this.fallback,
    this.context,
  });

  @override
  State<ErrorBoundary> createState() => _ErrorBoundaryState();
}

class _ErrorBoundaryState extends State<ErrorBoundary> {
  bool _hasError = false;
  AppError? _error;

  @override
  void initState() {
    super.initState();
    // Register error handler for this boundary
    ErrorHandler.register(_ErrorBoundaryHandler(this));
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return widget.fallback ?? _buildErrorWidget();
    }

    return widget.child;
  }

  Widget _buildErrorWidget() {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Scaffold(
        backgroundColor: lightColor,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 64,
                  color: darkColor,
                ),
                const SizedBox(height: 24),
                Text(
                  'Something went wrong',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: darkColor,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  _error?.message ?? 'An unexpected error occurred',
                  style: TextStyle(
                    fontSize: 16,
                    color: darkColor.withOpacity(0.8),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _hasError = false;
                      _error = null;
                    });
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: darkColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 16,
                    ),
                  ),
                  child: const Text('Try Again'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _handleError(AppError error) {
    if (mounted) {
      setState(() {
        _hasError = true;
        _error = error;
      });
    }
  }
}

class _ErrorBoundaryHandler extends ErrorHandler {
  final _ErrorBoundaryState _state;

  _ErrorBoundaryHandler(this._state);

  @override
  Future<void> onError(AppError error) async {
    _state._handleError(error);
  }
}

/// Wrapper widget that catches errors and shows a fallback UI
class ErrorCatcher extends StatelessWidget {
  final Widget child;
  final Widget Function(AppError error)? errorBuilder;
  final String? context;

  const ErrorCatcher({
    super.key,
    required this.child,
    this.errorBuilder,
    this.context,
  });

  @override
  Widget build(BuildContext context) {
    return ErrorBoundary(
      context: this.context,
      fallback: errorBuilder != null
          ? Builder(
              builder: (context) => errorBuilder!(
                AppError(
                  message: 'Widget error',
                  type: ErrorType.unknown,
                ),
              ),
            )
          : null,
      child: child,
    );
  }
}
