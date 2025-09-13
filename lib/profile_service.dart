// lib/profile_service.dart
import 'dart:async'; // OPT: TimeoutException for bounded network calls
import 'package:retry/retry.dart'; // OPT: selective retry with jitter
import 'package:supabase_flutter/supabase_flutter.dart';
import 'brand_profile_draft.dart';

class ProfileService {
  final supabase = Supabase.instance.client;

  Future<void> upsert(
    BrandProfileDraft d, {
    bool incompleteOnly = false,
  }) async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      throw Exception('User not authenticated');
    }
    final uid = user.id;

    // OPT: Light retry for transient hiccups (timeouts). SocketException is not Web-safe, so we avoid dart:io.
    final r = RetryOptions(
      maxAttempts:
          3, // OPT: Small, bounded retries to avoid duplicate writes or long hangs
      delayFactor: const Duration(milliseconds: 250), // OPT: Jittered backoff
      maxDelay: const Duration(seconds: 2),
    );

    Map<String, dynamic>? profile;
    try {
      profile = await r.retry(
        () => supabase
            .from('brand_profiles')
            .select(
              // OPT: Column-pruned select cuts payload and speeds up P50/P95.
              'id, user_id, persona, category, subcategory, primary_goal, '
              'content_types, target_posts_per_week, brand_name, brand_logo_path, '
              'primary_color, voice_tags, timezone',
            )
            .eq('user_id', uid)
            .maybeSingle()
            .timeout(const Duration(seconds: 8)), // OPT: Bound network time
        // OPT: Retry only on timeouts (cross‑platform safe). Avoids retrying logic errors (4xx).
        retryIf: (e) => e is TimeoutException,
      );
    } catch (_) {
      // OPT: Non-fatal read failure; continue with upsert attempt using current draft.
      profile = null;
    }

    // OPT: Preallocate small map to reduce churn.
    final Map<String, dynamic> updatedProfile = <String, dynamic>{};
    bool shouldUpsertProfile = false;

    // NOTE: Behavior unchanged.
    // When incompleteOnly == false, write whatever d has (even null/empty).
    // When incompleteOnly == true, write only if existing is null/empty list/string.
    void checkAndSet(String key, dynamic newVal, dynamic existingVal) {
      if (!incompleteOnly ||
          existingVal == null ||
          existingVal == '' ||
          (existingVal is List && existingVal.isEmpty)) {
        updatedProfile[key] = newVal;
        shouldUpsertProfile = true;
      }
    }

    checkAndSet('user_id', uid, profile?['user_id']);
    checkAndSet('persona', d.persona, profile?['persona']);
    checkAndSet('category', d.category, profile?['category']);
    checkAndSet('subcategory', d.subcategory, profile?['subcategory']);
    checkAndSet('primary_goal', d.primary_goal, profile?['primary_goal']);
    // checkAndSet('first_platform', d.firstPlatform, profile?['first_platform']); // kept commented for parity
    checkAndSet('content_types', d.content_types, profile?['content_types']);
    checkAndSet('target_posts_per_week', d.target_posts_per_week,
        profile?['target_posts_per_week']);
    checkAndSet('brand_name', d.brand_name, profile?['brand_name']);
    checkAndSet(
        'brand_logo_path', d.brand_logo_path, profile?['brand_logo_path']);
    checkAndSet('primary_color', d.primary_color, profile?['primary_color']);
    checkAndSet('voice_tags', d.voice_tags, profile?['voice_tags']);
    checkAndSet('timezone', d.timezone, profile?['timezone']);

    if (shouldUpsertProfile) {
      if (!updatedProfile.containsKey('user_id')) {
        updatedProfile['user_id'] =
            uid; // OPT: ensure ON CONFLICT target present
      }

      // OPT: Timeout + selective retry on write; .select('id') returns minimal representation.
      await r.retry(
        () => supabase
            .from('brand_profiles')
            .upsert(updatedProfile, onConflict: 'user_id')
            .select(
                'id') // OPT: minimal data back; enough to confirm write and preserve prior behavior
            .maybeSingle()
            .timeout(const Duration(seconds: 10)),
        // OPT: Retry only on timeouts to avoid duplicate logical writes.
        retryIf: (e) => e is TimeoutException,
      );
    }
  }
}
