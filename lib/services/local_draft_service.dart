// lib/services/local_draft_service.dart
// ✅ FIXED: Added proper title capitalization for recipe names

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class LocalDraftService {
  static const String _draftKey = "local_recipe_drafts";

  /// Capitalize each word in a string (e.g., "brunswick stew" → "Brunswick Stew")
  static String _capitalizeTitle(String text) {
    if (text.isEmpty) return text;
    
    return text
        .split(' ')
        .map((word) {
          if (word.isEmpty) return word;
          return word[0].toUpperCase() + word.substring(1).toLowerCase();
        })
        .join(' ');
  }

  /// Save or overwrite a draft (must include name)
  /// ✅ NOW: Automatically capitalizes recipe names
  static Future<void> saveDraft({
    required String name,
    required String ingredients,
    required String directions,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    Map<String, dynamic> drafts = {};
    
    final existing = prefs.getString(_draftKey);
    if (existing != null) drafts = jsonDecode(existing);

    // ✅ NEW: Capitalize the recipe name before saving
    final capitalizedName = _capitalizeTitle(name.trim());

    drafts[capitalizedName] = {
      "name": capitalizedName,
      "ingredients": ingredients,
      "directions": directions,
      "updated_at": DateTime.now().toIso8601String(),
    };

    await prefs.setString(_draftKey, jsonEncode(drafts));
  }

  /// Get all drafts
  static Future<Map<String, dynamic>> getDrafts() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(_draftKey);
    if (data == null) return {};
    return jsonDecode(data);
  }

  /// Load a single draft
  static Future<Map<String, dynamic>?> loadDraft(String name) async {
    final drafts = await getDrafts();
    
    // ✅ NEW: Try both original name and capitalized version
    if (drafts.containsKey(name)) {
      return drafts[name];
    }
    
    final capitalizedName = _capitalizeTitle(name);
    if (drafts.containsKey(capitalizedName)) {
      return drafts[capitalizedName];
    }
    
    return null;
  }

  /// Delete a draft
  static Future<void> deleteDraft(String name) async {
    final prefs = await SharedPreferences.getInstance();
    final drafts = await getDrafts();
    
    // ✅ NEW: Try to delete both versions (original and capitalized)
    drafts.remove(name);
    drafts.remove(_capitalizeTitle(name));
    
    await prefs.setString(_draftKey, jsonEncode(drafts));
  }

  /// Clear all drafts
  static Future<void> clearDrafts() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_draftKey);
  }
}