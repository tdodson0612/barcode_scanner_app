// lib/services/friends_visibility_service.dart
// Handles friend list visibility + fetching a user's friends list

import 'database_service_core.dart';
import 'auth_service.dart';
import 'profile_service.dart';

class FriendsVisibilityService {
  // ==================================================
  // FETCH USER'S FRIEND LIST (public view)
  // ==================================================
  static Future<List<Map<String, dynamic>>> getUserFriends(String userId) async {
    try {
      // Pull all accepted requests (Worker cannot do OR filters directly)
      final response = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'friend_requests',
        columns: ['*'],
        filters: {'status': 'accepted'},
      );

      final friends = <Map<String, dynamic>>[];

      for (var row in response as List) {
        if (row['sender'] == userId || row['receiver'] == userId) {
          final friendId =
              row['sender'] == userId ? row['receiver'] : row['sender'];

          final friendProfile = await DatabaseServiceCore.workerQuery(
            action: 'select',
            table: 'user_profiles',
            columns: [
              'id',
              'email',
              'username',
              'first_name',
              'last_name',
              'avatar_url'
            ],
            filters: {'id': friendId},
            limit: 1,
          );

          if (friendProfile != null && (friendProfile as List).isNotEmpty) {
            friends.add(friendProfile[0]);
          }
        }
      }

      return friends;
    } catch (e) {
      throw Exception('Failed to load user friends: $e');
    }
  }

  // ==================================================
  // GET VISIBILITY SETTING
  // ==================================================
  static Future<bool> getFriendsListVisibility() async {
    if (AuthService.currentUserId == null) {
      throw Exception('Please sign in to continue');
    }

    try {
      final profile = await ProfileService.getUserProfile(
        AuthService.currentUserId!,
      );
      return profile?['friends_list_visible'] ?? true;
    } catch (_) {
      return true; // default to visible
    }
  }

  // ==================================================
  // UPDATE VISIBILITY SETTING
  // ==================================================
  static Future<void> updateFriendsListVisibility(bool isVisible) async {
    if (AuthService.currentUserId == null) {
      throw Exception('Please sign in to continue');
    }

    final userId = AuthService.currentUserId!;

    try {
      await DatabaseServiceCore.workerQuery(
        action: 'update',
        table: 'user_profiles',
        filters: {'id': userId},
        data: {
          'friends_list_visible': isVisible,
          'updated_at': DateTime.now().toIso8601String(),
        },
      );

      await DatabaseServiceCore.clearCache('cache_user_profile_$userId');
      await DatabaseServiceCore.clearCache('cache_profile_timestamp_$userId');
    } catch (e) {
      throw Exception('Failed to update visibility setting: $e');
    }
  }
}
