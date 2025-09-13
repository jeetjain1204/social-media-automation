// file: load_image_from_url.dart
// OPT: Add HTTP error details, timeouts, and image decoding error handling.
// OPT: No change to return type or core behavior — still fetches an image from a URL and returns it as ui.Image.

import 'dart:ui' as ui;
import 'package:http/http.dart' as http;

/// Loads an image from a remote [url] and decodes it into a [ui.Image].
///
/// Throws [Exception] if the HTTP request fails or image decoding fails.
Future<ui.Image> loadImageFromUrl(String url) async {
  final uri = Uri.parse(url);

  // OPT: Add a timeout to prevent hanging network calls (10 seconds default).
  final res = await http.get(uri).timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw Exception('Timeout loading image: $url'),
      );

  if (res.statusCode == 200) {
    final bytes = res.bodyBytes;
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      return frame.image;
    } catch (e) {
      // OPT: Provide clear decoding error.
      throw Exception('Failed to decode image from $url: $e');
    }
  } else {
    throw Exception('Failed to load image: $url (HTTP ${res.statusCode})');
  }
}
