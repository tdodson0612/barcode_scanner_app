// lib/services/database_service.dart - COMPLETE WITH ALL FEATURES
import 'dart:convert';
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/favorite_recipe.dart';
import '../models/grocery_item.dart';
import '../models/submitted_recipe.dart';
import 'auth_service.dart';

class DatabaseService {
  static final SupabaseClient _supabase = Supabase.instance.client;

  // ==================================================
  // CURRENT USER ID & AUTH CHECK
  // ==================================================
  static String? get currentUserId => _supabase.auth.currentUser?.id;

  static void ensureUserAuthenticated() {
    if (currentUserId == null) {
      throw Exception('Please sign in to continue');
    }
  }

  static bool get isUserLoggedIn => currentUserId != null;

  // ==================================================
  // XP & LEVEL SYSTEM
  // ==================================================

  static Future<Map<String, dynamic>> addXP(int xpAmount, {String? reason}) async {
    ensureUserAuthenticated();
    
    try {
      final profile = await getCurrentUserProfile();
      final currentXP = profile?['xp'] ?? 0;
      final currentLevel = profile?['level'] ?? 1;
      final newXP = currentXP + xpAmount;
      
      int newLevel = _calculateLevel(newXP);
      bool leveledUp = newLevel > currentLevel;
      
      await _supabase
          .from('user_profiles')
          .update({
            'xp': newXP,
            'level': newLevel,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', currentUserId!);
      
      return {
        'xp_gained': xpAmount,
        'total_xp': newXP,
        'new_level': newLevel,
        'leveled_up': leveledUp,
        'reason': reason,
      };
    } catch (e) {
      throw Exception('Failed to add XP: $e');
    }
  }

  static int _calculateLevel(int xp) {
    int level = 1;
    int xpNeeded = 100;
    
    while (xp >= xpNeeded) {
      level++;
      xpNeeded += (level * 50);
    }
    
    return level;
  }

  static int getXPForNextLevel(int currentLevel) {
    int xpNeeded = 100;
    for (int i = 2; i <= currentLevel + 1; i++) {
      xpNeeded += (i * 50);
    }
    return xpNeeded;
  }

  static double getLevelProgress(int currentXP, int currentLevel) {
    int xpForCurrentLevel = getXPForNextLevel(currentLevel - 1);
    int xpForNextLevel = getXPForNextLevel(currentLevel);
    int xpIntoLevel = currentXP - xpForCurrentLevel;
    int xpNeededForLevel = xpForNextLevel - xpForCurrentLevel;
    
    return xpIntoLevel / xpNeededForLevel;
  }

  // ==================================================
  // ACHIEVEMENTS & BADGES
  // ==================================================

  static Future<List<Map<String, dynamic>>> getAllBadges() async {
    try {
      final response = await _supabase
          .from('badges')
          .select()
          .order('xp_reward');
      
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      throw Exception('Failed to get badges: $e');
    }
  }

  static Future<List<Map<String, dynamic>>> getUserBadges(String userId) async {
    try {
      final response = await _supabase
          .from('user_achievements')
          .select('*, badge:badges(*)')
          .eq('user_id', userId)
          .order('earned_at', ascending: false);
      
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      throw Exception('Failed to get user badges: $e');
    }
  }

  static Future<bool> awardBadge(String badgeId) async {
    ensureUserAuthenticated();
    
    try {
      final existing = await _supabase
          .from('user_achievements')
          .select()
          .eq('user_id', currentUserId!)
          .eq('badge_id', badgeId)
          .maybeSingle();
      
      if (existing != null) {
        return false;
      }
      
      await _supabase.from('user_achievements').insert({
        'user_id': currentUserId!,
        'badge_id': badgeId,
        'earned_at': DateTime.now().toIso8601String(),
      });
      
      final badge = await _supabase
          .from('badges')
          .select('xp_reward')
          .eq('id', badgeId)
          .single();
      
      if (badge['xp_reward'] != null && badge['xp_reward'] > 0) {
        await addXP(badge['xp_reward'], reason: 'Badge: $badgeId');
      }
      
      return true;
    } catch (e) {
      print('Failed to award badge: $e');
      return false;
    }
  }

  static Future<void> checkAchievements() async {
    ensureUserAuthenticated();
    
    try {
      final recipeCount = (await getSubmittedRecipes()).length;
      
      if (recipeCount >= 1) await awardBadge('first_recipe');
      if (recipeCount >= 5) await awardBadge('recipe_5');
      if (recipeCount >= 25) await awardBadge('recipe_25');
      if (recipeCount >= 50) await awardBadge('recipe_50');
      if (recipeCount >= 100) await awardBadge('recipe_100');
    } catch (e) {
      print('Error checking achievements: $e');
    }
  }

  // ==================================================
  // DISCOVERY FEED - POSTS (WITH VIDEO SUPPORT)
  // ==================================================

  static Future<String> createPost({
    required int recipeId,
    File? imageFile,
    File? videoFile,
    File? thumbnailFile,
    String? caption,
    bool isDraftRetry = false,
  }) async {
    ensureUserAuthenticated();
    
    if (imageFile == null && videoFile == null) {
      throw Exception('Must provide either an image or video');
    }
    
    try {
      final userId = currentUserId!;
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      
      String? imageUrl;
      String? videoUrl;
      
      // Handle video upload
      if (videoFile != null) {
        // Upload video
        final videoExt = videoFile.path.split('.').last;
        final videoFileName = 'video_${timestamp}.$videoExt';
        final videoPath = '$userId/posts/$videoFileName';
        
        await _supabase.storage
            .from('profile-pictures')
            .upload(videoPath, videoFile);
        
        videoUrl = _supabase.storage
            .from('profile-pictures')
            .getPublicUrl(videoPath);
        
        // Upload thumbnail (use video file as fallback if no custom thumbnail)
        final thumbFile = thumbnailFile ?? videoFile;
        final thumbExt = thumbFile.path.split('.').last;
        final thumbFileName = 'thumb_${timestamp}.$thumbExt';
        final thumbPath = '$userId/posts/$thumbFileName';
        
        await _supabase.storage
            .from('profile-pictures')
            .upload(thumbPath, thumbFile);
        
        imageUrl = _supabase.storage
            .from('profile-pictures')
            .getPublicUrl(thumbPath);
      } 
      // Handle image upload
      else if (imageFile != null) {
        final fileName = 'post_$timestamp.jpg';
        final filePath = '$userId/posts/$fileName';
        
        await _supabase.storage
            .from('profile-pictures')
            .upload(filePath, imageFile);
        
        imageUrl = _supabase.storage
            .from('profile-pictures')
            .getPublicUrl(filePath);
      }
      
      // Create post
      final response = await _supabase
          .from('posts')
          .insert({
            'user_id': userId,
            'recipe_id': recipeId,
            'image_url': imageUrl,
            'video_url': videoUrl,
            'caption': caption,
            'created_at': DateTime.now().toIso8601String(),
          })
          .select()
          .single();
      
      // Award first post badge
      await awardBadge('first_post');
      
      // Add XP (more for videos)
      await addXP(videoFile != null ? 50 : 25, 
          reason: videoFile != null ? 'Posted video' : 'Posted photo');
      
      return response['id'];
    } catch (e) {
      // Auto-save as draft on error (only if not already a retry from draft)
      if (!isDraftRetry) {
        try {
          final draftId = await saveDraftPost(
            recipeId: recipeId,
            imageFile: imageFile,
            videoFile: videoFile,
            thumbnailFile: thumbnailFile,
            caption: caption,
          );
          
          // Throw custom error with draft ID
          throw Exception('DRAFT_SAVED:$draftId:${e.toString()}');
        } catch (draftError) {
          // If draft save also fails, throw original error
          throw Exception('Failed to create post: $e');
        }
      }
      
      throw Exception('Failed to create post: $e');
    }
  }

  // ==================================================
  // DRAFT POSTS - AUTO-SAVE ON ERROR
  // ==================================================

  /// Save post as draft (auto-saves on upload error)
  static Future<String> saveDraftPost({
    required int recipeId,
    File? imageFile,
    File? videoFile,
    File? thumbnailFile,
    String? caption,
  }) async {
    ensureUserAuthenticated();
    
    try {
      final userId = currentUserId!;
      
      // Store file paths locally (don't upload yet)
      final draftData = {
        'user_id': userId,
        'recipe_id': recipeId,
        'image_path': imageFile?.path,
        'video_path': videoFile?.path,
        'thumbnail_path': thumbnailFile?.path,
        'caption': caption,
        'created_at': DateTime.now().toIso8601String(),
        'is_video': videoFile != null,
      };
      
      // Save draft to database
      final response = await _supabase
          .from('draft_posts')
          .insert(draftData)
          .select()
          .single();
      
      return response['id'];
    } catch (e) {
      throw Exception('Failed to save draft: $e');
    }
  }

  /// Get all draft posts for current user
  static Future<List<Map<String, dynamic>>> getDraftPosts() async {
    ensureUserAuthenticated();
    
    try {
      final response = await _supabase
          .from('draft_posts')
          .select('''
            *,
            recipe:submitted_recipes!draft_posts_recipe_id_fkey(id, recipe_name)
          ''')
          .eq('user_id', currentUserId!)
          .order('created_at', ascending: false);
      
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      throw Exception('Failed to get drafts: $e');
    }
  }

  /// Delete a draft post
  static Future<void> deleteDraftPost(String draftId) async {
    ensureUserAuthenticated();
    
    try {
      await _supabase
          .from('draft_posts')
          .delete()
          .eq('id', draftId)
          .eq('user_id', currentUserId!);
    } catch (e) {
      throw Exception('Failed to delete draft: $e');
    }
  }

  /// Resume uploading from draft (with automatic draft deletion on success)
  static Future<String> uploadFromDraft(String draftId) async {
    ensureUserAuthenticated();
    
    try {
      // Get draft data
      final draft = await _supabase
          .from('draft_posts')
          .select()
          .eq('id', draftId)
          .single();
      
      // Recreate file objects from paths
      final imageFile = draft['image_path'] != null ? File(draft['image_path']) : null;
      final videoFile = draft['video_path'] != null ? File(draft['video_path']) : null;
      final thumbnailFile = draft['thumbnail_path'] != null ? File(draft['thumbnail_path']) : null;
      
      // Verify files still exist
      if (videoFile != null && !await videoFile.exists()) {
        throw Exception('Video file no longer exists on device');
      }
      if (imageFile != null && !await imageFile.exists()) {
        throw Exception('Image file no longer exists on device');
      }
      if (thumbnailFile != null && !await thumbnailFile.exists()) {
        throw Exception('Thumbnail file no longer exists on device');
      }
      
      // Upload the post (with isDraftRetry = true to prevent recursive draft saving)
      final postId = await createPost(
        recipeId: draft['recipe_id'],
        imageFile: imageFile,
        videoFile: videoFile,
        thumbnailFile: thumbnailFile,
        caption: draft['caption'],
        isDraftRetry: true,
      );
      
      // Delete draft on successful upload
      await deleteDraftPost(draftId);
      
      return postId;
    } catch (e) {
      throw Exception('Failed to upload from draft: $e');
    }
  }

  static Future<List<Map<String, dynamic>>> getFeedPosts({
    int limit = 20,
    int offset = 0,
    String sortBy = 'recent',
  }) async {
    try {
      final response = await _supabase
          .from('posts')
          .select('''
            *,
            user:user_profiles!posts_user_id_fkey(id, username, first_name, last_name, avatar_url, level, xp),
            recipe:submitted_recipes!posts_recipe_id_fkey(id, recipe_name, ingredients, directions)
          ''')
          .order('created_at', ascending: sortBy != 'recent')
          .range(offset, offset + limit - 1);
      
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      throw Exception('Failed to get feed posts: $e');
    }
  }

  static Future<List<Map<String, dynamic>>> getUserPosts(String userId) async {
    try {
      final response = await _supabase
          .from('posts')
          .select('''
            *,
            user:user_profiles!posts_user_id_fkey(id, username, first_name, last_name, avatar_url),
            recipe:submitted_recipes!posts_recipe_id_fkey(id, recipe_name, ingredients, directions)
          ''')
          .eq('user_id', userId)
          .order('created_at', ascending: false);
      
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      throw Exception('Failed to get user posts: $e');
    }
  }

  static Future<void> deletePost(String postId) async {
    ensureUserAuthenticated();
    
    try {
      final post = await _supabase
          .from('posts')
          .select('image_url, video_url')
          .eq('id', postId)
          .single();
      
      // Delete image/thumbnail
      if (post['image_url'] != null) {
        final uri = Uri.parse(post['image_url']);
        final pathSegments = uri.pathSegments;
        final bucketIndex = pathSegments.indexOf('profile-pictures');
        if (bucketIndex != -1 && bucketIndex < pathSegments.length - 1) {
          final filePath = pathSegments.sublist(bucketIndex + 1).join('/');
          await _supabase.storage.from('profile-pictures').remove([filePath]);
        }
      }
      
      // Delete video if exists
      if (post['video_url'] != null) {
        final uri = Uri.parse(post['video_url']);
        final pathSegments = uri.pathSegments;
        final bucketIndex = pathSegments.indexOf('profile-pictures');
        if (bucketIndex != -1 && bucketIndex < pathSegments.length - 1) {
          final filePath = pathSegments.sublist(bucketIndex + 1).join('/');
          await _supabase.storage.from('profile-pictures').remove([filePath]);
        }
      }
      
      await _supabase
          .from('posts')
          .delete()
          .eq('id', postId);
    } catch (e) {
      throw Exception('Failed to delete post: $e');
    }
  }

  static Future<void> likePost(String postId) async {
    ensureUserAuthenticated();
    
    try {
      await _supabase.from('post_likes').insert({
        'post_id': postId,
        'user_id': currentUserId!,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      if (!e.toString().contains('duplicate key')) {
        throw Exception('Failed to like post: $e');
      }
    }
  }

  static Future<void> unlikePost(String postId) async {
    ensureUserAuthenticated();
    
    try {
      await _supabase
          .from('post_likes')
          .delete()
          .eq('post_id', postId)
          .eq('user_id', currentUserId!);
    } catch (e) {
      throw Exception('Failed to unlike post: $e');
    }
  }

  static Future<int> getPostLikeCount(String postId) async {
    try {
      final response = await _supabase
          .from('post_likes')
          .select('id')
          .eq('post_id', postId);
      
      return (response as List).length;
    } catch (e) {
      return 0;
    }
  }

  static Future<bool> hasUserLikedPost(String postId) async {
    if (currentUserId == null) return false;
    
    try {
      final response = await _supabase
          .from('post_likes')
          .select('id')
          .eq('post_id', postId)
          .eq('user_id', currentUserId!)
          .maybeSingle();
      
      return response != null;
    } catch (e) {
      return false;
    }
  }

  // ==================================================
  // COMMENTS & REVIEWS
  // ==================================================

  static Future<List<Map<String, dynamic>>> getRecipeComments(int recipeId) async {
    try {
      final response = await _supabase
          .from('recipe_comments')
          .select('''
            *,
            user:user_profiles!recipe_comments_user_id_fkey(id, username, first_name, last_name, avatar_url)
          ''')
          .eq('recipe_id', recipeId)
          .order('created_at', ascending: false);
      
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      throw Exception('Failed to get comments: $e');
    }
  }

  static Future<String> addComment({
    required int recipeId,
    required String commentText,
    String? parentCommentId,
  }) async {
    ensureUserAuthenticated();
    
    try {
      final response = await _supabase
          .from('recipe_comments')
          .insert({
            'recipe_id': recipeId,
            'user_id': currentUserId!,
            'comment_text': commentText,
            'parent_comment_id': parentCommentId,
            'created_at': DateTime.now().toIso8601String(),
          })
          .select()
          .single();
      
      await awardBadge('first_comment');
      await addXP(5, reason: 'Comment posted');
      
      final commentCount = await _getUserCommentCount();
      if (commentCount >= 10) await awardBadge('comments_10');
      if (commentCount >= 50) await awardBadge('comments_50');
      
      return response['id'];
    } catch (e) {
      throw Exception('Failed to add comment: $e');
    }
  }

  static Future<int> _getUserCommentCount() async {
    if (currentUserId == null) return 0;
    
    try {
      final response = await _supabase
          .from('recipe_comments')
          .select('id')
          .eq('user_id', currentUserId!);
      
      return (response as List).length;
    } catch (e) {
      return 0;
    }
  }

  static Future<void> updateComment(String commentId, String newText) async {
    ensureUserAuthenticated();
    
    try {
      await _supabase
          .from('recipe_comments')
          .update({
            'comment_text': newText,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', commentId)
          .eq('user_id', currentUserId!);
    } catch (e) {
      throw Exception('Failed to update comment: $e');
    }
  }

  static Future<void> deleteComment(String commentId) async {
    ensureUserAuthenticated();
    
    try {
      await _supabase
          .from('recipe_comments')
          .delete()
          .eq('id', commentId)
          .eq('user_id', currentUserId!);
    } catch (e) {
      throw Exception('Failed to delete comment: $e');
    }
  }

  static Future<void> likeComment(String commentId) async {
    ensureUserAuthenticated();
    
    try {
      await _supabase.from('comment_likes').insert({
        'comment_id': commentId,
        'user_id': currentUserId!,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      if (!e.toString().contains('duplicate key')) {
        throw Exception('Failed to like comment: $e');
      }
    }
  }

  static Future<void> unlikeComment(String commentId) async {
    ensureUserAuthenticated();
    
    try {
      await _supabase
          .from('comment_likes')
          .delete()
          .eq('comment_id', commentId)
          .eq('user_id', currentUserId!);
    } catch (e) {
      throw Exception('Failed to unlike comment: $e');
    }
  }

  static Future<void> reportComment(String commentId, String reason) async {
    ensureUserAuthenticated();
    
    try {
      await _supabase.from('comment_reports').insert({
        'comment_id': commentId,
        'reporter_id': currentUserId!,
        'reason': reason,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      if (!e.toString().contains('duplicate key')) {
        throw Exception('Failed to report comment: $e');
      }
    }
  }

  // ==================================================
  // USER PROFILE MANAGEMENT
  // ==================================================
  
  static Future<void> createUserProfile(
    String userId, 
    String email, 
    {bool isPremium = false}
  ) async {
    try {
      await _supabase.from('user_profiles').insert({
        'id': userId,
        'email': email,
        'is_premium': isPremium,
        'daily_scans_used': 0,
        'last_scan_date': DateTime.now().toIso8601String().split('T')[0],
        'created_at': DateTime.now().toIso8601String(),
        'username': email.split('@')[0],
        'friends_list_visible': true,
        'xp': 0,
        'level': 1,
      });
      
      await awardBadge('early_adopter');
    } catch (e) {
      throw Exception('Failed to create user profile: $e');
    }
  }

  static Future<Map<String, dynamic>?> getUserProfile(String userId) async {
    try {
      final response = await _supabase
          .from('user_profiles')
          .select()
          .eq('id', userId)
          .single();
      return response;
    } catch (e) {
      throw Exception('Failed to get user profile: $e');
    }
  }

  static Future<Map<String, dynamic>?> getCurrentUserProfile() async {
    final userId = currentUserId;
    if (userId == null) return null;
    
    try {
      return await getUserProfile(userId);
    } catch (e) {
      return null;
    }
  }

  static Future<bool> isUsernameAvailable(String username) async {
    try {
      final response = await _supabase
          .from('user_profiles')
          .select('id')
          .ilike('username', username)
          .maybeSingle();
      
      return response == null;
    } catch (e) {
      throw Exception('Failed to check username availability: $e');
    }
  }

  static Future<void> updateProfile({
    String? username,
    String? email,
    String? firstName,
    String? lastName,
    String? avatarUrl,
    String? profilePicture,
  }) async {
    ensureUserAuthenticated();
    
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

      await _supabase
          .from('user_profiles')
          .update(updates)
          .eq('id', currentUserId!);
          
    } catch (e) {
      if (e.toString().contains('duplicate key value') || 
          e.toString().contains('unique constraint')) {
        throw Exception('Username is already taken. Please choose a different username.');
      }
      throw Exception('Failed to update profile: $e');
    }
  }

  static Future<void> setPremiumStatus(String userId, bool isPremium) async {
    ensureUserAuthenticated();
    
    try {
      await _supabase.from('user_profiles').update({
        'is_premium': isPremium,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', userId);
    } catch (e) {
      throw Exception('Failed to update premium status: $e');
    }
  }

  static Future<bool> isPremiumUser() async {
    final userId = AuthService.currentUserId;
    if (userId == null) return false;

    try {
      final profile = await getUserProfile(userId);
      return profile?['is_premium'] ?? false;
    } catch (e) {
      return false;
    }
  }

  // ==================================================
  // PROFILE PICTURES MANAGEMENT
  // ==================================================

  static Future<String> uploadPicture(File imageFile) async {
    ensureUserAuthenticated();
    
    try {
      final userId = currentUserId!;
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'picture_$timestamp.jpg';
      final filePath = '$userId/$fileName';
      
      await _supabase.storage
          .from('profile-pictures')
          .upload(filePath, imageFile);
      
      final publicUrl = _supabase.storage
          .from('profile-pictures')
          .getPublicUrl(filePath);
      
      final profile = await getCurrentUserProfile();
      final currentPictures = profile?['pictures'];
      
      List<String> picturesList = [];
      if (currentPictures != null && currentPictures.isNotEmpty) {
        try {
          picturesList = List<String>.from(jsonDecode(currentPictures));
        } catch (e) {
          print('Error parsing pictures: $e');
        }
      }
      
      picturesList.add(publicUrl);
      
      await _supabase
          .from('user_profiles')
          .update({
            'pictures': jsonEncode(picturesList),
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', userId);
      
      return publicUrl;
    } catch (e) {
      throw Exception('Failed to upload picture: $e');
    }
  }

  static Future<List<String>> getUserPictures(String userId) async {
    try {
      final profile = await getUserProfile(userId);
      final picturesJson = profile?['pictures'];
      
      if (picturesJson == null || picturesJson.isEmpty) {
        return [];
      }
      
      try {
        return List<String>.from(jsonDecode(picturesJson));
      } catch (e) {
        print('Error parsing pictures: $e');
        return [];
      }
    } catch (e) {
      print('Error getting pictures: $e');
      return [];
    }
  }

  static Future<List<String>> getCurrentUserPictures() async {
    if (currentUserId == null) return [];
    return getUserPictures(currentUserId!);
  }

  static Future<void> deletePicture(String pictureUrl) async {
    ensureUserAuthenticated();
    
    try {
      final userId = currentUserId!;
      
      final uri = Uri.parse(pictureUrl);
      final pathSegments = uri.pathSegments;
      
      final bucketIndex = pathSegments.indexOf('profile-pictures');
      if (bucketIndex != -1 && bucketIndex < pathSegments.length - 1) {
        final filePath = pathSegments.sublist(bucketIndex + 1).join('/');
        
        await _supabase.storage
            .from('profile-pictures')
            .remove([filePath]);
      }
      
      final profile = await getCurrentUserProfile();
      final currentPictures = profile?['pictures'];
      
      if (currentPictures != null && currentPictures.isNotEmpty) {
        List<String> picturesList = List<String>.from(jsonDecode(currentPictures));
        picturesList.remove(pictureUrl);
        
        await _supabase
            .from('user_profiles')
            .update({
              'pictures': jsonEncode(picturesList),
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('id', userId);
      }
    } catch (e) {
      throw Exception('Failed to delete picture: $e');
    }
  }

  static Future<void> setPictureAsProfilePicture(String pictureUrl) async {
    ensureUserAuthenticated();
    
    try {
      await _supabase
          .from('user_profiles')
          .update({
            'profile_picture': pictureUrl,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', currentUserId!);
    } catch (e) {
      throw Exception('Failed to set profile picture: $e');
    }
  }

  static Future<String?> getProfilePictureUrl(String userId) async {
    try {
      final profile = await getUserProfile(userId);
      return profile?['profile_picture'];
    } catch (e) {
      print('Error getting profile picture: $e');
      return null;
    }
  }

  // ==================================================
  // FRIENDS LIST VISIBILITY
  // ==================================================
  
  static Future<List<Map<String, dynamic>>> getUserFriends(String userId) async {
    try {
      final response = await _supabase
          .from('friend_requests')
          .select('''
            sender:user_profiles!friend_requests_sender_fkey(id, email, username, first_name, last_name, avatar_url),
            receiver:user_profiles!friend_requests_receiver_fkey(id, email, username, first_name, last_name, avatar_url)
          ''')
          .or('sender.eq.$userId,receiver.eq.$userId')
          .eq('status', 'accepted');

      final friends = <Map<String, dynamic>>[];
      for (var row in response) {
        final friend = row['sender']['id'] == userId 
            ? row['receiver'] 
            : row['sender'];
        friends.add(friend);
      }
      return friends;
    } catch (e) {
      throw Exception('Failed to load friends list: $e');
    }
  }

  static Future<bool> getFriendsListVisibility() async {
    ensureUserAuthenticated();
    
    try {
      final profile = await getCurrentUserProfile();
      return profile?['friends_list_visible'] ?? true;
    } catch (e) {
      return true;
    }
  }

  static Future<void> updateFriendsListVisibility(bool isVisible) async {
    ensureUserAuthenticated();
    
    try {
      await _supabase
          .from('user_profiles')
          .update({
            'friends_list_visible': isVisible,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', currentUserId!);
    } catch (e) {
      throw Exception('Failed to update privacy setting: $e');
    }
  }

  // ==================================================
  // SCAN COUNT MANAGEMENT
  // ==================================================
  
  static Future<int> getDailyScanCount() async {
    final userId = AuthService.currentUserId;
    if (userId == null) return 0;

    try {
      final profile = await getUserProfile(userId);
      final today = DateTime.now().toIso8601String().split('T')[0];
      final lastScanDate = profile?['last_scan_date'] ?? '';

      if (lastScanDate != today) {
        await _supabase.from('user_profiles').update({
          'daily_scans_used': 0,
          'last_scan_date': today,
        }).eq('id', userId);
        return 0;
      }

      return profile?['daily_scans_used'] ?? 0;
    } catch (e) {
      return 0;
    }
  }

  static Future<bool> canPerformScan() async {
    try {
      if (await isPremiumUser()) return true;
      
      final dailyCount = await getDailyScanCount();
      return dailyCount < 3;
    } catch (e) {
      return true;
    }
  }

  static Future<void> incrementScanCount() async {
    try {
      if (await isPremiumUser()) return;

      final currentCount = await getDailyScanCount();
      await _supabase.from('user_profiles').update({
        'daily_scans_used': currentCount + 1,
      }).eq('id', currentUserId!);
      
      await awardBadge('first_scan');
      final totalScans = currentCount + 1;
      if (totalScans >= 10) await awardBadge('scans_10');
      if (totalScans >= 50) await awardBadge('scans_50');
    } catch (e) {
      throw Exception('Failed to update scan count: $e');
    }
  }

  // ==================================================
  // FAVORITE RECIPES
  // ==================================================
  
  static Future<List<FavoriteRecipe>> getFavoriteRecipes() async {
    if (currentUserId == null) return [];

    try {
      final response = await _supabase
          .from('favorite_recipes')
          .select()
          .eq('user_id', currentUserId!)
          .order('created_at', ascending: false);

      return (response as List)
      // CONTINUATION FROM: return (response as List)
          .map((recipe) => FavoriteRecipe.fromJson(recipe))
          .toList();
    } catch (e) {
      throw Exception('Failed to load favorite recipes: $e');
    }
  }

  static Future<void> addFavoriteRecipe(
      String recipeName, String ingredients, String directions) async {
    ensureUserAuthenticated();

    try {
      await _supabase.from('favorite_recipes').insert({
        'user_id': currentUserId!,
        'recipe_name': recipeName,
        'ingredients': ingredients,
        'directions': directions,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      throw Exception('Failed to add favorite recipe: $e');
    }
  }

  static Future<void> removeFavoriteRecipe(int recipeId) async {
    ensureUserAuthenticated();

    try {
      await _supabase.from('favorite_recipes').delete().eq('id', recipeId);
    } catch (e) {
      throw Exception('Failed to remove favorite recipe: $e');
    }
  }

  static Future<bool> isRecipeFavorited(String recipeName) async {
    if (currentUserId == null) return false;

    try {
      final response = await _supabase
          .from('favorite_recipes')
          .select('id')
          .eq('user_id', currentUserId!)
          .eq('recipe_name', recipeName)
          .maybeSingle();

      return response != null;
    } catch (e) {
      return false;
    }
  }

  // ==================================================
  // GROCERY LIST - ENHANCED WITH QUANTITY SUPPORT
  // ==================================================
  
  static Future<List<GroceryItem>> getGroceryList() async {
    if (currentUserId == null) return [];

    try {
      final response = await _supabase
          .from('grocery_items')
          .select()
          .eq('user_id', currentUserId!)
          .order('order_index', ascending: true);

      return (response as List)
          .map((item) => GroceryItem.fromJson(item))
          .toList();
    } catch (e) {
      throw Exception('Failed to load grocery list: $e');
    }
  }

  static Future<void> saveGroceryList(List<String> items) async {
    ensureUserAuthenticated();

    try {
      await _supabase
          .from('grocery_items')
          .delete()
          .eq('user_id', currentUserId!);

      if (items.isNotEmpty) {
        final groceryItems = items.asMap().entries.map((entry) => {
              'user_id': currentUserId!,
              'item': entry.value, // Stores "2 x Milk" format or just "Milk"
              'order_index': entry.key,
              'created_at': DateTime.now().toIso8601String(),
            }).toList();

        await _supabase.from('grocery_items').insert(groceryItems);
      }
    } catch (e) {
      throw Exception('Failed to save grocery list: $e');
    }
  }

  static Future<void> clearGroceryList() async {
    ensureUserAuthenticated();

    try {
      await _supabase
          .from('grocery_items')
          .delete()
          .eq('user_id', currentUserId!);
    } catch (e) {
      throw Exception('Failed to clear grocery list: $e');
    }
  }

  // NEW: Parse grocery item with quantity
  static Map<String, String> parseGroceryItem(String itemText) {
    // Parse "quantity x item" format
    final parts = itemText.split(' x ');
    
    if (parts.length == 2) {
      return {
        'quantity': parts[0].trim(),
        'name': parts[1].trim(),
      };
    } else {
      return {
        'quantity': '',
        'name': itemText.trim(),
      };
    }
  }

  // NEW: Format grocery item with quantity
  static String formatGroceryItem(String name, String quantity) {
    if (quantity.isNotEmpty) {
      return '$quantity x $name';
    } else {
      return name;
    }
  }

  // ENHANCED: Add to grocery list with optional quantity
  static Future<void> addToGroceryList(String item, {String? quantity}) async {
    ensureUserAuthenticated();

    try {
      final currentItems = await getGroceryList();
      final newOrderIndex = currentItems.length;
      
      // Format with quantity if provided
      final formattedItem = quantity != null && quantity.isNotEmpty 
          ? '$quantity x $item' 
          : item;

      await _supabase.from('grocery_items').insert({
        'user_id': currentUserId!,
        'item': formattedItem,
        'order_index': newOrderIndex,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      throw Exception('Failed to add item to grocery list: $e');
    }
  }

  static List<String> _parseIngredients(String ingredientsText) {
    final items = ingredientsText
        .split(RegExp(r'[,\n•\-\*]|\d+\.'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .map((item) {
          item = item.replaceAll(RegExp(r'^\d+\s*(cups?|tbsp|tsp|lbs?|oz|grams?|kg|ml|liters?)?\s*'), '');
          item = item.replaceAll(RegExp(r'^\d+/\d+\s*(cups?|tbsp|tsp|lbs?|oz|grams?|kg|ml|liters?)?\s*'), '');
          item = item.replaceAll(RegExp(r'^(a\s+)?(pinch\s+of\s+|dash\s+of\s+)?'), '');
          return item.trim();
        })
        .where((item) => item.isNotEmpty && item.length > 2)
        .toList();
    return items;
  }

  static bool _areItemsSimilar(String item1, String item2) {
    final clean1 = item1.toLowerCase().replaceAll(RegExp(r'[^a-z\s]'), '').trim();
    final clean2 = item2.toLowerCase().replaceAll(RegExp(r'[^a-z\s]'), '').trim();
    
    if (clean1 == clean2) return true;
    if (clean1.contains(clean2) || clean2.contains(clean1)) return true;
    
    return false;
  }

  // ENHANCED: Add recipe to shopping list with better quantity handling
  static Future<Map<String, dynamic>> addRecipeToShoppingList(
    String recipeName,
    String ingredients,
  ) async {
    ensureUserAuthenticated();

    try {
      final currentItems = await getGroceryList();
      final currentItemNames = currentItems.map((item) {
        // Parse out quantity to compare just the item names
        final parsed = parseGroceryItem(item.item);
        return parsed['name']!.toLowerCase();
      }).toList();
      
      final newIngredients = _parseIngredients(ingredients);
      
      final itemsToAdd = <String>[];
      final skippedItems = <String>[];
      
      for (final newItem in newIngredients) {
        bool isDuplicate = false;
        
        for (final existingItemName in currentItemNames) {
          if (_areItemsSimilar(newItem.toLowerCase(), existingItemName)) {
            isDuplicate = true;
            skippedItems.add(newItem);
            break;
          }
        }
        
        if (!isDuplicate) {
          bool isDuplicateInNewItems = false;
          for (final addedItem in itemsToAdd) {
            if (_areItemsSimilar(newItem.toLowerCase(), addedItem.toLowerCase())) {
              isDuplicateInNewItems = true;
              break;
            }
          }
          
          if (!isDuplicateInNewItems) {
            itemsToAdd.add(newItem);
          } else {
            skippedItems.add(newItem);
          }
        }
      }

      final updatedList = [
        ...currentItems.map((item) => item.item),
        ...itemsToAdd,
      ];
      await saveGroceryList(updatedList);

      return {
        'added': itemsToAdd.length,
        'skipped': skippedItems.length,
        'addedItems': itemsToAdd,
        'skippedItems': skippedItems,
        'recipeName': recipeName,
      };
    } catch (e) {
      throw Exception('Failed to add recipe to shopping list: $e');
    }
  }

  static Future<int> getShoppingListCount() async {
    try {
      final items = await getGroceryList();
      return items.length;
    } catch (e) {
      return 0;
    }
  }

  // ==================================================
  // SUBMITTED RECIPES
  // ==================================================
  
  static Future<List<SubmittedRecipe>> getSubmittedRecipes() async {
    if (currentUserId == null) return [];

    try {
      final response = await _supabase
          .from('submitted_recipes')
          .select()
          .eq('user_id', currentUserId!)
          .order('created_at', ascending: false);

      return (response as List)
          .map((recipe) => SubmittedRecipe.fromJson(recipe))
          .toList();
    } catch (e) {
      throw Exception('Failed to load submitted recipes: $e');
    }
  }

  static Future<void> submitRecipe(
      String recipeName, String ingredients, String directions) async {
    ensureUserAuthenticated();

    try {
      await _supabase.from('submitted_recipes').insert({
        'user_id': currentUserId!,
        'recipe_name': recipeName,
        'ingredients': ingredients,
        'directions': directions,
        'created_at': DateTime.now().toIso8601String(),
      });
      
      await addXP(50, reason: 'Recipe submitted');
      await checkAchievements();
    } catch (e) {
      throw Exception('Failed to submit recipe: $e');
    }
  }

  static Future<void> deleteSubmittedRecipe(int recipeId) async {
    ensureUserAuthenticated();

    try {
      await _supabase.from('submitted_recipes').delete().eq('id', recipeId);
    } catch (e) {
      throw Exception('Failed to delete submitted recipe: $e');
    }
  }

  // ==================================================
  // RECIPE RATINGS & MANAGEMENT
  // ==================================================

  static Future<void> rateRecipe(int recipeId, int rating) async {
    ensureUserAuthenticated();
    
    if (rating < 1 || rating > 5) {
      throw Exception('Rating must be between 1 and 5');
    }

    try {
      final recipe = await _supabase
          .from('submitted_recipes')
          .select('user_id')
          .eq('id', recipeId)
          .single();
      
      if (recipe['user_id'] == currentUserId) {
        throw Exception('You cannot rate your own recipe');
      }

      await _supabase.from('recipe_ratings').upsert({
        'recipe_id': recipeId,
        'user_id': currentUserId!,
        'rating': rating,
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      throw Exception('Failed to rate recipe: $e');
    }
  }

  static Future<List<Map<String, dynamic>>> getRecipeRatings(int recipeId) async {
    try {
      final response = await _supabase
          .from('recipe_ratings')
          .select('*, user_profiles!recipe_ratings_user_id_fkey(username, first_name, last_name)')
          .eq('recipe_id', recipeId)
          .order('created_at', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      throw Exception('Failed to get recipe ratings: $e');
    }
  }

  static Future<Map<String, dynamic>> getRecipeAverageRating(int recipeId) async {
    try {
      final response = await _supabase
          .from('recipe_ratings')
          .select('rating')
          .eq('recipe_id', recipeId);

      if (response.isEmpty) {
        return {'average': 0.0, 'count': 0};
      }

      final ratings = List<Map<String, dynamic>>.from(response);
      final sum = ratings.fold<int>(0, (sum, item) => sum + (item['rating'] as int));
      final average = sum / ratings.length;

      return {
        'average': double.parse(average.toStringAsFixed(1)),
        'count': ratings.length,
      };
    } catch (e) {
      return {'average': 0.0, 'count': 0};
    }
  }

  static Future<bool> hasUserRatedRecipe(int recipeId) async {
    if (currentUserId == null) return false;

    try {
      final response = await _supabase
          .from('recipe_ratings')
          .select('id')
          .eq('recipe_id', recipeId)
          .eq('user_id', currentUserId!)
          .maybeSingle();

      return response != null;
    } catch (e) {
      return false;
    }
  }

  static Future<int?> getUserRecipeRating(int recipeId) async {
    if (currentUserId == null) return null;

    try {
      final response = await _supabase
          .from('recipe_ratings')
          .select('rating')
          .eq('recipe_id', recipeId)
          .eq('user_id', currentUserId!)
          .maybeSingle();

      return response?['rating'];
    } catch (e) {
      return null;
    }
  }

  static Future<void> updateSubmittedRecipe({
    required int recipeId,
    required String recipeName,
    required String ingredients,
    required String directions,
  }) async {
    ensureUserAuthenticated();

    try {
      final recipe = await _supabase
          .from('submitted_recipes')
          .select('user_id')
          .eq('id', recipeId)
          .single();

      if (recipe['user_id'] != currentUserId) {
        throw Exception('You can only edit your own recipes');
      }

      await _supabase.from('submitted_recipes').update({
        'recipe_name': recipeName,
        'ingredients': ingredients,
        'directions': directions,
      }).eq('id', recipeId);
    } catch (e) {
      throw Exception('Failed to update recipe: $e');
    }
  }

  static Future<Map<String, dynamic>?> getRecipeById(int recipeId) async {
    try {
      final response = await _supabase
          .from('submitted_recipes')
          .select()
          .eq('id', recipeId)
          .single();

      return response;
    } catch (e) {
      throw Exception('Failed to get recipe: $e');
    }
  }

  static String generateShareableRecipeText(Map<String, dynamic> recipe) {
    final name = recipe['recipe_name'] ?? 'Unnamed Recipe';
    final ingredients = recipe['ingredients'] ?? 'No ingredients listed';
    final directions = recipe['directions'] ?? 'No directions provided';

    return '''
🍽️ Recipe: $name

📋 Ingredients:
$ingredients

👨‍🍳 Directions:
$directions

---
Shared from Recipe Scanner App
''';
  }

  // ==================================================
  // CONTACT MESSAGES
  // ==================================================
  
  static Future<void> submitContactMessage({
    required String name,
    required String email,
    required String message,
  }) async {
    try {
      await _supabase.from('contact_messages').insert({
        'name': name,
        'email': email,
        'message': message,
        'user_id': currentUserId,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      throw Exception('Failed to submit contact message: $e');
    }
  }

  // ==================================================
  // SOCIAL FEATURES - FRIENDS
  // ==================================================

  static Future<List<Map<String, dynamic>>> getFriends() async {
    ensureUserAuthenticated();
    
    try {
      final response = await _supabase
          .from('friend_requests')
          .select('sender:user_profiles!friend_requests_sender_fkey(id, email, username, first_name, last_name, avatar_url), receiver:user_profiles!friend_requests_receiver_fkey(id, email, username, first_name, last_name, avatar_url)')
          .or('sender.eq.$currentUserId,receiver.eq.$currentUserId')
          .eq('status', 'accepted');

      final friends = <Map<String, dynamic>>[];
      for (var row in response) {
        final friend = row['sender']['id'] == currentUserId 
            ? row['receiver'] 
            : row['sender'];
        friends.add(friend);
      }
      return friends;
    } catch (e) {
      throw Exception('Failed to load friends: $e');
    }
  }

  static Future<List<Map<String, dynamic>>> getFriendRequests() async {
    ensureUserAuthenticated();
    
    try {
      final response = await _supabase
          .from('friend_requests')
          .select('id, created_at, sender:user_profiles!friend_requests_sender_fkey(id, email, username, first_name, last_name, avatar_url)')
          .eq('receiver', currentUserId!)
          .eq('status', 'pending')
          .order('created_at', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      throw Exception('Failed to load friend requests: $e');
    }
  }

  static Future<List<Map<String, dynamic>>> getSentFriendRequests() async {
    ensureUserAuthenticated();
    
    try {
      final response = await _supabase
          .from('friend_requests')
          .select('id, created_at, receiver:user_profiles!friend_requests_receiver_fkey(id, email, username, first_name, last_name, avatar_url)')
          .eq('sender', currentUserId!)
          .eq('status', 'pending')
          .order('created_at', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      throw Exception('Failed to load sent friend requests: $e');
    }
  }

  static Future<String?> sendFriendRequest(String receiverId) async {
    ensureUserAuthenticated();
    
    if (receiverId == currentUserId) {
      throw Exception('Cannot send friend request to yourself');
    }
    
    try {
      final existing = await _supabase
          .from('friend_requests')
          .select('id, status, sender, receiver')
          .or('and(sender.eq.$currentUserId,receiver.eq.$receiverId),and(sender.eq.$receiverId,receiver.eq.$currentUserId)')
          .maybeSingle();

      if (existing != null) {
        if (existing['status'] == 'accepted') {
          throw Exception('You are already friends with this user');
        } else if (existing['status'] == 'pending') {
          if (existing['sender'] == receiverId) {
            throw Exception('This user has already sent you a friend request. Check your pending requests!');
          }
          throw Exception('Friend request already sent');
        }
      }

      final response = await _supabase
          .from('friend_requests')
          .insert({
            'sender': currentUserId!,
            'receiver': receiverId,
            'status': 'pending',
            'created_at': DateTime.now().toIso8601String(),
          })
          .select()
          .single();

      return response['id'];
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        throw Exception('Friend request already exists');
      }
      throw Exception('Failed to send friend request: ${e.message}');
    } catch (e) {
      throw Exception('Failed to send friend request: $e');
    }
  }

  static Future<void> acceptFriendRequest(String requestId) async {
    ensureUserAuthenticated();
    
    try {
      final request = await _supabase
          .from('friend_requests')
          .select('receiver, status')
          .eq('id', requestId)
          .single();
      
      if (request['receiver'] != currentUserId) {
        throw Exception('You cannot accept this friend request');
      }
      
      if (request['status'] != 'pending') {
        throw Exception('This friend request has already been ${request['status']}');
      }

      await _supabase
          .from('friend_requests')
          .update({
            'status': 'accepted',
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', requestId);
    } catch (e) {
      throw Exception('Failed to accept friend request: $e');
    }
  }

  static Future<void> declineFriendRequest(String requestId) async {
    ensureUserAuthenticated();
    
    try {
      await _supabase
          .from('friend_requests')
          .delete()
          .eq('id', requestId);
    } catch (e) {
      throw Exception('Failed to decline friend request: $e');
    }
  }

  static Future<void> cancelFriendRequestById(String requestId) async {
    ensureUserAuthenticated();
    
    try {
      final request = await _supabase
          .from('friend_requests')
          .select('sender')
          .eq('id', requestId)
          .single();
      
      if (request['sender'] != currentUserId) {
        throw Exception('You cannot cancel this friend request');
      }

      await _supabase
          .from('friend_requests')
          .delete()
          .eq('id', requestId);
    } catch (e) {
      throw Exception('Failed to cancel friend request: $e');
    }
  }

  static Future<void> cancelFriendRequest(String receiverId) async {
    ensureUserAuthenticated();
    
    try {
      await _supabase
          .from('friend_requests')
          .delete()
          .eq('sender', currentUserId!)
          .eq('receiver', receiverId);
    } catch (e) {
      throw Exception('Failed to cancel friend request: $e');
    }
  }

  static Future<void> removeFriend(String friendId) async {
    ensureUserAuthenticated();
    
    try {
      await _supabase
          .from('friend_requests')
          .delete()
          .or('and(sender.eq.$currentUserId,receiver.eq.$friendId),and(sender.eq.$friendId,receiver.eq.$currentUserId)')
          .eq('status', 'accepted');
    } catch (e) {
      throw Exception('Failed to remove friend: $e');
    }
  }

  static Future<Map<String, dynamic>> checkFriendshipStatus(String userId) async {
    ensureUserAuthenticated();
    
    if (userId == currentUserId) {
      return {
        'status': 'self',
        'requestId': null,
        'canSendRequest': false,
        'isOutgoing': false,
        'message': 'This is you!',
      };
    }
    
    try {
      final response = await _supabase
          .from('friend_requests')
          .select('id, status, sender, receiver, created_at')
          .or('and(sender.eq.$currentUserId,receiver.eq.$userId),and(sender.eq.$userId,receiver.eq.$currentUserId)')
          .maybeSingle();

      if (response == null) {
        return {
          'status': 'none',
          'requestId': null,
          'canSendRequest': true,
          'isOutgoing': false,
          'message': 'Not friends',
        };
      }

      final isOutgoing = response['sender'] == currentUserId;
      final status = response['status'];

      if (status == 'accepted') {
        return {
          'status': 'accepted',
          'requestId': response['id'],
          'canSendRequest': false,
          'isOutgoing': isOutgoing,
          'message': 'Friends',
        };
      } else if (status == 'pending') {
        if (isOutgoing) {
          return {
            'status': 'pending_sent',
            'requestId': response['id'],
            'canSendRequest': false,
            'isOutgoing': true,
            'message': 'Friend request sent',
          };
        } else {
          return {
            'status': 'pending_received',
            'requestId': response['id'],
            'canSendRequest': false,
            'isOutgoing': false,
            'message': 'Friend request received',
          };
        }
      }

      return {
        'status': 'unknown',
        'requestId': null,
        'canSendRequest': false,
        'isOutgoing': false,
        'message': 'Unknown status',
      };
    } catch (e) {
      return {
        'status': 'error',
        'requestId': null,
        'canSendRequest': false,
        'isOutgoing': false,
        'message': 'Error checking status',
      };
    }
  }

  // ==================================================
  // MESSAGING
  // ==================================================

  static Future<List<Map<String, dynamic>>> getMessages(String friendId) async {
    ensureUserAuthenticated();
    
    try {
      final response = await _supabase
          .from('messages')
          .select('*')
          .or('and(sender.eq.$currentUserId,receiver.eq.$friendId),and(sender.eq.$friendId,receiver.eq.$currentUserId)')
          .order('created_at');

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      throw Exception('Failed to load messages: $e');
    }
  }

  static Future<void> sendMessage(String receiverId, String content) async {
    ensureUserAuthenticated();
    
    try {
      await _supabase.from('messages').insert({
        'sender': currentUserId!,
        'receiver': receiverId,
        'content': content,
        'is_read': false,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      throw Exception('Failed to send message: $e');
    }
  }

  static Future<int> getUnreadMessageCount() async {
    ensureUserAuthenticated();
    
    try {
      final response = await _supabase
          .from('messages')
          .select('id')
          .eq('receiver', currentUserId!)
          .eq('is_read', false);

      return (response as List).length;
    } catch (e) {
      print('Error getting unread count: $e');
      return 0;
    }
  }

  static Future<void> markMessageAsRead(String messageId) async {
    ensureUserAuthenticated();
    
    try {
      await _supabase
          .from('messages')
          .update({'is_read': true})
          .eq('id', messageId);
    } catch (e) {
      print('Error marking message as read: $e');
    }
  }

  static Future<void> markMessagesAsReadFrom(String senderId) async {
    ensureUserAuthenticated();
    
    try {
      await _supabase
          .from('messages')
          .update({'is_read': true})
          .eq('receiver', currentUserId!)
          .eq('sender', senderId)
          .eq('is_read', false);
    } catch (e) {
      print('Error marking messages as read: $e');
    }
  }

  static Future<List<Map<String, dynamic>>> getChatList() async {
    ensureUserAuthenticated();
    
    try {
      final friends = await getFriends();
      final chats = <Map<String, dynamic>>[];

      for (final friend in friends) {
        final messages = await _supabase
            .from('messages')
            .select('*')
            .or('and(sender.eq.$currentUserId,receiver.eq.${friend['id']}),and(sender.eq.${friend['id']},receiver.eq.$currentUserId)')
            .order('created_at', ascending: false)
            .limit(1);

        if (messages.isNotEmpty) {
          chats.add({
            'friend': friend,
            'lastMessage': messages.first,
          });
        } else {
          chats.add({
            'friend': friend,
            'lastMessage': null,
          });
        }
      }

      chats.sort((a, b) {
        final aTime = a['lastMessage']?['created_at'];
        final bTime = b['lastMessage']?['created_at'];
        if (aTime == null && bTime == null) return 0;
        if (aTime == null) return 1;
        if (bTime == null) return -1;
        return bTime.compareTo(aTime);
      });

      return chats;
    } catch (e) {
      throw Exception('Failed to load chat list: $e');
    }
  }

  // ==================================================
  // USER SEARCH
  // ==================================================

  static Future<List<Map<String, dynamic>>> searchUsers(String query) async {
  ensureUserAuthenticated();
  
  try {
    final searchQuery = query.trim();
    if (searchQuery.isEmpty) return [];

    try {
      final response = await _supabase.rpc('search_users_fuzzy', params: {
        'search_query': searchQuery,
        'current_user_id': currentUserId!,
      });

      return List<Map<String, dynamic>>.from(response);
    } catch (rpcError) {
      print('RPC search failed, falling back to basic search: $rpcError');
      
      final response = await _supabase
          .from('user_profiles')
          .select('id, email, username, first_name, last_name, avatar_url')
          .or('email.ilike.%$searchQuery%,username.ilike.%$searchQuery%,first_name.ilike.%$searchQuery%,last_name.ilike.%$searchQuery%')
          .neq('id', currentUserId!)
          .limit(50);

      return List<Map<String, dynamic>>.from(response);
    }
  } catch (e) {
    throw Exception('Failed to search users: $e');
  }
}
static Future<void> debugTestUserSearch() async {
  ensureUserAuthenticated();
  
  try {
    print('🔍 DEBUG: Starting user search test...');
    print('📝 Current user ID: $currentUserId');
    
    print('\n--- TEST 1: Fetching all users ---');
    final allUsers = await _supabase
        .from('user_profiles')
        .select('id, email, username, first_name, last_name')
        .neq('id', currentUserId!)
        .limit(10);
    
    print('✅ Found ${(allUsers as List).length} users in database');
    for (var user in allUsers) {
      print('  👤 ${user['username'] ?? user['email']} (${user['first_name']} ${user['last_name']})');
    }
    
    print('\n--- TEST 2: Testing basic search ---');
    final searchResult = await _supabase
        .from('user_profiles')
        .select('id, email, username, first_name, last_name')
        .or('email.ilike.%test%,username.ilike.%test%,first_name.ilike.%test%,last_name.ilike.%test%')
        .neq('id', currentUserId!)
        .limit(10);
    
    print('✅ Basic search found ${(searchResult as List).length} results');
    
    print('\n--- TEST 3: Testing RPC function ---');
    try {
      final rpcResult = await _supabase.rpc('search_users_fuzzy', params: {
        'search_query': 'test',
        'current_user_id': currentUserId!,
      });
      print('✅ RPC function works! Found ${(rpcResult as List).length} results');
    } catch (rpcError) {
      print('⚠️  RPC function not available: $rpcError');
    }
    
    print('\n✅ DEBUG TEST COMPLETED');
  } catch (e) {
    print('❌ DEBUG TEST FAILED: $e');
    throw Exception('Debug test failed: $e');
  }
}}