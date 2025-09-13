// file: html_window_accessor.dart
// OPT: Preserve behavior while adding null-safety clarity and documentation.
// OPT: No functional changes — still returns the top-level window for Flutter Web; ignored on other platforms.

// ignore: avoid_web_libraries_in_flutter
import 'package:universal_html/html.dart' as html;

/// Provides access to the top-level browser [html.window] object when running on Web.
///
/// Returns `null` on platforms where `dart:html` is unsupported (non-Web targets).
///
/// **Security note**: Avoid exposing `html.window` directly to untrusted code,
/// and never use it to interpolate user input into DOM without sanitization.
html.Window? get htmlWindow => html.window;
