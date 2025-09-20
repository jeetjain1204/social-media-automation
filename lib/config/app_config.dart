// lib/config/app_config.dart
import 'package:flutter/foundation.dart';

class AppConfig {
  static const String _defaultSupabaseUrl =
      'https://ehgginqelbgrzfrzbmis.supabase.co';
  static const String _defaultAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVoZ2dpbnFlbGJncnpmcnpibWlzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDY3MDM4ODEsImV4cCI6MjA2MjI3OTg4MX0.SpR6qfl345Ra2RyMQ2SsqfZJ-gnA66_vwDz347tuWlI';

  static String get supabaseUrl {
    // Try environment variable first, then dart-define, then default
    const envUrl = String.fromEnvironment('SUPABASE_URL');
    if (envUrl.isNotEmpty) return envUrl;

    // In production, this should be set via environment variables
    if (kReleaseMode) {
      throw StateError('SUPABASE_URL must be set in production environment');
    }

    return _defaultSupabaseUrl;
  }

  static String get supabaseAnonKey {
    // Try environment variable first, then dart-define, then default
    const envKey = String.fromEnvironment('SUPABASE_ANON_KEY');
    if (envKey.isNotEmpty) return envKey;

    // In production, this should be set via environment variables
    if (kReleaseMode) {
      throw StateError(
          'SUPABASE_ANON_KEY must be set in production environment');
    }

    return _defaultAnonKey;
  }

  static String get encryptionKey {
    const envKey = String.fromEnvironment('ENCRYPTION_KEY');
    if (envKey.isNotEmpty) return envKey;

    if (kReleaseMode) {
      throw StateError('ENCRYPTION_KEY must be set in production environment');
    }

    // Development fallback - should never be used in production
    return 'dev-encryption-key-change-in-production';
  }
}
