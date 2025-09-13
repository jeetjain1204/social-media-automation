import 'package:flutter/material.dart';

/// Holds the current selection and prompts for idea generation flows (text/image).
/// Note: We keep the original data shape and keys. This class only manages state.
///
/// Contract:
/// - `update(key, value)` sets a single field and now *notifies* listeners. // OPT: bug fix for UI not updating
/// - `resetAll()` clears image-related selections but intentionally leaves `selectedTextIdea` unchanged (preserved behavior).
class IdeaNotifier extends ChangeNotifier {
  // TEXT CONTENT
  String? selectedTextIdea;
  String? selectedImageIdea;
  String? selectedImageSource;
  Map<String, dynamic>? imageCustomization;
  String? typedPrompt;

  // BACKGROUND
  String? selectedBackgroundUrl;
  bool isAIGeneratedBackground = false;
  String backgroundPrompt = "";

  // TAB SELECTION
  String selectedTab = 'Image';
  String selectedImageTab = 'Quote';

  /// Update a single property by key and notify listeners.
  /// Behavior: No data shape changes; callers can keep using the same keys.
  void update(String key, dynamic value) {
    switch (key) {
      case 'selectedTextIdea':
        selectedTextIdea = value;
        break;
      case 'selectedImageIdea':
        selectedImageIdea = value;
        break;
      case 'selectedImageSource':
        selectedImageSource = value;
        break;
      case 'customization':
        imageCustomization = value;
        break;
      case 'typedPrompt':
        typedPrompt = value;
        break;
      case 'selectedBackgroundUrl':
        selectedBackgroundUrl = value;
        break;
      case 'isAIGeneratedBackground':
        isAIGeneratedBackground = value;
        break;
      case 'backgroundPrompt':
        backgroundPrompt = value;
        break;
      case 'selectedImageTab':
        selectedImageTab = value;
        break;
      case 'selectedTab':
        selectedTab = value;
        break;
    }
    notifyListeners(); // OPT: ensure UI rebuilds after state updates
  }

  /// Reset only image-related state (preserving original behavior: `selectedTextIdea` stays).
  void resetAll() {
    selectedImageIdea = null;
    selectedImageSource = null;
    imageCustomization = null;
    typedPrompt = null;
    selectedBackgroundUrl = null;
    isAIGeneratedBackground = false;
    backgroundPrompt = "";
    notifyListeners();
  }
}
