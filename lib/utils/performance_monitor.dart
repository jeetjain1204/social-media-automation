// lib/utils/performance_monitor.dart
import 'dart:async';
import 'package:flutter/foundation.dart';

class PerformanceMonitor {
  static final Map<String, Stopwatch> _timers = {};
  static final Map<String, List<Duration>> _measurements = {};

  /// Start timing a performance metric
  static void startTimer(String name) {
    _timers[name] = Stopwatch()..start();
  }

  /// End timing and record the measurement
  static Duration? endTimer(String name) {
    final timer = _timers.remove(name);
    if (timer == null) return null;

    timer.stop();
    final duration = timer.elapsed;

    // Store measurement for analysis
    _measurements.putIfAbsent(name, () => []).add(duration);

    // Log in debug mode
    if (kDebugMode) {
      debugPrint('Performance [$name]: ${duration.inMilliseconds}ms');
    }

    return duration;
  }

  /// Measure the execution time of a function
  static Future<T> measureAsync<T>(
    String name,
    Future<T> Function() function,
  ) async {
    startTimer(name);
    try {
      return await function();
    } finally {
      endTimer(name);
    }
  }

  /// Measure the execution time of a synchronous function
  static T measureSync<T>(String name, T Function() function) {
    startTimer(name);
    try {
      return function();
    } finally {
      endTimer(name);
    }
  }

  /// Get performance statistics for a metric
  static Map<String, dynamic> getStats(String name) {
    final measurements = _measurements[name];
    if (measurements == null || measurements.isEmpty) {
      return {};
    }

    measurements.sort();
    final count = measurements.length;
    final min = measurements.first;
    final max = measurements.last;
    final avg = Duration(
      microseconds:
          measurements.map((d) => d.inMicroseconds).reduce((a, b) => a + b) ~/
              count,
    );

    return {
      'count': count,
      'min': min,
      'max': max,
      'avg': avg,
      'p50': measurements[count ~/ 2],
      'p95': measurements[(count * 0.95).round() - 1],
      'p99': measurements[(count * 0.99).round() - 1],
    };
  }

  /// Get all performance statistics
  static Map<String, Map<String, dynamic>> getAllStats() {
    final stats = <String, Map<String, dynamic>>{};
    for (final name in _measurements.keys) {
      stats[name] = getStats(name);
    }
    return stats;
  }

  /// Clear all measurements
  static void clear() {
    _timers.clear();
    _measurements.clear();
  }

  /// Log performance summary
  static void logSummary() {
    if (kDebugMode) {
      final stats = getAllStats();
      debugPrint('=== Performance Summary ===');
      for (final entry in stats.entries) {
        final name = entry.key;
        final stat = entry.value;
        debugPrint(
          '$name: avg=${stat['avg']?.inMilliseconds}ms, '
          'min=${stat['min']?.inMilliseconds}ms, '
          'max=${stat['max']?.inMilliseconds}ms, '
          'count=${stat['count']}',
        );
      }
    }
  }
}
