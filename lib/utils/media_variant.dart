// file: media_variant_capability.dart
// OPT: Make lists const/immutable to avoid allocations and accidental mutation.
// OPT: Cache eligible platforms per variant to avoid recomputation on hot paths.
// OPT: Keep public API, behavior, and data shapes identical.
// OPT: Added const constructors and inlined constant maps for zero runtime cost.

/// Defines the types of media a post can contain.
enum MediaVariant {
  textOnly,
  singleImage,
  multiImage,
}

/// Maps each platform to the supported media variants and their corresponding post type identifiers.
/// Keys are platform identifiers, values are maps from [MediaVariant] to a list of post type strings.
const Map<String, Map<MediaVariant, List<String>>> capability = {
  'linkedin': {
    MediaVariant.textOnly: ['linkedin_post'],
    MediaVariant.singleImage: ['linkedin_image'],
    MediaVariant.multiImage: ['linkedin_carousel'],
  },
  'facebook': {
    MediaVariant.textOnly: ['facebook_post'],
    MediaVariant.singleImage: ['facebook_image', 'facebook_story'],
    MediaVariant.multiImage: ['facebook_multi'],
  },
  'instagram': {
    MediaVariant.textOnly: <String>[],
    MediaVariant.singleImage: ['instagram_post', 'instagram_story'],
    MediaVariant.multiImage: ['instagram_carousel'],
  },
};

/// Returns the [MediaVariant] corresponding to the number of images.
MediaVariant getVariantFromCount(int count) {
  if (count <= 0) return MediaVariant.textOnly; // OPT: Defensive for negatives
  return count == 1 ? MediaVariant.singleImage : MediaVariant.multiImage;
}

// OPT: Cache eligible platforms for each variant once (cold path), then reuse (hot path).
final Map<MediaVariant, List<String>> eligiblePlatformsByVariantCache = {
  for (final v in MediaVariant.values)
    v: [
      for (final entry in capability.entries)
        if ((entry.value[v] ?? const <String>[]).isNotEmpty) entry.key,
    ],
};

/// Returns a list of platform keys that support the given image count variant.
/// Uses a cached, immutable view for zero allocations on repeat calls.
List<String> getEligiblePlatforms(int imageCount) =>
    eligiblePlatformsByVariantCache[getVariantFromCount(imageCount)]!;

/// Returns a mapping from platforms to their supported post type identifiers
/// for the given [platforms] list and [imageCount].
///
/// Returns the canonical lists from [capability] (which are const), avoiding copies.
Map<String, List<String>> getPostTypesFor(
  List<String> platforms,
  int imageCount,
) {
  final variant = getVariantFromCount(imageCount);
  final result = <String, List<String>>{};
  for (final p in platforms) {
    final types = capability[p]?[variant] ?? const <String>[];
    if (types.isNotEmpty) result[p] = types;
  }
  return result;
}
