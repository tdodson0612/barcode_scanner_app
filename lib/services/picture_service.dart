// lib/services/picture_service.dart
// Handles all picture uploads, deletes, and getters (profile, background, gallery)

import 'dart:convert';
import 'dart:io';

import '../config/app_config.dart';
import 'auth_service.dart';
import 'profile_service.dart';
import 'database_service_core.dart';

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

      AppConfig.debugPrint('📤 Uploading profile picture to: profile-pictures/$filePath');

      // Upload to R2
      final publicUrl = await DatabaseServiceCore.workerStorageUpload(
        bucket: 'profile-pictures',
        path: filePath,
        base64Data: base64Image,
        contentType: 'image/jpeg',
      );

      AppConfig.debugPrint('✅ Profile picture uploaded: $publicUrl');

      // Update profile with correct field name
      await DatabaseServiceCore.workerQuery(
        action: 'update',
        table: 'user_profiles',
        filters: {'id': userId},
        data: {
          'profile_picture': publicUrl,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
      );

      // Clear all profile-related caches
      await DatabaseServiceCore.clearCache('cache_user_profile_$userId');
      await DatabaseServiceCore.clearCache('cache_profile_timestamp_$userId');
      await DatabaseServiceCore.clearCache('user_profile_$userId');

      AppConfig.debugPrint('✅ Profile picture URL saved to database');

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

      // 🔥 DEBUG CODE - Background Picture
      print('🔍 DEBUG uploadBackgroundPicture:');
      print('   userId: $userId');
      print('   fileName: $fileName');
      print('   filePath: $filePath');
      print('   bucket: background-pictures');
      print('   fileSize: $fileSize bytes');
      print('   base64 length: ${base64Image.length} chars');

      AppConfig.debugPrint('📤 Uploading background picture to: background-pictures/$filePath');

      final publicUrl = await DatabaseServiceCore.workerStorageUpload(
        bucket: 'background-pictures',
        path: filePath,
        base64Data: base64Image,
        contentType: 'image/jpeg',
      );

      AppConfig.debugPrint('✅ Background picture uploaded: $publicUrl');

      await DatabaseServiceCore.workerQuery(
        action: 'update',
        table: 'user_profiles',
        filters: {'id': userId},
        data: {
          'profile_background': publicUrl,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
      );

      // Clear all profile-related caches
      await DatabaseServiceCore.clearCache('cache_user_profile_$userId');
      await DatabaseServiceCore.clearCache('cache_profile_timestamp_$userId');
      await DatabaseServiceCore.clearCache('user_profile_$userId');

      AppConfig.debugPrint('✅ Background picture URL saved to database');

      return publicUrl;
    } catch (e) {
      AppConfig.debugPrint('❌ uploadBackgroundPicture error: $e');
      print('❌ FULL ERROR: $e'); // 🔥 Extra debug
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

      // 🔥 DEBUG CODE - Gallery Picture
      print('🔍 DEBUG uploadPicture (gallery):');
      print('   userId: $userId');
      print('   fileName: $fileName');
      print('   filePath: $filePath');
      print('   bucket: photo-album');
      print('   fileSize: $fileSize bytes');
      print('   base64 length: ${base64Image.length} chars');

      AppConfig.debugPrint('📤 Uploading gallery picture to: photo-album/$filePath');

      final publicUrl = await DatabaseServiceCore.workerStorageUpload(
        bucket: 'photo-album',
        path: filePath,
        base64Data: base64Image,
        contentType: 'image/jpeg',
      );

      AppConfig.debugPrint('✅ Gallery picture uploaded: $publicUrl');

      // Get existing pictures from database
      final profile = await ProfileService.getCurrentUserProfile();
      List<String> pictures = [];

      final existing = profile?['pictures'];
      if (existing != null && existing.isNotEmpty) {
        try {
          pictures = List<String>.from(jsonDecode(existing));
        } catch (e) {
          AppConfig.debugPrint('⚠️ Failed to parse existing pictures: $e');
          pictures = [];
        }
      }

      pictures.add(publicUrl);

      AppConfig.debugPrint('💾 Saving ${pictures.length} pictures to database');

      // Save updated picture list to database
      await DatabaseServiceCore.workerQuery(
        action: 'update',
        table: 'user_profiles',
        filters: {'id': userId},
        data: {
          'pictures': jsonEncode(pictures),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
      );

      // Clear all profile-related caches
      await DatabaseServiceCore.clearCache('cache_user_profile_$userId');
      await DatabaseServiceCore.clearCache('cache_profile_timestamp_$userId');
      await DatabaseServiceCore.clearCache('user_profile_$userId');
      await DatabaseServiceCore.clearCache('user_pictures'); // Also clear pictures cache

      AppConfig.debugPrint('✅ Gallery picture saved to database');

      return publicUrl;
    } catch (e) {
      AppConfig.debugPrint('❌ uploadPicture error: $e');
      print('❌ FULL ERROR: $e'); // 🔥 Extra debug
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
      AppConfig.debugPrint('🗑️ Deleting picture: $pictureUrl');

      // Delete file from R2 storage (Worker determines correct bucket)
      try {
        await DatabaseServiceCore.deleteFileByPublicUrl(pictureUrl);
        AppConfig.debugPrint('✅ Picture deleted from R2 storage');
      } catch (e) {
        AppConfig.debugPrint('⚠️ Failed to delete file from R2: $e');
        // Continue anyway to remove from database
      }

      // Remove from pictures JSON array in database
      final profile = await ProfileService.getCurrentUserProfile();
      final picturesJson = profile?['pictures'];

      if (picturesJson != null && picturesJson.isNotEmpty) {
        List<String> pictures = [];
        try {
          pictures = List<String>.from(jsonDecode(picturesJson));
        } catch (e) {
          AppConfig.debugPrint('⚠️ Failed to parse pictures JSON: $e');
          pictures = [];
        }

        final originalLength = pictures.length;
        pictures.remove(pictureUrl);

        if (pictures.length < originalLength) {
          AppConfig.debugPrint('💾 Updating pictures list: ${pictures.length} remaining');

          await DatabaseServiceCore.workerQuery(
            action: 'update',
            table: 'user_profiles',
            filters: {'id': userId},
            data: {
              'pictures': jsonEncode(pictures),
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            },
          );

          // Clear all profile-related caches
          await DatabaseServiceCore.clearCache('cache_user_profile_$userId');
          await DatabaseServiceCore.clearCache('cache_profile_timestamp_$userId');
          await DatabaseServiceCore.clearCache('user_profile_$userId');
          await DatabaseServiceCore.clearCache('user_pictures');

          AppConfig.debugPrint('✅ Picture removed from database');
        } else {
          AppConfig.debugPrint('⚠️ Picture URL not found in database');
        }
      }
    } catch (e) {
      AppConfig.debugPrint('❌ deletePicture error: $e');
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
      AppConfig.debugPrint('🖼️ Setting profile picture: $pictureUrl');

      await DatabaseServiceCore.workerQuery(
        action: 'update',
        table: 'user_profiles',
        filters: {'id': userId},
        data: {
          'profile_picture': pictureUrl,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
      );

      // Clear all profile-related caches
      await DatabaseServiceCore.clearCache('cache_user_profile_$userId');
      await DatabaseServiceCore.clearCache('cache_profile_timestamp_$userId');
      await DatabaseServiceCore.clearCache('user_profile_$userId');

      AppConfig.debugPrint('✅ Profile picture updated successfully');
    } catch (e) {
      AppConfig.debugPrint('❌ setPictureAsProfilePicture error: $e');
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

      if (jsonText == null || jsonText.isEmpty) {
        AppConfig.debugPrint('📭 No pictures found for user: $userId');
        return [];
      }

      final pictures = List<String>.from(jsonDecode(jsonText));
      AppConfig.debugPrint('📦 Loaded ${pictures.length} pictures for user: $userId');
      return pictures;
    } catch (e) {
      AppConfig.debugPrint('❌ getUserPictures error: $e');
      return [];
    }
  }

  static Future<List<String>> getCurrentUserPictures() async {
    final userId = AuthService.currentUserId;
    if (userId == null) return [];
    return getUserPictures(userId);
  }
}