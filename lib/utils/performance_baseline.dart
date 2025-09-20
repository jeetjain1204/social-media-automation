// lib/utils/performance_baseline.dart
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';

class PerformanceBaseline {
  static final Map<String, List<Duration>> _metrics = {};
  static final Map<String, int> _counters = {};
  static DateTime? _appStartTime;

  static void initialize() {
    _appStartTime = DateTime.now();
    _trackAppStart();
  }

  static void _trackAppStart() {
    debugPrint('🚀 App started at: ${_appStartTime}');
  }

  // Database Performance Tracking
  static void trackDatabaseQuery(String query, Duration duration) {
    _metrics.putIfAbsent('db_${_sanitizeQuery(query)}', () => []).add(duration);
    _counters['db_queries'] = (_counters['db_queries'] ?? 0) + 1;

    if (duration.inMilliseconds > 1000) {
      debugPrint(
          '⚠️ Slow DB query: ${_sanitizeQuery(query)} took ${duration.inMilliseconds}ms');
    }
  }

  // API Performance Tracking
  static void trackApiCall(
      String endpoint, Duration duration, int? statusCode) {
    final key = 'api_${endpoint}_${statusCode ?? 'unknown'}';
    _metrics.putIfAbsent(key, () => []).add(duration);
    _counters['api_calls'] = (_counters['api_calls'] ?? 0) + 1;

    if (duration.inMilliseconds > 2000) {
      debugPrint(
          '⚠️ Slow API call: $endpoint took ${duration.inMilliseconds}ms');
    }
  }

  // Page Load Tracking
  static void trackPageLoad(String route, Duration loadTime) {
    _metrics.putIfAbsent('page_$route', () => []).add(loadTime);
    _counters['page_loads'] = (_counters['page_loads'] ?? 0) + 1;

    if (loadTime.inMilliseconds > 3000) {
      debugPrint('⚠️ Slow page load: $route took ${loadTime.inMilliseconds}ms');
    }
  }

  // Memory Usage Tracking
  static void trackMemoryUsage(int bytes) {
    _counters['memory_peak'] = math.max(_counters['memory_peak'] ?? 0, bytes);
    _counters['memory_samples'] = (_counters['memory_samples'] ?? 0) + 1;
  }

  // AI Token Tracking
  static void trackAITokens(int tokens, String model) {
    _counters['ai_tokens_$model'] =
        (_counters['ai_tokens_$model'] ?? 0) + tokens;
    _counters['ai_requests'] = (_counters['ai_requests'] ?? 0) + 1;
  }

  // Generate Performance Report
  static Map<String, dynamic> generateReport() {
    final report = <String, dynamic>{
      'timestamp': DateTime.now().toIso8601String(),
      'app_uptime': _appStartTime != null
          ? DateTime.now().difference(_appStartTime!).inMilliseconds
          : 0,
      'counters': Map<String, int>.from(_counters),
      'metrics': <String, dynamic>{},
    };

    // Calculate statistics for each metric
    for (final entry in _metrics.entries) {
      final times = entry.value;
      if (times.isNotEmpty) {
        times.sort();
        final milliseconds = times.map((d) => d.inMilliseconds).toList();

        report['metrics'][entry.key] = {
          'count': times.length,
          'min': milliseconds.first,
          'max': milliseconds.last,
          'avg': milliseconds.reduce((a, b) => a + b) / milliseconds.length,
          'p50': milliseconds[milliseconds.length ~/ 2],
          'p95': milliseconds[(milliseconds.length * 0.95).round() - 1],
          'p99': milliseconds[(milliseconds.length * 0.99).round() - 1],
        };
      }
    }

    return report;
  }

  // Identify Top Bottlenecks
  static List<Map<String, dynamic>> getTopBottlenecks() {
    final bottlenecks = <Map<String, dynamic>>[];

    for (final entry in _metrics.entries) {
      final times = entry.value;
      if (times.isNotEmpty) {
        final avgMs =
            times.map((d) => d.inMilliseconds).reduce((a, b) => a + b) /
                times.length;
        final maxMs = times.map((d) => d.inMilliseconds).reduce(math.max);

        if (avgMs > 1000 || maxMs > 3000) {
          bottlenecks.add({
            'metric': entry.key,
            'avg_ms': avgMs.round(),
            'max_ms': maxMs,
            'count': times.length,
            'severity': avgMs > 3000
                ? 'critical'
                : avgMs > 1500
                    ? 'high'
                    : 'medium',
          });
        }
      }
    }

    bottlenecks
        .sort((a, b) => (b['avg_ms'] as int).compareTo(a['avg_ms'] as int));
    return bottlenecks.take(10).toList();
  }

  static String _sanitizeQuery(String query) {
    // Remove sensitive data and normalize query
    return query
        .replaceAll(RegExp(r'\b\w+@\w+\.\w+\b'), 'email@example.com')
        .replaceAll(
            RegExp(
                r'\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b'),
            'uuid')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .substring(0, math.min(50, query.length));
  }

  static void logReport() {
    if (kDebugMode) {
      final report = generateReport();
      final bottlenecks = getTopBottlenecks();

      debugPrint('📊 Performance Report:');
      debugPrint('Counters: ${jsonEncode(report['counters'])}');
      debugPrint('Top Bottlenecks: ${jsonEncode(bottlenecks)}');
    }
  }
}
