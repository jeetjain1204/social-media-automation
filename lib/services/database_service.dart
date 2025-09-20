// lib/services/database_service.dart
import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:blob/utils/cache_manager.dart';
import 'package:blob/utils/error_handler.dart';
import 'package:blob/utils/performance_baseline.dart';

class DatabaseService {
  static final SupabaseClient _client = Supabase.instance.client;

  // Request deduplication cache
  static final Map<String, Future<dynamic>> _pendingRequests = {};

  /// Get user dashboard data in single optimized call
  static Future<Map<String, dynamic>?> getUserDashboardData(
      String userId) async {
    final cacheKey = 'user_dashboard_$userId';

    // Check cache first
    final cached = await CacheManager.get<Map<String, dynamic>>(
      cacheKey,
      (data) => data,
    );
    if (cached != null) return cached;

    // Check if request is already pending
    if (_pendingRequests.containsKey(cacheKey)) {
      return await _pendingRequests[cacheKey] as Map<String, dynamic>?;
    }

    // Create new request
    final request = _fetchUserDashboardData(userId);
    _pendingRequests[cacheKey] = request;

    try {
      final result = await request;
      if (result != null) {
        await CacheManager.set(
          cacheKey,
          result,
          ttl: const Duration(minutes: 10),
        );
      }
      return result;
    } finally {
      _pendingRequests.remove(cacheKey);
    }
  }

  /// Get user profile with caching and deduplication (legacy method)
  static Future<Map<String, dynamic>?> getUserProfile(String userId) async {
    final dashboardData = await getUserDashboardData(userId);
    return dashboardData?['profile'] as Map<String, dynamic>?;
  }

  /// Fetch user dashboard data using optimized RPC
  static Future<Map<String, dynamic>?> _fetchUserDashboardData(
      String userId) async {
    return await ErrorHandler.handleAsync<Map<String, dynamic>?>(
      () async {
        final stopwatch = Stopwatch()..start();

        final response = await _client.rpc('get_user_dashboard_data',
            params: {'user_uuid': userId}).timeout(const Duration(seconds: 5));

        stopwatch.stop();
        PerformanceBaseline.trackDatabaseQuery(
            'get_user_dashboard_data', stopwatch.elapsed);

        return response as Map<String, dynamic>?;
      },
      context: 'getUserDashboardData',
    );
  }

  /// Fetch user profile from database (legacy method)
  static Future<Map<String, dynamic>?> fetchUserProfile(String userId) async {
    return await ErrorHandler.handleAsync<Map<String, dynamic>?>(
      () async {
        final stopwatch = Stopwatch()..start();

        final response = await _client
            .from('brand_profiles')
            .select(
              'persona, primary_goal, brand_name, primary_color, voice_tags, '
              'content_types, target_posts_per_week, category, subcategory, timezone',
            )
            .eq('user_id', userId)
            .maybeSingle()
            .timeout(const Duration(seconds: 8));

        stopwatch.stop();
        PerformanceBaseline.trackDatabaseQuery(
            'get_user_profile', stopwatch.elapsed);

        return response;
      },
      context: 'getUserProfile',
    );
  }

  /// Get social accounts with caching (optimized via dashboard data)
  static Future<List<Map<String, dynamic>>> getSocialAccounts(
      String userId) async {
    final dashboardData = await getUserDashboardData(userId);
    final accounts = dashboardData?['social_accounts'] as List?;
    return accounts?.cast<Map<String, dynamic>>() ?? [];
  }

  /// Get social connection status using optimized RPC
  static Future<Map<String, dynamic>?> getSocialConnectionStatus(
      String userId) async {
    final cacheKey = 'social_status_$userId';

    // Check cache first
    final cached = await CacheManager.get<Map<String, dynamic>>(
      cacheKey,
      (data) => data,
    );
    if (cached != null) return cached;

    return await ErrorHandler.handleAsync<Map<String, dynamic>?>(
      () async {
        final stopwatch = Stopwatch()..start();

        final response = await _client.rpc('get_social_connection_status',
            params: {'user_uuid': userId}).timeout(const Duration(seconds: 3));

        stopwatch.stop();
        PerformanceBaseline.trackDatabaseQuery(
            'get_social_connection_status', stopwatch.elapsed);

        final result = response as Map<String, dynamic>?;
        if (result != null) {
          await CacheManager.set(
            cacheKey,
            result,
            ttl: const Duration(minutes: 5),
          );
        }
        return result;
      },
      context: 'getSocialConnectionStatus',
    );
  }

  /// Fetch social accounts from database
  static Future<List<Map<String, dynamic>>> fetchSocialAccounts(
      String userId) async {
    return await ErrorHandler.handleAsync(
          () async {
            final response = await _client
                .from('social_accounts')
                .select(
                    'platform, access_token, is_disconnected, needs_reconnect, connected_at')
                .eq('user_id', userId)
                .eq('is_disconnected', false)
                .inFilter('platform', [
              'linkedin',
              'facebook',
              'instagram'
            ]).timeout(const Duration(seconds: 8));

            return (response as List).cast<Map<String, dynamic>>();
          },
          context: 'getSocialAccounts',
          fallbackValue: <Map<String, dynamic>>[],
        ) ??
        <Map<String, dynamic>>[];
  }

  /// Get subscription status with caching (optimized via dashboard data)
  static Future<Map<String, dynamic>?> getSubscriptionStatus(
      String userId) async {
    final dashboardData = await getUserDashboardData(userId);
    return dashboardData?['subscription'] as Map<String, dynamic>?;
  }

  /// Fetch subscription status from database
  static Future<Map<String, dynamic>?> fetchSubscriptionStatus(
      String userId) async {
    return await ErrorHandler.handleAsync<Map<String, dynamic>?>(
      () async {
        final response = await _client
            .from('user_subscription_status')
            .select(
              'user_id, is_trial_active, is_active_subscriber, trial_ends_at, plan_ends_at',
            )
            .eq('user_id', userId)
            .maybeSingle()
            .timeout(const Duration(seconds: 8));

        return response;
      },
      context: 'getSubscriptionStatus',
    );
  }

  /// Batch update profile data using optimized RPC
  static Future<void> updateProfile(String userId, Map<String, dynamic> updates,
      {Map<String, dynamic>? brandKitUpdates}) async {
    await ErrorHandler.handleAsync(
      () async {
        final stopwatch = Stopwatch()..start();

        await _client.rpc('batch_update_profile', params: {
          'user_uuid': userId,
          'profile_updates': updates,
          'brand_kit_updates': brandKitUpdates,
        }).timeout(const Duration(seconds: 8));

        stopwatch.stop();
        PerformanceBaseline.trackDatabaseQuery(
            'batch_update_profile', stopwatch.elapsed);

        // Invalidate all related caches
        await CacheManager.remove('user_profile_$userId');
        await CacheManager.remove('user_dashboard_$userId');
        await CacheManager.remove('social_status_$userId');
      },
      context: 'updateProfile',
    );
  }

  /// Batch update social account
  static Future<void> updateSocialAccount(
    String userId,
    String platform,
    Map<String, dynamic> updates,
  ) async {
    await ErrorHandler.handleAsync(
      () async {
        await _client
            .from('social_accounts')
            .update(updates)
            .eq('user_id', userId)
            .eq('platform', platform)
            .timeout(const Duration(seconds: 10));

        // Invalidate cache
        await CacheManager.remove('social_accounts_$userId');
      },
      context: 'updateSocialAccount',
    );
  }

  /// Clear all caches for a user
  static Future<void> clearUserCache(String userId) async {
    await CacheManager.remove('user_profile_$userId');
    await CacheManager.remove('user_dashboard_$userId');
    await CacheManager.remove('social_accounts_$userId');
    await CacheManager.remove('social_status_$userId');
    await CacheManager.remove('subscription_status_$userId');
  }

  /// Clear all pending requests
  static void clearPendingRequests() {
    _pendingRequests.clear();
  }
}
