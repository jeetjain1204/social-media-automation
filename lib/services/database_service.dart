// lib/services/database_service.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
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

  /// Fetch user dashboard data using optimized RPC with fallback
  static Future<Map<String, dynamic>?> _fetchUserDashboardData(
      String userId) async {
    return await ErrorHandler.handleAsync<Map<String, dynamic>?>(
      () async {
        final stopwatch = Stopwatch()..start();

        // Use individual queries (RPC function doesn't exist in baseline schema)
        debugPrint('Using individual queries for dashboard data');

        // Fetch all data in parallel
        final futures = await Future.wait([
          _fetchUserProfile(userId),
          _fetchSocialAccounts(userId),
          _fetchSubscriptionStatus(userId),
          _fetchBrandKit(userId),
        ]);

        final profile = futures[0] as Map<String, dynamic>?;
        final socialAccounts = futures[1] as List<Map<String, dynamic>>;
        final subscription = futures[2] as Map<String, dynamic>?;
        final brandKit = futures[3] as Map<String, dynamic>?;

        stopwatch.stop();
        PerformanceBaseline.trackDatabaseQuery(
            'get_user_dashboard_data_fallback', stopwatch.elapsed);

        return {
          'profile': profile,
          'social_accounts': socialAccounts,
          'subscription': subscription,
          'brand_kit': brandKit,
        };
      },
      context: 'getUserDashboardData',
    );
  }

  /// Fetch user profile (fallback method)
  static Future<Map<String, dynamic>?> _fetchUserProfile(String userId) async {
    try {
      final response = await _client
          .from('brand_profiles')
          .select(
            'persona, primary_goal, brand_name, primary_color, voice_tags, '
            'content_types, target_posts_per_week, category, subcategory, timezone',
          )
          .eq('user_id', userId)
          .maybeSingle()
          .timeout(const Duration(seconds: 3));
      return response;
    } catch (e) {
      debugPrint('Error fetching user profile: $e');
      return null;
    }
  }

  /// Fetch social accounts (fallback method)
  static Future<List<Map<String, dynamic>>> _fetchSocialAccounts(
      String userId) async {
    try {
      final response = await _client
          .from('social_accounts')
          .select(
              'platform, access_token, is_disconnected, needs_reconnect, connected_at')
          .eq('user_id', userId)
          .eq('is_disconnected', false)
          .timeout(const Duration(seconds: 3));
      return response.cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('Error fetching social accounts: $e');
      return [];
    }
  }

  /// Fetch subscription status (fallback method)
  static Future<Map<String, dynamic>?> _fetchSubscriptionStatus(
      String userId) async {
    try {
      final response = await _client
          .from('user_subscription_status')
          .select(
            'user_id, is_trial_active, is_active_subscriber, trial_ends_at, plan_ends_at',
          )
          .eq('user_id', userId)
          .maybeSingle()
          .timeout(const Duration(seconds: 3));
      return response;
    } catch (e) {
      debugPrint('Error fetching subscription status: $e');
      return null;
    }
  }

  /// Fetch brand kit (fallback method)
  static Future<Map<String, dynamic>?> _fetchBrandKit(String userId) async {
    try {
      // Note: This assumes brand_kit table exists in brand_kit schema
      // If it doesn't exist, this will return null gracefully
      final response = await _client
          .from('brand_kits')
          .select('brand_name, brand_logo_path')
          .eq('user_id', userId)
          .maybeSingle()
          .timeout(const Duration(seconds: 3));
      return response;
    } catch (e) {
      debugPrint('Error fetching brand kit (table may not exist): $e');
      return null;
    }
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

  /// Get social connection status using optimized RPC with fallback
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

        // Use RPC function (exists in baseline schema)
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

  /// Batch update profile data using optimized RPC with fallback
  static Future<void> updateProfile(String userId, Map<String, dynamic> updates,
      {Map<String, dynamic>? brandKitUpdates}) async {
    await ErrorHandler.handleAsync(
      () async {
        final stopwatch = Stopwatch()..start();

        // Use individual updates (RPC function doesn't exist in baseline schema)
        debugPrint('Using individual updates for profile data');

        // Update brand profile
        if (updates.isNotEmpty) {
          await _client
              .from('brand_profiles')
              .update(updates)
              .eq('user_id', userId)
              .timeout(const Duration(seconds: 5));
        }

        // Update brand kit if provided
        if (brandKitUpdates != null && brandKitUpdates.isNotEmpty) {
          try {
            await _client
                .from('brand_kits')
                .update(brandKitUpdates)
                .eq('user_id', userId)
                .timeout(const Duration(seconds: 5));
          } catch (e) {
            debugPrint('Brand kit update failed (table may not exist): $e');
          }
        }

        stopwatch.stop();
        PerformanceBaseline.trackDatabaseQuery(
            'batch_update_profile_fallback', stopwatch.elapsed);

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
