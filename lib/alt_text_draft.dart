import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class AltTextDraft extends ChangeNotifier {
  // Alt-text for single image or first image in carousel
  String _altText = '';

  // Alt-texts for carousel (array of alt-texts for each image)
  List<String> _altTexts = [];

  // Current validation state
  bool _isValid = false;
  String _validationMessage = '';

  // Getters
  String get altText => _altText;
  List<String> get altTexts => List.unmodifiable(_altTexts);
  bool get isValid => _isValid;
  String get validationMessage => _validationMessage;

  // Check if we have multiple images (carousel)
  bool get isCarousel => _altTexts.length > 1;

  // Get alt-text for specific image index
  String getAltTextForIndex(int index) {
    if (index < 0 || index >= _altTexts.length) return '';
    return _altTexts[index];
  }

  // Set alt-text for single image
  void setAltText(String text) {
    if (_altText == text) return;
    _altText = text;
    _validateAltText(text);
    notifyListeners();
  }

  // Set alt-texts for carousel
  void setAltTexts(List<String> texts) {
    if (_listsEqual(_altTexts, texts)) return;
    _altTexts = List.from(texts);
    _validateAltTexts();
    notifyListeners();
  }

  // Set alt-text for specific image in carousel
  void setAltTextForIndex(int index, String text) {
    if (index < 0) return;

    // Ensure list is large enough
    while (_altTexts.length <= index) {
      _altTexts.add('');
    }

    if (_altTexts[index] == text) return;
    _altTexts[index] = text;
    _validateAltTexts();
    notifyListeners();
  }

  // Initialize with number of images (for carousel)
  void initializeForImages(int imageCount) {
    if (imageCount <= 0) {
      _altTexts = [];
      _altText = '';
      _isValid = false;
      _validationMessage = 'No images to describe';
      notifyListeners();
      return;
    }

    if (imageCount == 1) {
      // Single image
      _altTexts = [_altText];
    } else {
      // Carousel - ensure we have alt-text for each image
      while (_altTexts.length < imageCount) {
        _altTexts.add('');
      }
      // Trim excess if we have more alt-texts than images
      if (_altTexts.length > imageCount) {
        _altTexts = _altTexts.take(imageCount).toList();
      }
    }

    _validateAltTexts();
    notifyListeners();
  }

  // Validation
  void _validateAltText(String text) {
    if (text.trim().isEmpty) {
      _isValid = false;
      _validationMessage = 'Alt-text is required for accessibility';
      return;
    }

    if (text.length < 140) {
      _isValid = false;
      _validationMessage =
          'Alt-text must be at least 140 characters (${text.length}/140)';
      return;
    }

    if (text.length > 250) {
      _isValid = false;
      _validationMessage =
          'Alt-text must be 250 characters or less (${text.length}/250)';
      return;
    }

    _isValid = true;
    _validationMessage = 'Alt-text is valid (${text.length}/250)';
  }

  void _validateAltTexts() {
    if (_altTexts.isEmpty) {
      _isValid = false;
      _validationMessage = 'No images to describe';
      return;
    }

    // Check if all alt-texts are valid
    for (int i = 0; i < _altTexts.length; i++) {
      final text = _altTexts[i];
      if (text.trim().isEmpty) {
        _isValid = false;
        _validationMessage = 'Alt-text is required for image ${i + 1}';
        return;
      }

      if (text.length < 140) {
        _isValid = false;
        _validationMessage =
            'Alt-text for image ${i + 1} must be at least 140 characters (${text.length}/140)';
        return;
      }

      if (text.length > 250) {
        _isValid = false;
        _validationMessage =
            'Alt-text for image ${i + 1} must be 250 characters or less (${text.length}/250)';
        return;
      }
    }

    _isValid = true;
    _validationMessage = 'All alt-texts are valid';
  }

  // Clear all alt-texts
  void clear() {
    _altText = '';
    _altTexts = [];
    _isValid = false;
    _validationMessage = '';
    notifyListeners();
  }

  // Helper to check if two lists are equal
  bool _listsEqual(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  // Get alt-texts as array for database storage
  List<String> getAltTextsForStorage() {
    if (_altTexts.isEmpty) return [];
    return List.from(_altTexts);
  }

  // Load alt-texts from database storage
  void loadFromStorage(List<String>? storedAltTexts) {
    if (storedAltTexts == null || storedAltTexts.isEmpty) {
      clear();
      return;
    }

    _altTexts = List.from(storedAltTexts);
    if (_altTexts.length == 1) {
      _altText = _altTexts[0];
    } else if (_altTexts.isNotEmpty) {
      _altText = _altTexts[0]; // Use first as primary
    }

    _validateAltTexts();
    notifyListeners();
  }

  // Save alt-texts to SharedPreferences
  Future<void> saveToPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = {
        'altText': _altText,
        'altTexts': _altTexts,
        'isValid': _isValid,
        'validationMessage': _validationMessage,
      };
      await prefs.setString('alt_text_draft', jsonEncode(data));
    } catch (e) {
      debugPrint('Failed to save alt-text draft: $e');
    }
  }

  // Load alt-texts from SharedPreferences
  Future<void> loadFromPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final dataString = prefs.getString('alt_text_draft');
      if (dataString == null) return;

      final data = jsonDecode(dataString) as Map<String, dynamic>;
      _altText = data['altText'] ?? '';
      _altTexts = List<String>.from(data['altTexts'] ?? []);
      _isValid = data['isValid'] ?? false;
      _validationMessage = data['validationMessage'] ?? '';

      notifyListeners();
    } catch (e) {
      debugPrint('Failed to load alt-text draft: $e');
    }
  }

  // Clear alt-texts from SharedPreferences
  Future<void> clearPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('alt_text_draft');
    } catch (e) {
      debugPrint('Failed to clear alt-text draft: $e');
    }
  }

  // Enhanced setAltText with auto-save
  void setAltTextWithSave(String text) {
    setAltText(text);
    saveToPreferences();
  }

  // Enhanced setAltTexts with auto-save
  void setAltTextsWithSave(List<String> texts) {
    setAltTexts(texts);
    saveToPreferences();
  }

  // Enhanced setAltTextForIndex with auto-save
  void setAltTextForIndexWithSave(int index, String text) {
    setAltTextForIndex(index, text);
    saveToPreferences();
  }

  // Enhanced clear with auto-save
  void clearWithSave() {
    clear();
    clearPreferences();
  }
}
