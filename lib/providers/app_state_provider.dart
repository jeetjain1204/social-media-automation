// lib/providers/app_state_provider.dart
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Unified app state provider that consolidates multiple providers
/// This reduces the number of providers from 5 to 1, improving performance
class AppStateProvider extends ChangeNotifier {
  // ====== PROFILE STATE ======
  bool _profileUpdated = false;
  bool get profileUpdated => _profileUpdated;

  void notifyProfileUpdated() {
    _profileUpdated = !_profileUpdated; // Toggle to trigger rebuilds
    notifyListeners();
  }

  // ====== IDEA GENERATION STATE ======
  String? _selectedTextIdea;
  String? _selectedImageIdea;
  String? _selectedImageSource;
  Map<String, dynamic>? _imageCustomization;
  String? _typedPrompt;
  String? _selectedBackgroundUrl;
  bool _isAIGeneratedBackground = false;
  String _backgroundPrompt = "";
  String _selectedTab = 'Image';
  String _selectedImageTab = 'Quote';

  // Getters
  String? get selectedTextIdea => _selectedTextIdea;
  String? get selectedImageIdea => _selectedImageIdea;
  String? get selectedImageSource => _selectedImageSource;
  Map<String, dynamic>? get imageCustomization => _imageCustomization;
  String? get typedPrompt => _typedPrompt;
  String? get selectedBackgroundUrl => _selectedBackgroundUrl;
  bool get isAIGeneratedBackground => _isAIGeneratedBackground;
  String get backgroundPrompt => _backgroundPrompt;
  String get selectedTab => _selectedTab;
  String get selectedImageTab => _selectedImageTab;

  // Setters with change detection
  void updateIdeaState(String key, dynamic value) {
    bool changed = false;

    switch (key) {
      case 'selectedTextIdea':
        if (_selectedTextIdea != value) {
          _selectedTextIdea = value;
          changed = true;
        }
        break;
      case 'selectedImageIdea':
        if (_selectedImageIdea != value) {
          _selectedImageIdea = value;
          changed = true;
        }
        break;
      case 'selectedImageSource':
        if (_selectedImageSource != value) {
          _selectedImageSource = value;
          changed = true;
        }
        break;
      case 'customization':
        if (_imageCustomization != value) {
          _imageCustomization = value;
          changed = true;
        }
        break;
      case 'typedPrompt':
        if (_typedPrompt != value) {
          _typedPrompt = value;
          changed = true;
        }
        break;
      case 'selectedBackgroundUrl':
        if (_selectedBackgroundUrl != value) {
          _selectedBackgroundUrl = value;
          changed = true;
        }
        break;
      case 'isAIGeneratedBackground':
        if (_isAIGeneratedBackground != value) {
          _isAIGeneratedBackground = value;
          changed = true;
        }
        break;
      case 'backgroundPrompt':
        if (_backgroundPrompt != value) {
          _backgroundPrompt = value;
          changed = true;
        }
        break;
      case 'selectedImageTab':
        if (_selectedImageTab != value) {
          _selectedImageTab = value;
          changed = true;
        }
        break;
      case 'selectedTab':
        if (_selectedTab != value) {
          _selectedTab = value;
          changed = true;
        }
        break;
    }

    if (changed) notifyListeners();
  }

  void resetIdeaState() {
    bool changed = false;

    if (_selectedImageIdea != null) {
      _selectedImageIdea = null;
      changed = true;
    }
    if (_selectedImageSource != null) {
      _selectedImageSource = null;
      changed = true;
    }
    if (_imageCustomization != null) {
      _imageCustomization = null;
      changed = true;
    }
    if (_typedPrompt != null) {
      _typedPrompt = null;
      changed = true;
    }
    if (_selectedBackgroundUrl != null) {
      _selectedBackgroundUrl = null;
      changed = true;
    }
    if (_isAIGeneratedBackground) {
      _isAIGeneratedBackground = false;
      changed = true;
    }
    if (_backgroundPrompt.isNotEmpty) {
      _backgroundPrompt = "";
      changed = true;
    }

    if (changed) notifyListeners();
  }

  // ====== FOREGROUND/UI STATE ======
  String _text = "Your quote goes here.";
  double _textBoxFactor = 0.84;
  String _fontFamily = "Roboto";
  int _fontWeight = 400;
  double _manualFont = 28;
  double _lineHeight = 1.2;
  String _textAlign = 'C';
  Color _textColor = Colors.black;
  bool _italic = false;
  bool _uppercase = false;
  bool _showSubLine = true;
  String _subText = "Author Name";
  double _subScale = 0.6;
  ui.Image? _logoImage;
  bool _showLogo = true;
  String _logoPlacement = "TL";
  double _logoScale = 0.12;
  ui.Image? _headshotImage;
  bool _showHeadshot = true;
  String _headshotPlacement = "BR";
  double _headshotScale = 0.12;
  double _overlayPadding = 0.0;
  double _rounding = 16;
  bool _shadow = true;
  double _shadowBlur = 4;
  bool _autoBrightness = true;
  String _selectedAspectRatio = '1:1';
  double _backgroundBlur = 0;
  double _backgroundBrightness = 100;

  // Getters
  String get text => _text;
  double get textBoxFactor => _textBoxFactor;
  String get fontFamily => _fontFamily;
  int get fontWeight => _fontWeight;
  double get manualFont => _manualFont;
  double get lineHeight => _lineHeight;
  String get textAlign => _textAlign;
  Color get textColor => _textColor;
  bool get italic => _italic;
  bool get uppercase => _uppercase;
  bool get showSubLine => _showSubLine;
  String get subText => _subText;
  double get subScale => _subScale;
  ui.Image? get logoImage => _logoImage;
  bool get showLogo => _showLogo;
  String get logoPlacement => _logoPlacement;
  double get logoScale => _logoScale;
  ui.Image? get headshotImage => _headshotImage;
  bool get showHeadshot => _showHeadshot;
  String get headshotPlacement => _headshotPlacement;
  double get headshotScale => _headshotScale;
  double get overlayPadding => _overlayPadding;
  double get rounding => _rounding;
  bool get shadow => _shadow;
  double get shadowBlur => _shadowBlur;
  bool get autoBrightness => _autoBrightness;
  String get selectedAspectRatio => _selectedAspectRatio;
  double get backgroundBlur => _backgroundBlur;
  double get backgroundBrightness => _backgroundBrightness;

  // Convenience getters
  TextAlign get textAlignResolved {
    switch (_textAlign) {
      case 'L':
        return TextAlign.left;
      case 'R':
        return TextAlign.right;
      default:
        return TextAlign.center;
    }
  }

  Offset get logoAnchor => _placementToAnchor(_logoPlacement);
  Offset get headshotAnchor => _placementToAnchor(_headshotPlacement);

  // Update foreground state
  void updateForegroundState(String key, dynamic value) {
    bool changed = false;

    switch (key) {
      case 'Text':
        if (_text != value) {
          _text = _toString(value, _text);
          changed = true;
        }
        break;
      case 'textBoxFactor':
        final newValue = _toDouble(value, _textBoxFactor);
        if (_textBoxFactor != newValue) {
          _textBoxFactor = newValue;
          changed = true;
        }
        break;
      case 'fontFamily':
        if (_fontFamily != value) {
          _fontFamily = _toString(value, _fontFamily);
          changed = true;
        }
        break;
      case 'fontWeight':
        final newValue = _toInt(value, _fontWeight);
        if (_fontWeight != newValue) {
          _fontWeight = newValue;
          changed = true;
        }
        break;
      case 'manualFont':
        final newValue = _toDouble(value, _manualFont);
        if (_manualFont != newValue) {
          _manualFont = newValue;
          changed = true;
        }
        break;
      case 'lineHeight':
        final newValue = _toDouble(value, _lineHeight);
        if (_lineHeight != newValue) {
          _lineHeight = newValue;
          changed = true;
        }
        break;
      case 'textAlign':
        if (_textAlign != value) {
          _textAlign = _toString(value, _textAlign);
          changed = true;
        }
        break;
      case 'textColor':
        final newValue = _toColor(value, _textColor);
        if (_textColor != newValue) {
          _textColor = newValue;
          changed = true;
        }
        break;
      case 'italic':
        final newValue = _toBool(value, _italic);
        if (_italic != newValue) {
          _italic = newValue;
          changed = true;
        }
        break;
      case 'uppercase':
        final newValue = _toBool(value, _uppercase);
        if (_uppercase != newValue) {
          _uppercase = newValue;
          changed = true;
        }
        break;
      case 'showSubLine':
        final newValue = _toBool(value, _showSubLine);
        if (_showSubLine != newValue) {
          _showSubLine = newValue;
          changed = true;
        }
        break;
      case 'subText':
        if (_subText != value) {
          _subText = _toString(value, _subText);
          changed = true;
        }
        break;
      case 'subScale':
        final newValue = _toDouble(value, _subScale);
        if (_subScale != newValue) {
          _subScale = newValue;
          changed = true;
        }
        break;
      case 'showLogo':
        final newValue = _toBool(value, _showLogo);
        if (_showLogo != newValue) {
          _showLogo = newValue;
          changed = true;
        }
        break;
      case 'logoPlacement':
        if (_logoPlacement != value) {
          _logoPlacement = _toString(value, _logoPlacement);
          changed = true;
        }
        break;
      case 'logoScale':
        final newValue = _toDouble(value, _logoScale);
        if (_logoScale != newValue) {
          _logoScale = newValue;
          changed = true;
        }
        break;
      case 'logoImage':
        if (_logoImage != value) {
          _logoImage = value as ui.Image?;
          changed = true;
        }
        break;
      case 'showHeadshot':
        final newValue = _toBool(value, _showHeadshot);
        if (_showHeadshot != newValue) {
          _showHeadshot = newValue;
          changed = true;
        }
        break;
      case 'headshotPlacement':
        if (_headshotPlacement != value) {
          _headshotPlacement = _toString(value, _headshotPlacement);
          changed = true;
        }
        break;
      case 'headshotScale':
        final newValue = _toDouble(value, _headshotScale);
        if (_headshotScale != newValue) {
          _headshotScale = newValue;
          changed = true;
        }
        break;
      case 'headshotImage':
        if (_headshotImage != value) {
          _headshotImage = value as ui.Image?;
          changed = true;
        }
        break;
      case 'overlayPadding':
        final newValue = _toDouble(value, _overlayPadding);
        if (_overlayPadding != newValue) {
          _overlayPadding = newValue;
          changed = true;
        }
        break;
      case 'rounding':
        final newValue = _toDouble(value, _rounding);
        if (_rounding != newValue) {
          _rounding = newValue;
          changed = true;
        }
        break;
      case 'shadow':
        final newValue = _toBool(value, _shadow);
        if (_shadow != newValue) {
          _shadow = newValue;
          changed = true;
        }
        break;
      case 'shadowBlur':
        final newValue = _toDouble(value, _shadowBlur);
        if (_shadowBlur != newValue) {
          _shadowBlur = newValue;
          changed = true;
        }
        break;
      case 'autoBrightness':
        final newValue = _toBool(value, _autoBrightness);
        if (_autoBrightness != newValue) {
          _autoBrightness = newValue;
          changed = true;
        }
        break;
      case 'selectedAspectRatio':
        if (_selectedAspectRatio != value) {
          _selectedAspectRatio = _toString(value, _selectedAspectRatio);
          changed = true;
        }
        break;
      case 'backgroundBlur':
        final newValue = _toDouble(value, _backgroundBlur);
        if (_backgroundBlur != newValue) {
          _backgroundBlur = newValue;
          changed = true;
        }
        break;
      case 'backgroundBrightness':
        final newValue = _toDouble(value, _backgroundBrightness);
        if (_backgroundBrightness != newValue) {
          _backgroundBrightness = newValue;
          changed = true;
        }
        break;
    }

    if (changed) notifyListeners();
  }

  // ====== CLEAR STATE ======
  bool _shouldClear = false;
  bool get shouldClear => _shouldClear;

  void triggerClear() {
    _shouldClear = true;
    notifyListeners();
  }

  void acknowledgeClear() {
    _shouldClear = false;
  }

  bool consumeClear() {
    if (_shouldClear) {
      _shouldClear = false;
      return true;
    }
    return false;
  }

  // ====== HELPER METHODS ======
  String _toString(dynamic v, String fallback) {
    if (v is String) return v;
    if (v == null) return fallback;
    return v.toString();
  }

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

  bool _toBool(dynamic v, bool fallback) {
    if (v is bool) return v;
    if (v is String) {
      final lower = v.toLowerCase();
      if (lower == 'true') return true;
      if (lower == 'false') return false;
    }
    return fallback;
  }

  Color _toColor(dynamic v, Color fallback) {
    if (v is Color) return v;
    if (v is int) {
      if (v <= 0xFFFFFF) return Color(0xFF000000 | v);
      return Color(v);
    }
    if (v is String) {
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
