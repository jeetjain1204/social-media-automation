// lib/services/network_optimizer.dart
import 'dart:async';
import 'dart:math';
import 'package:blob/utils/performance_baseline.dart';

class NetworkOptimizer {
  // Request deduplication cache
  static final Map<String, Future<dynamic>> _pendingRequests = {};
  static final Map<String, DateTime> _lastRequests = {};

  // Circuit breaker state
  static final Map<String, CircuitBreakerState> _circuitBreakers = {};

  // Configuration
  static const Duration DEBOUNCE_DURATION = Duration(milliseconds: 300);
  static const Duration REQUEST_TIMEOUT = Duration(seconds: 10);
  static const int MAX_RETRIES = 3;
  static const Duration RETRY_BASE_DELAY = Duration(milliseconds: 500);

  /// Debounced request to prevent rapid-fire calls
  static Future<T> debouncedRequest<T>(
    String key,
    Future<T> Function() request, {
    Duration? debounceDuration,
  }) async {
    final now = DateTime.now();
    final lastRequest = _lastRequests[key];
    final debounce = debounceDuration ?? DEBOUNCE_DURATION;

    if (lastRequest != null && now.difference(lastRequest) < debounce) {
      final waitTime = debounce - now.difference(lastRequest);
      await Future.delayed(waitTime);
    }

    _lastRequests[key] = DateTime.now();
    return await request();
  }

  /// Deduplicated request - prevents multiple identical requests
  static Future<T> deduplicatedRequest<T>(
    String key,
    Future<T> Function() request, {
    Duration? cacheDuration,
  }) async {
    // Check if request is already pending
    if (_pendingRequests.containsKey(key)) {
      return await _pendingRequests[key] as T;
    }

    // Create new request
    final requestFuture = _executeWithCircuitBreaker(key, request);
    _pendingRequests[key] = requestFuture;

    try {
      final result = await requestFuture;
      return result;
    } finally {
      _pendingRequests.remove(key);
    }
  }

  /// Execute request with circuit breaker pattern
  static Future<T> _executeWithCircuitBreaker<T>(
    String key,
    Future<T> Function() request,
  ) async {
    final circuitBreaker = _circuitBreakers.putIfAbsent(
      key,
      () => CircuitBreakerState(),
    );

    // Check if circuit is open
    if (circuitBreaker.isOpen()) {
      throw CircuitBreakerException('Circuit breaker is open for $key');
    }

    try {
      final stopwatch = Stopwatch()..start();
      final result = await request().timeout(REQUEST_TIMEOUT);
      stopwatch.stop();

      // Track successful request
      PerformanceBaseline.trackApiCall(key, stopwatch.elapsed, 200);
      circuitBreaker.recordSuccess();

      return result;
    } catch (error) {
      circuitBreaker.recordFailure();

      // Track failed request
      final statusCode = error is TimeoutException ? 408 : 500;
      PerformanceBaseline.trackApiCall(key, Duration.zero, statusCode);

      // Retry with exponential backoff if circuit is not open
      if (!circuitBreaker.isOpen() &&
          circuitBreaker.failureCount < MAX_RETRIES) {
        final delay = _calculateRetryDelay(circuitBreaker.failureCount);
        await Future.delayed(delay);
        return await _executeWithCircuitBreaker(key, request);
      }

      rethrow;
    }
  }

  /// Batch multiple requests together
  static Future<List<T>> batchRequests<T>(
    List<Future<T> Function()> requests, {
    Duration? timeout,
  }) async {
    final stopwatch = Stopwatch()..start();

    try {
      final results = await Future.wait(
        requests.map((req) => req()),
        eagerError: false,
      ).timeout(timeout ?? REQUEST_TIMEOUT);

      stopwatch.stop();
      PerformanceBaseline.trackApiCall(
          'batch_requests', stopwatch.elapsed, 200);

      return results;
    } catch (error) {
      stopwatch.stop();
      PerformanceBaseline.trackApiCall(
          'batch_requests', stopwatch.elapsed, 500);
      rethrow;
    }
  }

  /// Calculate retry delay with exponential backoff and jitter
  static Duration _calculateRetryDelay(int attempt) {
    final baseDelay = RETRY_BASE_DELAY.inMilliseconds;
    final exponentialDelay = baseDelay * pow(2, attempt);
    final jitter = Random().nextInt(1000); // Add up to 1 second jitter
    return Duration(milliseconds: exponentialDelay.toInt() + jitter);
  }

  /// Get circuit breaker status
  static Map<String, Map<String, dynamic>> getCircuitBreakerStatus() {
    return _circuitBreakers.map((key, state) => MapEntry(key, {
          'isOpen': state.isOpen(),
          'failureCount': state.failureCount,
          'lastFailure': state.lastFailure?.toIso8601String(),
          'nextRetry': state.nextRetry?.toIso8601String(),
        }));
  }

  /// Reset circuit breaker for a key
  static void resetCircuitBreaker(String key) {
    _circuitBreakers.remove(key);
  }

  /// Clear all pending requests
  static void clearPendingRequests() {
    _pendingRequests.clear();
  }

  /// Get network statistics
  static Map<String, dynamic> getNetworkStats() {
    return {
      'pending_requests': _pendingRequests.length,
      'circuit_breakers': _circuitBreakers.length,
      'open_circuits': _circuitBreakers.values.where((s) => s.isOpen()).length,
    };
  }
}

/// Circuit breaker state management
class CircuitBreakerState {
  int failureCount = 0;
  DateTime? lastFailure;
  DateTime? nextRetry;
  static const int FAILURE_THRESHOLD = 5;
  static const Duration OPEN_DURATION = Duration(minutes: 1);

  bool isOpen() {
    if (failureCount < FAILURE_THRESHOLD) return false;
    if (lastFailure == null) return false;

    final timeSinceLastFailure = DateTime.now().difference(lastFailure!);
    return timeSinceLastFailure < OPEN_DURATION;
  }

  void recordSuccess() {
    failureCount = 0;
    lastFailure = null;
    nextRetry = null;
  }

  void recordFailure() {
    failureCount++;
    lastFailure = DateTime.now();
    nextRetry = lastFailure!.add(OPEN_DURATION);
  }
}

/// Circuit breaker exception
class CircuitBreakerException implements Exception {
  final String message;
  CircuitBreakerException(this.message);

  @override
  String toString() => 'CircuitBreakerException: $message';
}
