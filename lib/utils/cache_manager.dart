// lib/utils/cache_manager.dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class CacheManager {
  static const String _cachePrefix = 'blob_cache_';
  static const int _maxCacheSize = 50; // Maximum number of cached items
  static const Duration _defaultTTL = Duration(hours: 1);

  // In-memory cache for fast access
  static final Map<String, _CacheItem> _memoryCache = {};

  /// Get cached data with TTL check
  static Future<T?> get<T>(
      String key, T Function(Map<String, dynamic>) fromJson) async {
    final cacheKey = '$_cachePrefix$key';

    // Check memory cache first
    final memoryItem = _memoryCache[cacheKey];
    if (memoryItem != null && !memoryItem.isExpired) {
      return fromJson(memoryItem.data);
    }

    // Check persistent cache
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedData = prefs.getString(cacheKey);

      if (cachedData != null) {
        final item = _CacheItem.fromJson(jsonDecode(cachedData));

        if (!item.isExpired) {
          // Update memory cache
          _memoryCache[cacheKey] = item;
          return fromJson(item.data);
        } else {
          // Remove expired item
          await prefs.remove(cacheKey);
          _memoryCache.remove(cacheKey);
        }
      }
    } catch (e) {
      // Handle JSON parsing errors gracefully
      print('Cache get error for key $key: $e');
    }

    return null;
  }

  /// Set cached data with TTL
  static Future<void> set<T>(String key, T data, {Duration? ttl}) async {
    final cacheKey = '$_cachePrefix$key';
    final item = _CacheItem(
      data: data as Map<String, dynamic>,
      expiresAt: DateTime.now().add(ttl ?? _defaultTTL),
    );

    // Update memory cache
    _memoryCache[cacheKey] = item;

    // Update persistent cache
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(cacheKey, jsonEncode(item.toJson()));

      // Clean up old cache entries if we exceed the limit
      await _cleanupCache(prefs);
    } catch (e) {
      print('Cache set error for key $key: $e');
    }
  }

  /// Remove cached data
  static Future<void> remove(String key) async {
    final cacheKey = '$_cachePrefix$key';

    // Remove from memory cache
    _memoryCache.remove(cacheKey);

    // Remove from persistent cache
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(cacheKey);
    } catch (e) {
      print('Cache remove error for key $key: $e');
    }
  }

  /// Clear all cache
  static Future<void> clear() async {
    // Clear memory cache
    _memoryCache.clear();

    // Clear persistent cache
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((key) => key.startsWith(_cachePrefix));
      for (final key in keys) {
        await prefs.remove(key);
      }
    } catch (e) {
      print('Cache clear error: $e');
    }
  }

  /// Clean up old cache entries
  static Future<void> _cleanupCache(SharedPreferences prefs) async {
    final keys =
        prefs.getKeys().where((key) => key.startsWith(_cachePrefix)).toList();

    if (keys.length <= _maxCacheSize) return;

    // Sort by access time (oldest first)
    final items = <MapEntry<String, DateTime>>[];

    for (final key in keys) {
      try {
        final cachedData = prefs.getString(key);
        if (cachedData != null) {
          final item = _CacheItem.fromJson(jsonDecode(cachedData));
          items.add(MapEntry(key, item.expiresAt));
        }
      } catch (e) {
        // Remove corrupted entries
        await prefs.remove(key);
      }
    }

    // Remove oldest entries
    items.sort((a, b) => a.value.compareTo(b.value));
    final toRemove = items.take(items.length - _maxCacheSize);

    for (final entry in toRemove) {
      await prefs.remove(entry.key);
      _memoryCache.remove(entry.key);
    }
  }
}

class _CacheItem {
  final Map<String, dynamic> data;
  final DateTime expiresAt;

  _CacheItem({required this.data, required this.expiresAt});

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  Map<String, dynamic> toJson() => {
        'data': data,
        'expiresAt': expiresAt.toIso8601String(),
      };

  factory _CacheItem.fromJson(Map<String, dynamic> json) => _CacheItem(
        data: Map<String, dynamic>.from(json['data']),
        expiresAt: DateTime.parse(json['expiresAt']),
      );
}
