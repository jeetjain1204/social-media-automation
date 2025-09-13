// ignore_for_file: non_constant_identifier_names

// OPT: Use correct import for Uint8List.
import 'dart:typed_data';

import 'package:flutter/material.dart';

class BrandProfileDraft extends ChangeNotifier {
  // ---------- Core fields (unchanged API) ----------
  String persona = '';
  String category = '';
  String subcategory = '';
  String primary_goal = '';
  String brand_name = '';
  Uint8List? brand_logo_bytes;
  String? brand_logo_path;
  String primary_color = '#004aad';
  final voice_tags = <String>[];
  final content_types = <String>[];
  int target_posts_per_week = 0;
  String timezone = '';

  bool updatedPersona = false;
  bool updatedCategory = false;
  bool updatedSubcategory = false;

  // later steps
  String voiceTone = '';
  String description = '';
  String targetAudience = '';
  final topics = <String>[];
  final goals = <String>[];

  // ---------- Perf: coalesce notifies for multi-field updates ----------
  // OPT: Public flag to avoid underscore per your convention. When true, notify() becomes a no-op
  // and a final notify is sent after updateMany finishes.
  bool batching = false; // OPT: replaces a private _batching

  // OPT: Keep your helper name but make it batching-aware.
  void notify() {
    if (batching) return; // coalesce while batching
    notifyListeners();
  }

  // OPT: Batch multiple mutations into a single notify to reduce rebuild storms.
  // Use: draft.updateMany(() { draft.persona = 'x'; draft.category = 'y'; });
  void updateMany(void Function() fn) {
    final wasBatching = batching;
    batching = true;
    try {
      fn();
    } finally {
      batching = wasBatching;
      notify(); // one final notify
    }
  }

  // ---------- Topic helpers ----------
  bool addTopic(String topic) {
    if (topic.isEmpty) return false; // OPT: cheap guard
    if (!topics.contains(topic) && topics.length < 10) {
      topics.add(topic);
      notify();
      return true;
    }
    return false;
  }

  bool removeTopic(String topic) {
    final removed = topics.remove(topic);
    if (removed) notify();
    return removed;
  }

  // ---------- Goal helpers ----------
  bool toggleGoal(String goal) {
    if (goals.contains(goal)) {
      goals.remove(goal);
      notify();
      return false;
    } else {
      goals.add(goal);
      notify();
      return true;
    }
  }

  // ---------- List helpers to keep notifications consistent ----------
  bool addVoiceTag(String tag) {
    if (tag.isEmpty) return false;
    if (!voice_tags.contains(tag)) {
      voice_tags.add(tag);
      notify();
      return true;
    }
    return false;
  }

  bool removeVoiceTag(String tag) {
    final removed = voice_tags.remove(tag);
    if (removed) notify();
    return removed;
  }

  bool toggleContentType(String t) {
    if (content_types.contains(t)) {
      content_types.remove(t);
      notify();
      return false;
    } else {
      content_types.add(t);
      notify();
      return true;
    }
  }

  // ---------- Value setters that avoid redundant notifies ----------
  bool setPersona(String v) {
    if (persona == v) return false;
    persona = v;
    notify();
    return true;
  }

  bool setCategory(String v) {
    if (category == v) return false;
    category = v;
    notify();
    return true;
  }

  bool setSubcategory(String v) {
    if (subcategory == v) return false;
    subcategory = v;
    notify();
    return true;
  }

  bool setPrimaryGoal(String v) {
    if (primary_goal == v) return false;
    primary_goal = v;
    notify();
    return true;
  }

  bool setBrandName(String v) {
    if (brand_name == v) return false;
    brand_name = v;
    notify();
    return true;
  }

  bool setBrandLogoBytes(Uint8List? bytes) {
    if (identical(brand_logo_bytes, bytes)) return false;
    brand_logo_bytes = bytes;
    notify();
    return true;
  }

  bool setBrandLogoPath(String? path) {
    if (brand_logo_path == path) return false;
    brand_logo_path = path;
    notify();
    return true;
  }

  bool setPrimaryColor(String hex) {
    if (primary_color == hex) return false;
    primary_color = hex;
    notify();
    return true;
  }

  bool setTargetPostsPerWeek(int v) {
    if (target_posts_per_week == v) return false;
    target_posts_per_week = v;
    notify();
    return true;
  }

  bool setTimezone(String v) {
    if (timezone == v) return false;
    timezone = v;
    notify();
    return true;
  }

  bool setVoiceTone(String v) {
    if (voiceTone == v) return false;
    voiceTone = v;
    notify();
    return true;
  }

  bool setDescription(String v) {
    if (description == v) return false;
    description = v;
    notify();
    return true;
  }

  bool setTargetAudience(String v) {
    if (targetAudience == v) return false;
    targetAudience = v;
    notify();
    return true;
  }

  bool setUpdatedPersona(bool v) {
    if (updatedPersona == v) return false;
    updatedPersona = v;
    notify();
    return true;
  }

  bool setUpdatedCategory(bool v) {
    if (updatedCategory == v) return false;
    updatedCategory = v;
    notify();
    return true;
  }

  bool setUpdatedSubcategory(bool v) {
    if (updatedSubcategory == v) return false;
    updatedSubcategory = v;
    notify();
    return true;
  }

  // ---------- Clear with change detection ----------
  void clear() {
    // OPT: Only notify if something actually changed.
    var changed = false;

    void setIf<T>(T current, T next, void Function() apply) {
      if (current != next) {
        apply();
        changed = true;
      }
    }

    updateMany(() {
      setIf(persona, '', () => persona = '');
      setIf(category, '', () => category = '');
      setIf(subcategory, '', () => subcategory = '');
      setIf(primary_goal, '', () => primary_goal = '');
      setIf(brand_name, '', () => brand_name = '');
      setIf<Uint8List?>(brand_logo_bytes, null, () => brand_logo_bytes = null);
      setIf(brand_logo_path, null, () => brand_logo_path = null);
      setIf(primary_color, '#004aad', () => primary_color = '#004aad');

      if (voice_tags.isNotEmpty) {
        voice_tags.clear();
        changed = true;
      }
      if (content_types.isNotEmpty) {
        content_types.clear();
        changed = true;
      }

      setIf(target_posts_per_week, 0, () => target_posts_per_week = 0);
      setIf(timezone, '', () => timezone = '');

      setIf(voiceTone, '', () => voiceTone = '');
      setIf(description, '', () => description = '');
      setIf(targetAudience, '', () => targetAudience = '');

      if (topics.isNotEmpty) {
        topics.clear();
        changed = true;
      }
      if (goals.isNotEmpty) {
        goals.clear();
        changed = true;
      }

      setIf(updatedPersona, false, () => updatedPersona = false);
      setIf(updatedCategory, false, () => updatedCategory = false);
      setIf(updatedSubcategory, false, () => updatedSubcategory = false);
    });

    // OPT: updateMany already notified once; no extra notify needed.
    // If nothing changed, suppress notification entirely.
    if (!changed) {
      // No-op: avoid unnecessary rebuilds when clear() called on a fresh draft.
    }
  }
}
