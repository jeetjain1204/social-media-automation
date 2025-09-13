import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class ForegroundNotifier extends ChangeNotifier {
  // TEXT CONTENT
  String text = "Your quote goes here.";
  double textBoxFactor = 0.84;

  // FONT + STYLING
  String fontFamily = "Roboto";
  int fontWeight = 400;
  double manualFont = 28;
  double lineHeight = 1.2;
  String textAlign = 'C'; // 'L' | 'C' | 'R'
  Color textColor = Colors.black;
  bool italic = false;
  bool uppercase = false;

  // SUB LINE
  bool showSubLine = true;
  String subText = "Author Name";
  double subScale = 0.6;

  // LOGO
  ui.Image? logoImage;
  bool showLogo = true;
  String logoPlacement = "TL"; // 'TL' | 'TR' | 'TC' | 'BL' | 'BR' | 'BC'
  double logoScale = 0.12;

  // HEADSHOT
  ui.Image? headshotImage;
  bool showHeadshot = true;
  String headshotPlacement = "BR";
  double headshotScale = 0.12;

  // LAYOUT + VISUAL EFFECTS
  double overlayPadding = 0.0;
  double rounding = 16;
  bool shadow = true;
  double shadowBlur = 4;
  bool autoBrightness = true;
  String selectedAspectRatio = '1:1';

  double backgroundBlur = 0;
  double backgroundBrightness = 100;

  // ====== Convenience getters (non-breaking) ======
  // OPT: DX — helpers used by painters without changing stored data.
  TextAlign get textAlignResolved {
    switch (textAlign) {
      case 'L':
        return TextAlign.left;
      case 'R':
        return TextAlign.right;
      default:
        return TextAlign.center;
    }
  }

  // Returns normalized 2D placement hints if useful to painters.
  // Values: 0.0 (min/top/left) → 0.5 (center) → 1.0 (max/bottom/right)
  // OPT: DX — purely optional helpers.
  Offset get logoAnchor => _placementToAnchor(logoPlacement);
  Offset get headshotAnchor => _placementToAnchor(headshotPlacement);

  // ====== Public API (kept semantics) ======

  /// Update a single property by key.
  /// Behavior preserved:
  /// - Always calls `notifyListeners()` at the end, even if the value didn't change.
  /// - Type guards added to prevent runtime type errors. // OPT: reliability
  void update(String key, dynamic value) {
    switch (key) {
      case 'Text':
        text = _toString(value, text); // OPT: guard
        break;
      case 'textBoxFactor':
        textBoxFactor = _toDouble(value, textBoxFactor); // OPT: guard
        break;
      case 'fontFamily':
        fontFamily = _toString(value, fontFamily); // OPT: guard
        break;
      case 'fontWeight':
        fontWeight = _toInt(value, fontWeight); // OPT: guard
        break;
      case 'manualFont':
        manualFont = _toDouble(value, manualFont); // OPT: guard
        break;
      case 'lineHeight':
        lineHeight = _toDouble(value, lineHeight); // OPT: guard
        break;
      case 'textAlign':
        textAlign = _toString(value, textAlign); // OPT: guard
        break;
      case 'textColor':
        textColor = _toColor(value, textColor); // OPT: guard
        break;
      case 'italic':
        italic = _toBool(value, italic); // OPT: guard
        break;
      case 'uppercase':
        uppercase = _toBool(value, uppercase); // OPT: guard
        break;
      case 'showSubLine':
        showSubLine = _toBool(value, showSubLine); // OPT: guard
        break;
      case 'subText':
        subText = _toString(value, subText); // OPT: guard
        break;
      case 'subScale':
        subScale = _toDouble(value, subScale); // OPT: guard
        break;
      case 'showLogo':
        showLogo = _toBool(value, showLogo); // OPT: guard
        break;
      case 'logoPlacement':
        logoPlacement = _toString(value, logoPlacement); // OPT: guard
        break;
      case 'logoScale':
        logoScale = _toDouble(value, logoScale); // OPT: guard
        break;
      case 'logoImage':
        logoImage = value as ui.Image?; // OPT: type-safe cast
        break;
      case 'showHeadshot':
        showHeadshot = _toBool(value, showHeadshot); // OPT: guard
        break;
      case 'headshotPlacement':
        headshotPlacement = _toString(value, headshotPlacement); // OPT: guard
        break;
      case 'headshotScale':
        headshotScale = _toDouble(value, headshotScale); // OPT: guard
        break;
      case 'headshotImage':
        headshotImage = value as ui.Image?; // OPT: type-safe cast
        break;
      case 'overlayPadding':
        overlayPadding = _toDouble(value, overlayPadding); // OPT: guard
        break;
      case 'rounding':
        rounding = _toDouble(value, rounding); // OPT: guard
        break;
      case 'shadow':
        shadow = _toBool(value, shadow); // OPT: guard
        break;
      case 'shadowBlur':
        shadowBlur = _toDouble(value, shadowBlur); // OPT: guard
        break;
      case 'autoBrightness':
        autoBrightness = _toBool(value, autoBrightness); // OPT: guard
        break;
      case 'selectedAspectRatio':
        selectedAspectRatio =
            _toString(value, selectedAspectRatio); // OPT: guard
        break;
      case 'backgroundBlur':
        backgroundBlur = _toDouble(value, backgroundBlur); // OPT: guard
        break;
      case 'backgroundBrightness':
        backgroundBrightness =
            _toDouble(value, backgroundBrightness); // OPT: guard
        break;
    }
    notifyListeners(); // keep original semantics
  }

  /// Update multiple properties in a single notify.
  /// Behavior preserved: single `notifyListeners()` at the end.
  void updateAll(Map<String, dynamic> map) {
    text = _toString(map['text'], text);
    fontFamily = _toString(map['fontFamily'], fontFamily);
    fontWeight = _toInt(map['fontWeight'], fontWeight);
    manualFont = _toDouble(map['manualFont'], manualFont);
    lineHeight = _toDouble(map['lineHeight'], lineHeight);
    textAlign = _toString(map['textAlign'], textAlign);
    textColor = _toColor(map['textColor'], textColor);
    italic = _toBool(map['italic'], italic);
    uppercase = _toBool(map['uppercase'], uppercase);

    showSubLine = _toBool(map['showSubLine'], showSubLine);
    subText = _toString(map['subText'], subText);
    subScale = _toDouble(map['subScale'], subScale);

    showLogo = _toBool(map['showLogo'], showLogo);
    logoPlacement = _toString(map['logoPlacement'], logoPlacement);
    logoScale = _toDouble(map['logoScale'], logoScale);

    showHeadshot = _toBool(map['showHeadshot'], showHeadshot);
    headshotPlacement = _toString(map['headshotPlacement'], headshotPlacement);
    headshotScale = _toDouble(map['headshotScale'], headshotScale);

    overlayPadding = _toDouble(map['overlayPadding'], overlayPadding);
    rounding = _toDouble(map['rounding'], rounding);
    shadow = _toBool(map['shadow'], shadow);
    shadowBlur = _toDouble(map['shadowBlur'], shadowBlur);
    autoBrightness = _toBool(map['autoBrightness'], autoBrightness);
    selectedAspectRatio =
        _toString(map['selectedAspectRatio'], selectedAspectRatio);

    backgroundBlur = _toDouble(map['backgroundBlur'], backgroundBlur);
    backgroundBrightness =
        _toDouble(map['backgroundBrightness'], backgroundBrightness);

    notifyListeners();
  }

  // ====== Private helpers (guards) ======

  // OPT: defensive conversion helpers to avoid runtime errors without changing semantics.
  @pragma('vm:prefer-inline')
  String _toString(dynamic v, String fallback) {
    if (v is String) return v;
    if (v == null) return fallback;
    return v.toString();
  }

  @pragma('vm:prefer-inline')
  double _toDouble(dynamic v, double fallback) {
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is num) return v.toDouble();
    if (v is String) {
      final parsed = double.tryParse(v);
      if (parsed != null) return parsed;
    }
    return fallback;
  }

  @pragma('vm:prefer-inline')
  int _toInt(dynamic v, int fallback) {
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is num) return v.toInt();
    if (v is String) {
      final parsed = int.tryParse(v);
      if (parsed != null) return parsed;
    }
    return fallback;
  }

  @pragma('vm:prefer-inline')
  bool _toBool(dynamic v, bool fallback) {
    if (v is bool) return v;
    if (v is String) {
      final lower = v.toLowerCase();
      if (lower == 'true') return true;
      if (lower == 'false') return false;
    }
    return fallback;
  }

  @pragma('vm:prefer-inline')
  Color _toColor(dynamic v, Color fallback) {
    if (v is Color) return v;
    if (v is int) {
      // Accept raw ARGB or RGB ints if they slip through.
      // If it's 24-bit RGB, assume opaque.
      if (v <= 0xFFFFFF) return Color(0xFF000000 | v);
      return Color(v);
    }
    if (v is String) {
      // Accept "AARRGGBB" or "#AARRGGBB" or "RRGGBB" or "#RRGGBB"
      final s = v.startsWith('#') ? v.substring(1) : v;
      if (s.length == 8) {
        final parsed = int.tryParse('0x$s');
        if (parsed != null) return Color(parsed);
      } else if (s.length == 6) {
        final parsed = int.tryParse('0xFF$s');
        if (parsed != null) return Color(parsed);
      }
    }
    return fallback;
  }

  @pragma('vm:prefer-inline')
  Offset _placementToAnchor(String code) {
    switch (code) {
      case 'TL':
        return const Offset(0.0, 0.0);
      case 'TR':
        return const Offset(1.0, 0.0);
      case 'TC':
        return const Offset(0.5, 0.0);
      case 'BL':
        return const Offset(0.0, 1.0);
      case 'BR':
        return const Offset(1.0, 1.0);
      case 'BC':
        return const Offset(0.5, 1.0);
      default:
        return const Offset(1.0, 1.0);
    }
  }
}
