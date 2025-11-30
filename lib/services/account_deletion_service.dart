// lib/services/account_deletion_service.dart
// Handles COMPLETE user account deletion from all tables + R2 storage cleanup

import 'dart:convert';

import '../config/app_config.dart';

import 'database_service_core.dart';          // auth + currentUserId
import 'profile_service.dart';           // for getUserProfile()


class AccountDeletionService {

  // ==================================================
  // DELETE ACCOUNT COMPLETELY
  // ==================================================
  static Future<void> deleteAccountCompletely() async {
    DatabaseServiceCore.ensureUserAuthenticated();
    final userId = DatabaseServiceCore.currentUserId!;

    try {
      AppConfig.debugPrint('🗑️ Starting account deletion for $userId');

      // --------------------------------------------------
      // 1) GET PROFILE (to read picture URLs)
      // --------------------------------------------------
      AppConfig.debugPrint('📋 Fetching profile...');
      final profile = await ProfileService.getUserProfile(userId);

      final picturesJson = profile?['pictures'];
      final profilePicUrl = profile?['profile_picture'];
      final bgPicUrl = profile?['profile_background'];

      // --------------------------------------------------
      // 2) DELETE ALL R2 STORAGE FILES (gallery, profile, background)
      // --------------------------------------------------
      // Gallery
      if (picturesJson != null && picturesJson.isNotEmpty) {
        try {
          final pics = List<String>.from(jsonDecode(picturesJson));

          AppConfig.debugPrint('🗑️ Deleting ${pics.length} gallery pictures...');
          for (final url in pics) {
            try {
              await DatabaseServiceCore.deleteFileByPublicUrl(url);
            } catch (e) {
              AppConfig.debugPrint('⚠️ Failed to delete gallery picture: $e');
            }
          }
        } catch (e) {
          AppConfig.debugPrint('⚠️ Failed to parse gallery JSON: $e');
        }
      }

      // Profile picture
      if (profilePicUrl is String && profilePicUrl.isNotEmpty) {
        try {
          AppConfig.debugPrint('🗑️ Deleting profile picture...');
          await DatabaseServiceCore.deleteFileByPublicUrl(profilePicUrl);
        } catch (e) {
          AppConfig.debugPrint('⚠️ Failed to delete profile picture: $e');
        }
      }

      // Background picture
      if (bgPicUrl is String && bgPicUrl.isNotEmpty) {
        try {
          AppConfig.debugPrint('🗑️ Deleting background picture...');
          await DatabaseServiceCore.deleteFileByPublicUrl(bgPicUrl);
        } catch (e) {
          AppConfig.debugPrint('⚠️ Failed to delete background picture: $e');
        }
      }

      // --------------------------------------------------
      // 3) DELETE ALL DATABASE DATA (children → parents)
      // --------------------------------------------------
      AppConfig.debugPrint('🗑️ Deleting database rows...');

      // Grocery items
      await _safeDelete('grocery_items', {'user_id': userId});

      // Submitted recipes
      await _safeDelete('submitted_recipes', {'user_id': userId});

      // Favorite recipes
      await _safeDelete('favorite_recipes', {'user_id': userId});

      // Achievements
      await _safeDelete('user_achievements', {'user_id': userId});

      // Recipe ratings
      await _safeDelete('recipe_ratings', {'user_id': userId});

      // Recipe comments
      await _safeDelete('recipe_comments', {'user_id': userId});

      // Comment likes
      await _safeDelete('comment_likes', {'user_id': userId});

      // Friend requests (sender)
      await _safeDelete('friend_requests', {'sender': userId});

      // Friend requests (receiver)
      await _safeDelete('friend_requests', {'receiver': userId});

      // Messages (sent)
      await _safeDelete('messages', {'sender': userId});

      // Messages (received)
      await _safeDelete('messages', {'receiver': userId});

      // Finally: user profile
      await _safeDelete('user_profiles', {'id': userId});

      // --------------------------------------------------
      // 4) CLEAR LOCAL CACHE
      // --------------------------------------------------
      AppConfig.debugPrint('🧹 Clearing local cache...');
      await DatabaseServiceCore.clearAllUserCache();

      AppConfig.debugPrint('✅ Account deletion successfully completed.');
    } catch (e) {
      AppConfig.debugPrint('❌ deleteAccountCompletely error: $e');
      throw Exception("Failed to delete account: $e");
    }
  }

  // ==================================================
  // Helper: SAFE DELETE WRAPPER
  // ==================================================
  static Future<void> _safeDelete(
    String table,
    Map<String, dynamic> filters,
  ) async {
    try {
      await DatabaseServiceCore.workerQuery(
        action: 'delete',
        table: table,
        filters: filters,
      );
      AppConfig.debugPrint('✔ Deleted $table (filters: $filters)');
    } catch (e) {
      AppConfig.debugPrint('⚠️ Error deleting $table: $e');
    }
  }
}
