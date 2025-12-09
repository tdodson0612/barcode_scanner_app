// lib/services/picture_service.dart
// IMPROVED: Better error handling and debugging

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
      // Validate file exists
      if (!await imageFile.exists()) {
        throw Exception('Image file not found');
      }

      // Validate size
      final fileSize = await imageFile.length();
      AppConfig.debugPrint('📊 Profile picture file size: ${(fileSize / 1024 / 1024).toStringAsFixed(2)}MB');
      
      if (fileSize > 10 * 1024 * 1024) {
        throw Exception('Image file too large (${(fileSize / 1024 / 1024).toStringAsFixed(1)}MB). Max 10MB.');
      }

      if (fileSize == 0) {
        throw Exception('Image file is empty');
      }

      // Read and encode image
      AppConfig.debugPrint('📖 Reading image file...');
      final bytes = await imageFile.readAsBytes();
      
      if (bytes.isEmpty) {
        throw Exception('Failed to read image data');
      }

      AppConfig.debugPrint('🔄 Encoding to base64...');
      final base64Image = base64Encode(bytes);
      
      if (base64Image.isEmpty) {
        throw Exception('Failed to encode image');
      }

      AppConfig.debugPrint('📤 Uploading profile picture:');
      AppConfig.debugPrint('   Bucket: profile-pictures');
      AppConfig.debugPrint('   Path: $filePath');
      AppConfig.debugPrint('   Size: ${bytes.length} bytes');
      AppConfig.debugPrint('   Base64 length: ${base64Image.length} chars');

      // Upload to R2 via Worker
      final publicUrl = await DatabaseServiceCore.workerStorageUpload(
        bucket: 'profile-pictures',
        path: filePath,
        base64Data: base64Image,
        contentType: 'image/jpeg',
      );

      AppConfig.debugPrint('✅ Profile picture uploaded: $publicUrl');

      // Update database
      AppConfig.debugPrint('💾 Updating database with profile picture URL...');
      await DatabaseServiceCore.workerQuery(
        action: 'update',
        table: 'user_profiles',
        filters: {'id': userId},
        data: {
          'profile_picture': publicUrl,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
      );

      // Clear caches
      await DatabaseServiceCore.clearCache('cache_user_profile_$userId');
      await DatabaseServiceCore.clearCache('cache_profile_timestamp_$userId');
      await DatabaseServiceCore.clearCache('user_profile_$userId');

      AppConfig.debugPrint('✅ Profile picture updated successfully');

      return publicUrl;
    } on FileSystemException catch (e) {
      AppConfig.debugPrint('❌ File system error: $e');
      throw Exception('Cannot access image file: ${e.message}');
    } on FormatException catch (e) {
      AppConfig.debugPrint('❌ Format error: $e');
      throw Exception('Invalid image format: ${e.message}');
    } catch (e) {
      AppConfig.debugPrint('❌ uploadProfilePicture error: $e');
      
      // Provide more helpful error messages
      final errorStr = e.toString().toLowerCase();
      if (errorStr.contains('timeout')) {
        throw Exception('Upload timeout. Please check your connection and try again.');
      } else if (errorStr.contains('network') || errorStr.contains('socket')) {
        throw Exception('Network error. Please check your internet connection.');
      } else if (errorStr.contains('401') || errorStr.contains('authentication')) {
        throw Exception('Session expired. Please sign out and sign back in.');
      } else if (errorStr.contains('413') || errorStr.contains('too large')) {
        throw Exception('Image too large. Please choose a smaller image.');
      }
      
      rethrow;
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
      if (!await imageFile.exists()) {
        throw Exception('Image file not found');
      }

      final fileSize = await imageFile.length();
      AppConfig.debugPrint('📊 Background picture file size: ${(fileSize / 1024 / 1024).toStringAsFixed(2)}MB');
      
      if (fileSize > 10 * 1024 * 1024) {
        throw Exception('Image file too large. Max 10MB.');
      }

      if (fileSize == 0) {
        throw Exception('Image file is empty');
      }

      final bytes = await imageFile.readAsBytes();
      if (bytes.isEmpty) {
        throw Exception('Failed to read image data');
      }

      final base64Image = base64Encode(bytes);
      if (base64Image.isEmpty) {
        throw Exception('Failed to encode image');
      }

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

      await DatabaseServiceCore.clearCache('cache_user_profile_$userId');
      await DatabaseServiceCore.clearCache('cache_profile_timestamp_$userId');
      await DatabaseServiceCore.clearCache('user_profile_$userId');

      AppConfig.debugPrint('✅ Background picture URL saved to database');

      return publicUrl;
    } catch (e) {
      AppConfig.debugPrint('❌ uploadBackgroundPicture error: $e');
      rethrow;
    }
  }

  // ==================================================
  // UPLOAD PICTURE TO PHOTO ALBUM
  // ==================================================
// lib/services/picture_service.dart - FIXED GALLERY UPLOAD

// Replace the uploadPicture method with this:

  static Future<String> uploadPicture(File imageFile) async {
    final userId = AuthService.currentUserId;
    if (userId == null) {
      throw Exception('Please sign in to continue');
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final fileName = 'picture_$timestamp.jpg';
    final filePath = '$userId/$fileName';

    try {
      // Validate file exists
      if (!await imageFile.exists()) {
        throw Exception('Image file not found');
      }

      // Validate size
      final fileSize = await imageFile.length();
      AppConfig.debugPrint('📊 Gallery picture file size: ${(fileSize / 1024 / 1024).toStringAsFixed(2)}MB');
      
      if (fileSize > 10 * 1024 * 1024) {
        throw Exception('Image too large (${(fileSize / 1024 / 1024).toStringAsFixed(1)}MB). Max 10MB.');
      }

      if (fileSize == 0) {
        throw Exception('Image file is empty');
      }

      // Read and encode image
      AppConfig.debugPrint('📖 Reading gallery image file...');
      final bytes = await imageFile.readAsBytes();
      
      if (bytes.isEmpty) {
        throw Exception('Failed to read image data');
      }

      AppConfig.debugPrint('🔄 Encoding gallery image to base64...');
      final base64Image = base64Encode(bytes);
      
      if (base64Image.isEmpty) {
        throw Exception('Failed to encode image');
      }

      AppConfig.debugPrint('📤 Uploading gallery picture to: photo-album/$filePath');

      // Upload to R2 via Worker
      final publicUrl = await DatabaseServiceCore.workerStorageUpload(
        bucket: 'photo-album',
        path: filePath,
        base64Data: base64Image,
        contentType: 'image/jpeg',
      );

      AppConfig.debugPrint('✅ Gallery picture uploaded: $publicUrl');

      // Get existing pictures from database
      AppConfig.debugPrint('📥 Fetching current pictures list...');
      final profile = await ProfileService.getCurrentUserProfile();
      List<String> pictures = [];

      final existing = profile?['pictures'];
      if (existing != null && existing.isNotEmpty) {
        try {
          // Handle both String (JSON) and List formats
          if (existing is String) {
            pictures = List<String>.from(jsonDecode(existing));
          } else if (existing is List) {
            pictures = List<String>.from(existing);
          }
          AppConfig.debugPrint('📦 Found ${pictures.length} existing pictures');
        } catch (e) {
          AppConfig.debugPrint('⚠️ Failed to parse existing pictures: $e');
          pictures = [];
        }
      } else {
        AppConfig.debugPrint('📭 No existing pictures found');
      }

      // Add new picture
      pictures.add(publicUrl);
      AppConfig.debugPrint('💾 Saving ${pictures.length} pictures to database...');

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
      await DatabaseServiceCore.clearCache('user_pictures');

      AppConfig.debugPrint('✅ Gallery picture saved to database (total: ${pictures.length})');

      return publicUrl;
    } on FileSystemException catch (e) {
      AppConfig.debugPrint('❌ File system error: $e');
      throw Exception('Cannot access image file: ${e.message}');
    } on FormatException catch (e) {
      AppConfig.debugPrint('❌ Format error: $e');
      throw Exception('Invalid image format: ${e.message}');
    } catch (e) {
      AppConfig.debugPrint('❌ uploadPicture (gallery) error: $e');
      
      // Provide more helpful error messages
      final errorStr = e.toString().toLowerCase();
      if (errorStr.contains('session expired') || errorStr.contains('authentication')) {
        throw Exception('Your session has expired. Please sign out and sign back in.');
      } else if (errorStr.contains('timeout')) {
        throw Exception('Upload timeout. Please check your connection and try again.');
      } else if (errorStr.contains('network') || errorStr.contains('socket')) {
        throw Exception('Network error. Please check your internet connection.');
      } else if (errorStr.contains('413') || errorStr.contains('too large')) {
        throw Exception('Image too large. Please choose a smaller image.');
      }
      
      rethrow;
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