// lib/services/profile_service.dart
// Handles user profile creation, updates, premium status, and picture getters

import 'dart:convert';
import '../config/app_config.dart';

import 'database_service_core.dart';
import 'achievements_service.dart'; // awardBadge
import 'profile_data_access.dart'; // NEW: replaces all AuthService/profile DB loops


class ProfileService {

  
  // ==================================================
  // FETCH PROFILE
  // ==================================================

  static Future<Map<String, dynamic>?> getUserProfile(String userId) async {
    try {
      final result = await ProfileDataAccess.getUserProfile(userId);
      return result;
    } catch (e) {
      throw Exception('Failed to get user profile: $e');
    }
  }

  static Future<Map<String, dynamic>?> getCurrentUserProfile() async {
    final userId = DatabaseServiceCore.currentUserId; // FIX: removed AuthService
    if (userId == null) return null;
    return getUserProfile(userId);
  }

  // ==================================================
  // UPDATE PROFILE
  // ==================================================

  static Future<void> updateProfile({
    String? username,
    String? email,
    String? firstName,
    String? lastName,
    String? avatarUrl,
    String? profilePicture,
  }) async {
    final userId = DatabaseServiceCore.currentUserId; // FIX
    if (userId == null) throw Exception('Please sign in');

    try {
      final updates = <String, dynamic>{
        'updated_at': DateTime.now().toIso8601String(),
      };

      if (username != null) updates['username'] = username;
      if (email != null) updates['email'] = email;
      if (firstName != null) updates['first_name'] = firstName;
      if (lastName != null) updates['last_name'] = lastName;
      if (avatarUrl != null) updates['avatar_url'] = avatarUrl;
      if (profilePicture != null) updates['profile_picture'] = profilePicture;

      await DatabaseServiceCore.workerQuery(
        action: 'update',
        table: 'user_profiles',
        filters: {'id': userId},
        data: updates,
      );

      await DatabaseServiceCore.clearCache('cache_user_profile_$userId');
      await DatabaseServiceCore.clearCache('cache_profile_timestamp_$userId');
    } catch (e) {
      if (e.toString().contains('duplicate') ||
          e.toString().contains('unique constraint')) {
        throw Exception('Username is already taken. Please choose another.');
      }
      throw Exception('Failed to update profile: $e');
    }
  }

  // ==================================================
  // PREMIUM STATUS
  // ==================================================

  static Future<bool> isPremiumUser() async {
    final userId = DatabaseServiceCore.currentUserId; // FIX
    if (userId == null) return false;

    try {
      final profile = await getUserProfile(userId);
      return profile?['is_premium'] ?? false;
    } catch (_) {
      return false;
    }
  }

  // ==================================================
  // PICTURE GETTERS
  // ==================================================

  static Future<String?> getProfilePicture(String userId) async {
    try {
      final profile = await getUserProfile(userId);
      return profile?['profile_picture'] as String?;
    } catch (e) {
      AppConfig.debugPrint('Error getting profile picture: $e');
      return null;
    }
  }

  static Future<String?> getCurrentProfilePicture() async {
    final userId = DatabaseServiceCore.currentUserId; // FIX
    if (userId == null) return null;
    return getProfilePicture(userId);
  }

  static Future<String?> getBackgroundPicture(String userId) async {
    try {
      final profile = await getUserProfile(userId);
      return profile?['profile_background'] as String?;
    } catch (e) {
      AppConfig.debugPrint('Error getting background picture: $e');
      return null;
    }
  }

  static Future<String?> getCurrentBackgroundPicture() async {
    final userId = DatabaseServiceCore.currentUserId; // FIX
    if (userId == null) return null;
    return getBackgroundPicture(userId);
  }

  // ==================================================
  // 🆕 DISEASE TYPE MANAGEMENT
  // ==================================================

  /// Get user's liver disease type
  static Future<String?> getDiseaseType(String userId) async {
    try {
      final profile = await getUserProfile(userId);
      return profile?['liver_disease_type'] as String?;
    } catch (e) {
      AppConfig.debugPrint('Error getting disease type: $e');
      return null;
    }
  }

  /// Update user's liver disease type
  static Future<void> updateDiseaseType(String userId, String diseaseType) async {
    try {
      await DatabaseServiceCore.workerQuery(
        action: 'update',
        table: 'user_profiles',
        filters: {'id': userId},
        data: {
          'liver_disease_type': diseaseType,
          'updated_at': DateTime.now().toIso8601String(),
        },
      );

      // Clear cache to force fresh data
      await DatabaseServiceCore.clearCache('cache_user_profile_$userId');
      await DatabaseServiceCore.clearCache('cache_profile_timestamp_$userId');
      
      AppConfig.debugPrint('✅ Disease type updated to: $diseaseType');
    } catch (e) {
      AppConfig.debugPrint('❌ Error updating disease type: $e');
      throw Exception('Failed to update disease type: $e');
    }
  }

  /// Get current user's disease type
  static Future<String?> getCurrentDiseaseType() async {
    final userId = DatabaseServiceCore.currentUserId;
    if (userId == null) return null;
    return getDiseaseType(userId);
  }
}