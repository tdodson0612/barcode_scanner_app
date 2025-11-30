// lib/services/picture_service.dart
// Handles all picture uploads, deletes, and getters (profile, background, gallery)

import 'dart:convert';
import 'dart:io';

import '../config/app_config.dart';
import 'auth_service.dart';
import 'profile_service.dart';
import 'database_service_core.dart';     // worker upload/delete + caching

class PictureService {

  // ==================================================
  // UPLOAD PROFILE PICTURE
  // ==================================================

  static Future<String> uploadProfilePicture(File imageFile) async {
    final userId = AuthService.currentUserId;
    if (userId == null) {
      throw Exception('Please sign in to continue');
    }
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final fileName = 'profile_$timestamp.jpg';
    final filePath = '$userId/$fileName';

    try {
      // Validate size
      final fileSize = await imageFile.length();
      if (fileSize > 10 * 1024 * 1024) {
        throw Exception('Image file too large. Max 10MB.');
      }

      // Encode image
      final bytes = await imageFile.readAsBytes();
      final base64Image = base64Encode(bytes);

      // Upload to R2
      final publicUrl = await DatabaseServiceCore.workerStorageUpload(
        bucket: 'profile-pictures',
        path: filePath,
        base64Data: base64Image,
        contentType: 'image/jpeg',
      );

      // Update profile
      await DatabaseServiceCore.workerQuery(
        action: 'update',
        table: 'user_profiles',
        filters: {'id': userId},
        data: {
          'profile_picture': publicUrl,
          'updated_at': DateTime.now().toIso8601String(),
        },
      );

      // Clear cache
      await DatabaseServiceCore.clearCache('cache_user_profile_$userId');
      await DatabaseServiceCore.clearCache('cache_profile_timestamp_$userId');

      return publicUrl;
    } catch (e) {
      AppConfig.debugPrint('❌ uploadProfilePicture error: $e');
      throw Exception('Failed to upload profile picture: $e');
    }
  }

  // ==================================================
  // UPLOAD BACKGROUND PICTURE
  // ==================================================

  static Future<String> uploadBackgroundPicture(File imageFile) async {
    final userId = AuthService.currentUserId;
    if (userId == null) {
      throw Exception('Please sign in to continue');
    }
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final fileName = 'background_$timestamp.jpg';
    final filePath = '$userId/$fileName';

    try {
      final fileSize = await imageFile.length();
      if (fileSize > 10 * 1024 * 1024) {
        throw Exception('Image file too large. Max 10MB.');
      }

      final bytes = await imageFile.readAsBytes();
      final base64Image = base64Encode(bytes);

      final publicUrl = await DatabaseServiceCore.workerStorageUpload(
        bucket: 'background-pictures',
        path: filePath,
        base64Data: base64Image,
        contentType: 'image/jpeg',
      );

      await DatabaseServiceCore.workerQuery(
        action: 'update',
        table: 'user_profiles',
        filters: {'id': userId},
        data: {
          'profile_background': publicUrl,
          'updated_at': DateTime.now().toIso8601String(),
        },
      );

      await DatabaseServiceCore.clearCache('cache_user_profile_$userId');
      await DatabaseServiceCore.clearCache('cache_profile_timestamp_$userId');

      return publicUrl;
    } catch (e) {
      AppConfig.debugPrint('❌ uploadBackgroundPicture error: $e');
      throw Exception('Failed to upload background picture: $e');
    }
  }

  // ==================================================
  // UPLOAD PICTURE TO PHOTO ALBUM
  // ==================================================

  static Future<String> uploadPicture(File imageFile) async {
    final userId = AuthService.currentUserId;
    if (userId == null) {
      throw Exception('Please sign in to continue');
    }
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final fileName = 'picture_$timestamp.jpg';
    final filePath = '$userId/$fileName';

    try {
      final fileSize = await imageFile.length();
      if (fileSize > 10 * 1024 * 1024) {
        throw Exception('Image too large. Max 10MB.');
      }

      final bytes = await imageFile.readAsBytes();
      final base64Image = base64Encode(bytes);

      final publicUrl = await DatabaseServiceCore.workerStorageUpload(
        bucket: 'photo-album',
        path: filePath,
        base64Data: base64Image,
        contentType: 'image/jpeg',
      );

      // Get existing pictures
      final profile = await ProfileService.getCurrentUserProfile();
      List<String> pictures = [];

      final existing = profile?['pictures'];
      if (existing != null && existing.isNotEmpty) {
        try {
          pictures = List<String>.from(jsonDecode(existing));
        } catch (_) {}
      }

      pictures.add(publicUrl);

      // Save updated picture list
      await DatabaseServiceCore.workerQuery(
        action: 'update',
        table: 'user_profiles',
        filters: {'id': userId},
        data: {
          'pictures': jsonEncode(pictures),
          'updated_at': DateTime.now().toIso8601String(),
        },
      );

      await DatabaseServiceCore.clearCache('cache_user_profile_$userId');
      await DatabaseServiceCore.clearCache('cache_profile_timestamp_$userId');

      return publicUrl;
    } catch (e) {
      AppConfig.debugPrint('❌ uploadPicture error: $e');
      throw Exception('Failed to upload picture: $e');
    }
  }

  // ==================================================
  // DELETE PICTURE (Gallery, Profile, OR Background)
  // ==================================================

  static Future<void> deletePicture(String pictureUrl) async {
    final userId = AuthService.currentUserId;
    if (userId == null) {
      throw Exception('Please sign in to continue');
    }

    try {
      // Delete file from bucket (Worker determines correct bucket)
      try {
        await DatabaseServiceCore.deleteFileByPublicUrl(pictureUrl);
      } catch (e) {
        AppConfig.debugPrint('⚠️ Failed to delete file from R2: $e');
        // continue anyway
      }

      // Remove from pictures JSON
      final profile = await ProfileService.getCurrentUserProfile();
      final picturesJson = profile?['pictures'];

      if (picturesJson != null && picturesJson.isNotEmpty) {
        List<String> pictures = List<String>.from(jsonDecode(picturesJson));
        pictures.remove(pictureUrl);

        await DatabaseServiceCore.workerQuery(
          action: 'update',
          table: 'user_profiles',
          filters: {'id': userId},
          data: {
            'pictures': jsonEncode(pictures),
            'updated_at': DateTime.now().toIso8601String(),
          },
        );

        await DatabaseServiceCore.clearCache('cache_user_profile_$userId');
        await DatabaseServiceCore.clearCache('cache_profile_timestamp_$userId');
      }
    } catch (e) {
      throw Exception('Failed to delete picture: $e');
    }
  }

  // ==================================================
  // SET A GALLERY PICTURE AS PROFILE PICTURE
  // ==================================================

  static Future<void> setPictureAsProfilePicture(String pictureUrl) async {
    final userId = AuthService.currentUserId;
    if (userId == null) {
      throw Exception('Please sign in to continue');
    }

    try {
      await DatabaseServiceCore.workerQuery(
        action: 'update',
        table: 'user_profiles',
        filters: {'id': userId},
        data: {
          'profile_picture_url': pictureUrl,
          'updated_at': DateTime.now().toIso8601String(),
        },
      );

      await DatabaseServiceCore.clearCache('cache_user_profile_$userId');
      await DatabaseServiceCore.clearCache('cache_profile_timestamp_$userId');
    } catch (e) {
      throw Exception('Failed to update profile picture: $e');
    }
  }

  // ==================================================
  // GETTERS
  // ==================================================

  static Future<List<String>> getUserPictures(String userId) async {
    try {
      final profile = await ProfileService.getUserProfile(userId);
      final jsonText = profile?['pictures'];

      if (jsonText == null || jsonText.isEmpty) return [];
      return List<String>.from(jsonDecode(jsonText));
    } catch (_) {
      return [];
    }
  }

  static Future<List<String>> getCurrentUserPictures() async {
    final userId = AuthService.currentUserId;
    if (userId == null) return [];
    return getUserPictures(userId);
  }
}
