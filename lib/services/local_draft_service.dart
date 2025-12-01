import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class LocalDraftService {
  static const String _draftKey = "local_recipe_drafts";

  /// Save or overwrite a draft (must include name)
  static Future<void> saveDraft({
    required String name,
    required String ingredients,
    required String directions,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    Map<String, dynamic> drafts = {};

    final existing = prefs.getString(_draftKey);
    if (existing != null) drafts = jsonDecode(existing);

    drafts[name] = {
      "name": name,
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
    return drafts[name];
  }

  /// Delete a draft
  static Future<void> deleteDraft(String name) async {
    final prefs = await SharedPreferences.getInstance();
    final drafts = await getDrafts();

    drafts.remove(name);

    await prefs.setString(_draftKey, jsonEncode(drafts));
  }

  /// Clear all drafts
  static Future<void> clearDrafts() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_draftKey);
  }
}
