// lib/services/ai_cost_controller.dart
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:blob/utils/cache_manager.dart';
import 'package:blob/utils/performance_baseline.dart';

class AICostController {
  // Cost tracking
  static int _totalTokensUsed = 0;
  static double _totalCost = 0.0;
  static final Map<String, int> _modelTokenUsage = {};
  static final Map<String, double> _modelCosts = {};

  // Configuration
  static const int MAX_TOKENS_PER_REQUEST = 2000;
  static const int MAX_TOKENS_PER_DAY = 50000;
  static const Duration CACHE_TTL = Duration(hours: 24);
  static const Duration BRAND_KIT_CACHE_TTL = Duration(days: 7);

  // Model pricing (per 1K tokens)
  static const Map<String, double> MODEL_PRICING = {
    'gpt-3.5-turbo': 0.002,
    'gpt-4': 0.03,
    'gpt-4-turbo': 0.01,
    'claude-3-haiku': 0.00025,
    'claude-3-sonnet': 0.003,
    'claude-3-opus': 0.015,
  };

  // Tier limits
  static const Map<String, Map<String, int>> TIER_LIMITS = {
    'free': {'daily_tokens': 1000, 'requests_per_hour': 10},
    'basic': {'daily_tokens': 10000, 'requests_per_hour': 100},
    'pro': {'daily_tokens': 50000, 'requests_per_hour': 500},
    'enterprise': {'daily_tokens': 200000, 'requests_per_hour': 2000},
  };

  /// Generate cache key for AI request
  static String _generateCacheKey(
      String prompt, Map<String, dynamic> context, String model) {
    final combined = '$prompt${context.toString()}$model';
    final bytes = utf8.encode(combined);
    final digest = sha256.convert(bytes);
    return 'ai_${digest.toString().substring(0, 16)}';
  }

  /// Check if request can be served from cache
  static Future<String?> getCachedResult(
    String prompt,
    Map<String, dynamic> context,
    String model,
  ) async {
    final cacheKey = _generateCacheKey(prompt, context, model);

    try {
      final cached = await CacheManager.get<String>(
        cacheKey,
        (data) => data as String,
      );

      if (cached != null) {
        debugPrint('🎯 AI cache hit for model: $model');
        return cached;
      }
    } catch (e) {
      debugPrint('⚠️ AI cache read error: $e');
    }

    return null;
  }

  /// Cache AI result
  static Future<void> cacheResult(
    String prompt,
    Map<String, dynamic> context,
    String model,
    String result,
  ) async {
    final cacheKey = _generateCacheKey(prompt, context, model);

    try {
      await CacheManager.set(
        cacheKey,
        result,
        ttl: CACHE_TTL,
      );
      debugPrint('💾 AI result cached for model: $model');
    } catch (e) {
      debugPrint('⚠️ AI cache write error: $e');
    }
  }

  /// Check if user can make AI request
  static Future<bool> canMakeRequest(String userId, String model) async {
    // Check daily token limit
    final dailyUsage = await _getDailyTokenUsage(userId);
    final tier = await _getUserTier(userId);
    final dailyLimit = TIER_LIMITS[tier]?['daily_tokens'] ?? 1000;

    if (dailyUsage >= dailyLimit) {
      debugPrint('🚫 Daily token limit exceeded for user: $userId');
      return false;
    }

    // Check hourly request limit
    final hourlyRequests = await _getHourlyRequestCount(userId);
    final hourlyLimit = TIER_LIMITS[tier]?['requests_per_hour'] ?? 10;

    if (hourlyRequests >= hourlyLimit) {
      debugPrint('🚫 Hourly request limit exceeded for user: $userId');
      return false;
    }

    return true;
  }

  /// Track AI token usage and cost
  static void trackTokenUsage(String model, int tokens) {
    _totalTokensUsed += tokens;
    _modelTokenUsage[model] = (_modelTokenUsage[model] ?? 0) + tokens;

    final costPerToken = MODEL_PRICING[model] ?? 0.002;
    final cost = (tokens / 1000) * costPerToken;
    _totalCost += cost;
    _modelCosts[model] = (_modelCosts[model] ?? 0) + cost;

    PerformanceBaseline.trackAITokens(tokens, model);

    debugPrint(
        '💰 AI cost: \$${cost.toStringAsFixed(4)} for $tokens tokens ($model)');
  }

  /// Get cost report
  static Map<String, dynamic> getCostReport() {
    return {
      'total_tokens': _totalTokensUsed,
      'total_cost': _totalCost,
      'model_usage': Map<String, int>.from(_modelTokenUsage),
      'model_costs': Map<String, double>.from(_modelCosts),
      'average_cost_per_token':
          _totalTokensUsed > 0 ? _totalCost / _totalTokensUsed : 0,
    };
  }

  /// Optimize prompt for cost efficiency
  static String optimizePrompt(String prompt, {int? maxTokens}) {
    final targetTokens = maxTokens ?? MAX_TOKENS_PER_REQUEST;

    // Simple token estimation (rough approximation)
    final estimatedTokens = prompt.split(' ').length * 1.3;

    if (estimatedTokens <= targetTokens) {
      return prompt;
    }

    // Truncate if too long
    final words = prompt.split(' ');
    final targetWords = (targetTokens / 1.3).floor();
    final truncated = words.take(targetWords).join(' ');

    debugPrint('✂️ Prompt optimized: ${words.length} → ${targetWords} words');
    return truncated;
  }

  /// Batch similar requests for cost efficiency
  static List<Map<String, dynamic>> batchSimilarRequests(
    List<Map<String, dynamic>> requests,
  ) {
    final batched = <Map<String, dynamic>>[];
    final grouped = <String, List<Map<String, dynamic>>>{};

    // Group requests by similarity
    for (final request in requests) {
      final prompt = request['prompt'] as String? ?? '';
      final model = request['model'] as String? ?? 'gpt-3.5-turbo';
      final key = '$model:${prompt.length}';

      grouped.putIfAbsent(key, () => []).add(request);
    }

    // Create batches
    for (final group in grouped.values) {
      if (group.length == 1) {
        batched.addAll(group);
      } else {
        // Combine similar requests
        final batch = {
          'type': 'batch',
          'requests': group,
          'estimated_savings': (group.length - 1) * 0.1, // Rough estimate
        };
        batched.add(batch);
      }
    }

    return batched;
  }

  /// Get user tier (mock implementation)
  static Future<String> _getUserTier(String userId) async {
    // In real implementation, this would check user's subscription
    return 'basic';
  }

  /// Get daily token usage (mock implementation)
  static Future<int> _getDailyTokenUsage(String userId) async {
    // In real implementation, this would check database
    return _totalTokensUsed;
  }

  /// Get hourly request count (mock implementation)
  static Future<int> _getHourlyRequestCount(String userId) async {
    // In real implementation, this would check database
    return 0;
  }

  /// Clear cost tracking
  static void clearCostTracking() {
    _totalTokensUsed = 0;
    _totalCost = 0.0;
    _modelTokenUsage.clear();
    _modelCosts.clear();
  }

  /// Get optimization recommendations
  static Map<String, dynamic> getOptimizationRecommendations() {
    final recommendations = <String>[];

    if (_totalCost > 10.0) {
      recommendations.add('Consider using cheaper models for simple tasks');
    }

    if (_modelTokenUsage['gpt-4'] != null &&
        _modelTokenUsage['gpt-4']! > 10000) {
      recommendations.add(
          'High GPT-4 usage detected. Consider GPT-3.5-turbo for non-critical tasks');
    }

    final avgCostPerToken =
        _totalTokensUsed > 0 ? _totalCost / _totalTokensUsed : 0;
    if (avgCostPerToken > 0.01) {
      recommendations
          .add('Average cost per token is high. Review model selection');
    }

    return {
      'recommendations': recommendations,
      'potential_savings': _calculatePotentialSavings(),
      'optimization_score': _calculateOptimizationScore(),
    };
  }

  static double _calculatePotentialSavings() {
    // Calculate potential savings from using cheaper models
    double savings = 0.0;

    for (final entry in _modelTokenUsage.entries) {
      final model = entry.key;
      final tokens = entry.value;
      final currentCost = (tokens / 1000) * (MODEL_PRICING[model] ?? 0.002);

      // Assume we could use GPT-3.5-turbo instead
      final cheaperCost = (tokens / 1000) * MODEL_PRICING['gpt-3.5-turbo']!;
      savings += currentCost - cheaperCost;
    }

    return savings;
  }

  static double _calculateOptimizationScore() {
    // Score from 0-100 based on cost efficiency
    final avgCostPerToken =
        _totalTokensUsed > 0 ? _totalCost / _totalTokensUsed : 0;
    final optimalCost = 0.002; // GPT-3.5-turbo cost per token

    if (avgCostPerToken <= optimalCost) return 100.0;
    if (avgCostPerToken <= optimalCost * 2) return 80.0;
    if (avgCostPerToken <= optimalCost * 5) return 60.0;
    if (avgCostPerToken <= optimalCost * 10) return 40.0;
    return 20.0;
  }
}
