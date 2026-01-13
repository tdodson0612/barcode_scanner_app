// lib/services/feed_posts_service.dart - WITH VISIBILITY CONTROLS
import 'database_service_core.dart';
import 'auth_service.dart';
import '../config/app_config.dart';

class FeedPostsService {
  /// Create a text post with visibility setting
  static Future<void> createTextPost({
    required String content,
    required String visibility, // 'public' or 'friends'
  }) async {
    try {
      final userId = AuthService.currentUserId;
      final username = await AuthService.fetchCurrentUsername();

      if (userId == null || username == null) {
        throw Exception('User not authenticated');
      }

      if (content.trim().isEmpty) {
        throw Exception('Post content cannot be empty');
      }

      // Insert into feed_posts table with visibility
      await DatabaseServiceCore.workerQuery(
        action: 'insert',
        table: 'feed_posts',
        data: {
          'user_id': userId,
          'username': username,
          'content': content.trim(),
          'post_type': 'text',
          'visibility': visibility, // 'public' or 'friends'
          'created_at': DateTime.now().toIso8601String(),
        },
      );

      AppConfig.debugPrint('✅ Text post created with visibility: $visibility');
    } catch (e) {
      AppConfig.debugPrint('❌ Error creating text post: $e');
      throw Exception('Failed to create post: $e');
    }
  }

  /// Share a recipe to the feed
  static Future<void> shareRecipeToFeed({
    required String recipeName,
    String? description,
    required String ingredients,
    required String directions,
    required String visibility,
  }) async {
    try {
      final userId = AuthService.currentUserId;
      final username = await AuthService.fetchCurrentUsername();

      if (userId == null || username == null) {
        throw Exception('User not authenticated');
      }

      final postContent = _formatRecipeForFeed(
        recipeName: recipeName,
        description: description,
        ingredients: ingredients,
        directions: directions,
      );

      await DatabaseServiceCore.workerQuery(
        action: 'insert',
        table: 'feed_posts',
        data: {
          'user_id': userId,
          'username': username,
          'content': postContent,
          'post_type': 'recipe_share',
          'recipe_name': recipeName,
          'visibility': visibility,
          'created_at': DateTime.now().toIso8601String(),
        },
      );

      AppConfig.debugPrint('✅ Recipe shared to feed: $recipeName');
    } catch (e) {
      AppConfig.debugPrint('❌ Error sharing recipe to feed: $e');
      throw Exception('Failed to share recipe: $e');
    }
  }

  static String _formatRecipeForFeed({
    required String recipeName,
    String? description,
    required String ingredients,
    required String directions,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('🍽️ **$recipeName**');
    buffer.writeln();
    if (description != null && description.trim().isNotEmpty) {
      buffer.writeln(description);
      buffer.writeln();
    }
    buffer.writeln('📋 **Ingredients:**');
    buffer.writeln(ingredients);
    buffer.writeln();
    buffer.writeln('👨‍🍳 **Directions:**');
    buffer.writeln(directions);
    return buffer.toString();
  }

  /// Get feed posts based on current user's friend status
  /// Shows: Public posts + Friends-only posts from friends
  static Future<List<Map<String, dynamic>>> getFeedPosts({
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final userId = AuthService.currentUserId;
      
      if (userId == null) {
        AppConfig.debugPrint('⚠️ User not authenticated, showing only public posts');
        return await _getPublicPostsOnly(limit: limit);
      }

      AppConfig.debugPrint('📱 Loading feed for user: $userId');

      // Get friend IDs
      final friendsResult = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'friends',
        filters: {'status': 'accepted'},
        columns: ['user_id', 'friend_id'],
      );

      final friendIds = <String>{userId}; // Include self
      
      if (friendsResult != null && (friendsResult as List).isNotEmpty) {
        for (final friendship in friendsResult) {
          final user1 = friendship['user_id']?.toString();
          final user2 = friendship['friend_id']?.toString();
          
          if (user1 == userId && user2 != null) {
            friendIds.add(user2);
          } else if (user2 == userId && user1 != null) {
            friendIds.add(user1);
          }
        }
      }

      AppConfig.debugPrint('👥 Friend IDs (including self): ${friendIds.length}');

      // Get all posts
      final postsResult = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'feed_posts',
        orderBy: 'created_at',
        ascending: false,
        limit: 200,
      );

      if (postsResult == null || (postsResult as List).isEmpty) {
        AppConfig.debugPrint('ℹ️ No posts found in database');
        return [];
      }

      final allPosts = List<Map<String, dynamic>>.from(postsResult);
      
      // Filter posts based on visibility rules:
      // 1. All PUBLIC posts (from anyone)
      // 2. FRIENDS-ONLY posts from friends
      final visiblePosts = allPosts.where((post) {
        final visibility = post['visibility']?.toString() ?? 'public';
        final postUserId = post['user_id']?.toString();
        
        // Show all public posts
        if (visibility == 'public') {
          return true;
        }
        
        // Show friends-only posts only from friends
        if (visibility == 'friends' && postUserId != null) {
          return friendIds.contains(postUserId);
        }
        
        return false;
      }).toList();

      final limitedPosts = visiblePosts.take(limit).toList();

      AppConfig.debugPrint('✅ Loaded ${limitedPosts.length} visible posts (${visiblePosts.length} total after filtering)');

      return limitedPosts;
    } catch (e) {
      AppConfig.debugPrint('❌ Error loading feed: $e');
      return [];
    }
  }

  /// Get only public posts (for unauthenticated users)
  static Future<List<Map<String, dynamic>>> _getPublicPostsOnly({
    int limit = 20,
  }) async {
    try {
      final result = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'feed_posts',
        filters: {'visibility': 'public'},
        orderBy: 'created_at',
        ascending: false,
        limit: limit,
      );

      if (result == null || (result as List).isEmpty) {
        return [];
      }

      return List<Map<String, dynamic>>.from(result);
    } catch (e) {
      AppConfig.debugPrint('❌ Error loading public posts: $e');
      return [];
    }
  }

  /// LEGACY: Keep this for compatibility
  static Future<List<Map<String, dynamic>>> getFeedPostsFromFriends({
    int limit = 20,
    int offset = 0,
  }) async {
    return getFeedPosts(limit: limit, offset: offset);
  }

  static Future<void> reportPost({
    required String postId,
    required String reason,
  }) async {
    try {
      final userId = AuthService.currentUserId;
      
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      final existingReport = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'post_reports',
        filters: {
          'post_id': postId,
          'reporter_user_id': userId,
        },
        limit: 1,
      );

      if (existingReport != null && (existingReport as List).isNotEmpty) {
        throw Exception('You have already reported this post');
      }

      await DatabaseServiceCore.workerQuery(
        action: 'insert',
        table: 'post_reports',
        data: {
          'post_id': postId,
          'reporter_user_id': userId,
          'reason': reason,
          'status': 'pending',
          'created_at': DateTime.now().toIso8601String(),
        },
      );

      AppConfig.debugPrint('✅ Post reported: $postId, Reason: $reason');
    } catch (e) {
      AppConfig.debugPrint('❌ Error reporting post: $e');
      throw Exception('Failed to report post: $e');
    }
  }

  static Future<void> deletePost(String postId) async {
    try {
      final userId = AuthService.currentUserId;
      
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      await DatabaseServiceCore.workerQuery(
        action: 'delete',
        table: 'feed_posts',
        filters: {
          'id': postId,
          'user_id': userId,
        },
      );

      AppConfig.debugPrint('✅ Post deleted: $postId');
    } catch (e) {
      AppConfig.debugPrint('❌ Error deleting post: $e');
      throw Exception('Failed to delete post: $e');
    }
  }

  static Future<void> likePost(String postId) async {
    try {
      final userId = AuthService.currentUserId;
      
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      await DatabaseServiceCore.workerQuery(
        action: 'insert',
        table: 'feed_post_likes',
        data: {
          'post_id': postId,
          'user_id': userId,
          'created_at': DateTime.now().toIso8601String(),
        },
      );

      AppConfig.debugPrint('✅ Post liked: $postId');
    } catch (e) {
      AppConfig.debugPrint('❌ Error liking post: $e');
      throw Exception('Failed to like post: $e');
    }
  }

  static Future<void> unlikePost(String postId) async {
    try {
      final userId = AuthService.currentUserId;
      
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      await DatabaseServiceCore.workerQuery(
        action: 'delete',
        table: 'feed_post_likes',
        filters: {
          'post_id': postId,
          'user_id': userId,
        },
      );

      AppConfig.debugPrint('✅ Post unliked: $postId');
    } catch (e) {
      AppConfig.debugPrint('❌ Error unliking post: $e');
      throw Exception('Failed to unlike post: $e');
    }
  }

  static Future<bool> hasUserLikedPost(String postId) async {
    try {
      final userId = AuthService.currentUserId;
      
      if (userId == null) {
        return false;
      }

      final result = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'feed_post_likes',
        filters: {
          'post_id': postId,
          'user_id': userId,
        },
        limit: 1,
      );

      return result != null && (result as List).isNotEmpty;
    } catch (e) {
      AppConfig.debugPrint('❌ Error checking like status: $e');
      return false;
    }
  }

  static Future<int> getPostLikeCount(String postId) async {
    try {
      final result = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'feed_post_likes',
        filters: {'post_id': postId},
        columns: ['COUNT(*) as count'],
      );

      if (result == null || (result as List).isEmpty) {
        return 0;
      }

      return result[0]['count'] as int? ?? 0;
    } catch (e) {
      AppConfig.debugPrint('❌ Error getting like count: $e');
      return 0;
    }
  }
}