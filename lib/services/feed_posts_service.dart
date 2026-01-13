// lib/services/feed_posts_service.dart - FIXED VERSION
import 'database_service_core.dart';
import 'auth_service.dart';
import '../config/app_config.dart';

class FeedPostsService {
  /// Create a text post
  static Future<void> createTextPost({
    required String content,
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

      // Insert into feed_posts table
      await DatabaseServiceCore.workerQuery(
        action: 'insert',
        table: 'feed_posts',
        data: {
          'user_id': userId,
          'username': username,
          'content': content.trim(),
          'post_type': 'text',
          'created_at': DateTime.now().toIso8601String(),
        },
      );

      AppConfig.debugPrint('✅ Text post created');
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
  }) async {
    try {
      final userId = AuthService.currentUserId;
      final username = await AuthService.fetchCurrentUsername();

      if (userId == null || username == null) {
        throw Exception('User not authenticated');
      }

      // Create post content
      final postContent = _formatRecipeForFeed(
        recipeName: recipeName,
        description: description,
        ingredients: ingredients,
        directions: directions,
      );

      // Insert into feed_posts table
      await DatabaseServiceCore.workerQuery(
        action: 'insert',
        table: 'feed_posts',
        data: {
          'user_id': userId,
          'username': username,
          'content': postContent,
          'post_type': 'recipe_share',
          'recipe_name': recipeName,
          'created_at': DateTime.now().toIso8601String(),
        },
      );

      AppConfig.debugPrint('✅ Recipe shared to feed: $recipeName');
    } catch (e) {
      AppConfig.debugPrint('❌ Error sharing recipe to feed: $e');
      throw Exception('Failed to share recipe: $e');
    }
  }

  /// Format recipe content for feed display
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

  /// Get all feed posts (for home page)
  static Future<List<Map<String, dynamic>>> getFeedPosts({
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final result = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'feed_posts',
        orderBy: 'created_at',
        ascending: false,
        limit: limit,
      );

      if (result == null || (result as List).isEmpty) {
        return [];
      }

      return List<Map<String, dynamic>>.from(result);
    } catch (e) {
      AppConfig.debugPrint('❌ Error loading feed posts: $e');
      return [];
    }
  }

  /// 🔥 DEBUG: Get ALL posts (no filtering) - for testing
  static Future<List<Map<String, dynamic>>> getAllPostsDebug({
    int limit = 20,
  }) async {
    try {
      AppConfig.debugPrint('🔍 DEBUG: Fetching ALL posts...');
      
      final result = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'feed_posts',
        orderBy: 'created_at',
        ascending: false,
        limit: limit,
      );

      if (result == null || (result as List).isEmpty) {
        AppConfig.debugPrint('❌ No posts found in database at all');
        return [];
      }

      final posts = List<Map<String, dynamic>>.from(result);
      AppConfig.debugPrint('✅ Found ${posts.length} total posts in database');
      
      for (final post in posts) {
        AppConfig.debugPrint('   - Post: ${post['id']} by user ${post['user_id']} (${post['username']})');
      }

      return posts;
    } catch (e) {
      AppConfig.debugPrint('❌ Error in getAllPostsDebug: $e');
      return [];
    }
  }

  /// 🔥 FIXED: Get feed posts only from friends (Facebook-style)
  static Future<List<Map<String, dynamic>>> getFeedPostsFromFriends({
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final userId = AuthService.currentUserId;
      
      if (userId == null) {
        AppConfig.debugPrint('⚠️ User not authenticated, returning empty feed');
        return [];
      }

      AppConfig.debugPrint('📱 Loading feed for user: $userId');

      // 🔥 FIX: Get list of friend IDs first
      final friendsResult = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'friends',
        filters: {
          'status': 'accepted',
        },
        columns: ['user_id', 'friend_id'],
      );

      // Build friend ID set (including self)
      final friendIds = <String>{userId}; // Always include own posts
      
      if (friendsResult != null && (friendsResult as List).isNotEmpty) {
        for (final friendship in friendsResult) {
          final user1 = friendship['user_id']?.toString();
          final user2 = friendship['friend_id']?.toString();
          
          // Add friend IDs based on who the current user is in the relationship
          if (user1 == userId && user2 != null) {
            friendIds.add(user2);
          } else if (user2 == userId && user1 != null) {
            friendIds.add(user1);
          }
        }
      }

      AppConfig.debugPrint('👥 Friend IDs (including self): ${friendIds.length} - ${friendIds.toList()}');

      // 🔥 FIX: Get ALL posts (we'll filter in memory if needed)
      final postsResult = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'feed_posts',
        orderBy: 'created_at',
        ascending: false,
        limit: 200, // Get more posts to ensure we have enough after filtering
      );

      if (postsResult == null || (postsResult as List).isEmpty) {
        AppConfig.debugPrint('ℹ️ No posts found in database');
        return [];
      }

      AppConfig.debugPrint('📊 Total posts in database: ${(postsResult as List).length}');

      // 🔥 FIX: Filter posts to only include friends
      final allPosts = List<Map<String, dynamic>>.from(postsResult);
      
      // Log all post user_ids for debugging
      final postUserIds = allPosts.map((p) => p['user_id']?.toString() ?? 'null').toSet();
      AppConfig.debugPrint('📝 Unique post user_ids: ${postUserIds.toList()}');
      
      final friendPosts = allPosts.where((post) {
        final postUserId = post['user_id']?.toString();
        final isIncluded = postUserId != null && friendIds.contains(postUserId);
        
        if (!isIncluded && postUserId != null) {
          AppConfig.debugPrint('🚫 Filtering out post from: $postUserId (not in friend list)');
        }
        
        return isIncluded;
      }).toList();

      // Apply limit
      final limitedPosts = friendPosts.take(limit).toList();

      AppConfig.debugPrint('✅ Loaded ${limitedPosts.length} posts from friends (filtered from ${allPosts.length} total)');

      if (limitedPosts.isEmpty) {
        AppConfig.debugPrint('⚠️ No posts from friends found. Debug info:');
        AppConfig.debugPrint('   - Friend IDs: $friendIds');
        AppConfig.debugPrint('   - Post user IDs: $postUserIds');
        AppConfig.debugPrint('   - Intersection: ${friendIds.intersection(postUserIds)}');
      }

      return limitedPosts;
    } catch (e) {
      AppConfig.debugPrint('❌ Error loading friends feed: $e');
      AppConfig.debugPrint('Stack trace: ${StackTrace.current}');
      return [];
    }
  }

  /// 🔥 Report a post for harassment/inappropriate content
  static Future<void> reportPost({
    required String postId,
    required String reason,
  }) async {
    try {
      final userId = AuthService.currentUserId;
      
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      // Check if user has already reported this post
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

      // Insert report
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

  /// Delete a post (user can delete their own posts)
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

  /// Like a post
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

  /// Unlike a post
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

  /// Check if user has liked a post
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

  /// Get like count for a post
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