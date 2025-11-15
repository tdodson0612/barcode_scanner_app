// lib/services/database_service.dart - COMPLETE WITH ALL METHODS
import 'dart:convert';
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/favorite_recipe.dart';
import '../models/grocery_item.dart';
import '../models/submitted_recipe.dart';
import 'auth_service.dart';

class DatabaseService {
  static final SupabaseClient _supabase = Supabase.instance.client;
  
  // Cache keys
  static const String _CACHE_BADGES = 'cache_badges';
  static const String _CACHE_USER_BADGES = 'cache_user_badges_';
  static const String _CACHE_USER_PROFILE = 'cache_user_profile_';
  static const String _CACHE_PROFILE_TIMESTAMP = 'cache_profile_timestamp_';
  static const String _CACHE_FRIENDS = 'cache_friends_';
  static const String _CACHE_MESSAGES = 'cache_messages_';
  static const String _CACHE_LAST_MESSAGE_TIME = 'cache_last_message_time_';
  static const String _CACHE_POSTS = 'cache_posts';
  static const String _CACHE_LAST_POST_TIME = 'cache_last_post_time';
  static const String _CACHE_USER_POSTS = 'cache_user_posts_';
  static const String _CACHE_SUBMITTED_RECIPES = 'cache_submitted_recipes';
  static const String _CACHE_FAVORITE_RECIPES = 'cache_favorite_recipes';

  // ==================================================
  // CACHE HELPER METHODS
  // ==================================================
  
  static Future<SharedPreferences> _getPrefs() async {
    return await SharedPreferences.getInstance();
  }

  static Future<void> _cacheData(String key, String data) async {
    final prefs = await _getPrefs();
    await prefs.setString(key, data);
  }

  static Future<String?> _getCachedData(String key) async {
    final prefs = await _getPrefs();
    return prefs.getString(key);
  }

  static Future<void> _clearCache(String key) async {
    final prefs = await _getPrefs();
    await prefs.remove(key);
  }

  static Future<void> clearAllUserCache() async {
    if (currentUserId == null) return;
    final prefs = await _getPrefs();
    final keys = prefs.getKeys().where((key) => 
      key.contains(currentUserId!) || 
      key == _CACHE_BADGES ||
      key == _CACHE_POSTS ||
      key == _CACHE_LAST_POST_TIME
    ).toList();
    for (final key in keys) {
      await prefs.remove(key);
    }
  }

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
      
      // Invalidate profile cache since XP changed
      await _clearCache('$_CACHE_USER_PROFILE$currentUserId');
      await _clearCache('$_CACHE_PROFILE_TIMESTAMP$currentUserId');
      
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
  // ACHIEVEMENTS & BADGES (CACHED - Static data)
  // ==================================================

  static Future<List<Map<String, dynamic>>> getAllBadges() async {
    try {
      final cached = await _getCachedData(_CACHE_BADGES);
      if (cached != null) {
        final List<dynamic> decoded = jsonDecode(cached);
        return List<Map<String, dynamic>>.from(decoded);
      }
      
      final response = await _supabase
          .from('badges')
          .select()
          .order('xp_reward');
      
      final badges = List<Map<String, dynamic>>.from(response);
      await _cacheData(_CACHE_BADGES, jsonEncode(badges));
      
      return badges;
    } catch (e) {
      throw Exception('Failed to get badges: $e');
    }
  }

  static Future<List<Map<String, dynamic>>> getUserBadges(String userId) async {
    try {
      final cacheKey = '$_CACHE_USER_BADGES$userId';
      final cached = await _getCachedData(cacheKey);
      if (cached != null) {
        final List<dynamic> decoded = jsonDecode(cached);
        return List<Map<String, dynamic>>.from(decoded);
      }
      
      final response = await _supabase
          .from('user_achievements')
          .select('*, badge:badges(*)')
          .eq('user_id', userId)
          .order('earned_at', ascending: false);
      
      final badges = List<Map<String, dynamic>>.from(response);
      await _cacheData(cacheKey, jsonEncode(badges));
      
      return badges;
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
      
      await _clearCache('$_CACHE_USER_BADGES$currentUserId');
      
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
  // USER PROFILE MANAGEMENT (WITH TIMESTAMP CACHING)
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
      final cacheKey = '$_CACHE_USER_PROFILE$userId';
      final timestampKey = '$_CACHE_PROFILE_TIMESTAMP$userId';
      
      final cached = await _getCachedData(cacheKey);
      final cachedTimestamp = await _getCachedData(timestampKey);
      
      if (cached != null && cachedTimestamp != null) {
        final serverProfile = await _supabase
            .from('user_profiles')
            .select('updated_at')
            .eq('id', userId)
            .single();
        
        final serverTimestamp = serverProfile['updated_at'] ?? '';
        
        if (serverTimestamp == cachedTimestamp) {
          return jsonDecode(cached);
        }
      }
      
      final response = await _supabase
          .from('user_profiles')
          .select()
          .eq('id', userId)
          .single();
      
      await _cacheData(cacheKey, jsonEncode(response));
      await _cacheData(timestampKey, response['updated_at'] ?? DateTime.now().toIso8601String());
      
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

  // ==================================================
  // RECIPE MANAGEMENT - SUBMITTED RECIPES (CACHED)
  // ==================================================
  
  static Future<List<SubmittedRecipe>> getSubmittedRecipes() async {
    if (currentUserId == null) return [];

    try {
      final cached = await _getCachedData(_CACHE_SUBMITTED_RECIPES);
      if (cached != null) {
        final List<dynamic> decoded = jsonDecode(cached);
        return decoded.map((recipe) => SubmittedRecipe.fromJson(recipe)).toList();
      }
      
      final response = await _supabase
          .from('submitted_recipes')
          .select()
          .eq('user_id', currentUserId!)
          .order('created_at', ascending: false);

      final recipes = (response as List)
          .map((recipe) => SubmittedRecipe.fromJson(recipe))
          .toList();
      
      await _cacheData(_CACHE_SUBMITTED_RECIPES, jsonEncode(response));
      
      return recipes;
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
      
      await _clearCache(_CACHE_SUBMITTED_RECIPES);
      await addXP(50, reason: 'Recipe submitted');
      await checkAchievements();
    } catch (e) {
      throw Exception('Failed to submit recipe: $e');
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
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', recipeId);
      
      await _clearCache(_CACHE_SUBMITTED_RECIPES);
    } catch (e) {
      throw Exception('Failed to update recipe: $e');
    }
  }

  static Future<void> deleteSubmittedRecipe(int recipeId) async {
    ensureUserAuthenticated();

    try {
      await _supabase.from('submitted_recipes').delete().eq('id', recipeId);
      await _clearCache(_CACHE_SUBMITTED_RECIPES);
    } catch (e) {
      throw Exception('Failed to delete submitted recipe: $e');
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
        
        await _clearCache('$_CACHE_USER_PROFILE$userId');
        await _clearCache('$_CACHE_PROFILE_TIMESTAMP$userId');
        
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
      
      await _clearCache('$_CACHE_USER_PROFILE$currentUserId');
      await _clearCache('$_CACHE_PROFILE_TIMESTAMP$currentUserId');
      
      await awardBadge('first_scan');
      final totalScans = currentCount + 1;
      if (totalScans >= 10) await awardBadge('scans_10');
      if (totalScans >= 50) await awardBadge('scans_50');
    } catch (e) {
      throw Exception('Failed to update scan count: $e');
    }
  }

  // Continue with remaining methods from your original file...
  // (All other methods remain unchanged from your original document #2)
  
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
      
      await _clearCache('$_CACHE_USER_PROFILE$currentUserId');
      await _clearCache('$_CACHE_PROFILE_TIMESTAMP$currentUserId');
          
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
      
      await _clearCache('$_CACHE_USER_PROFILE$userId');
      await _clearCache('$_CACHE_PROFILE_TIMESTAMP$userId');
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
      
      await _clearCache('$_CACHE_USER_PROFILE$userId');
      await _clearCache('$_CACHE_PROFILE_TIMESTAMP$userId');
      
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
        
        await _clearCache('$_CACHE_USER_PROFILE$userId');
        await _clearCache('$_CACHE_PROFILE_TIMESTAMP$userId');
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
      
      await _clearCache('$_CACHE_USER_PROFILE$currentUserId');
      await _clearCache('$_CACHE_PROFILE_TIMESTAMP$currentUserId');
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
      
      await _clearCache('$_CACHE_USER_PROFILE$currentUserId');
      await _clearCache('$_CACHE_PROFILE_TIMESTAMP$currentUserId');
    } catch (e) {
      throw Exception('Failed to update privacy setting: $e');
    }
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
  // FAVORITE RECIPES (CACHED)
  // ==================================================
  
  static Future<List<FavoriteRecipe>> getFavoriteRecipes() async {
    if (currentUserId == null) return [];

    try {
      final cached = await _getCachedData(_CACHE_FAVORITE_RECIPES);
      if (cached != null) {
        final List<dynamic> decoded = jsonDecode(cached);
        return decoded.map((recipe) => FavoriteRecipe.fromJson(recipe)).toList();
      }
      
      final response = await _supabase
          .from('favorite_recipes')
          .select()
          .eq('user_id', currentUserId!)
          .order('created_at', ascending: false);

      final recipes = (response as List)
          .map((recipe) => FavoriteRecipe.fromJson(recipe))
          .toList();
      
      await _cacheData(_CACHE_FAVORITE_RECIPES, jsonEncode(response));
      
      return recipes;
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
      
      await _clearCache(_CACHE_FAVORITE_RECIPES);
    } catch (e) {
      throw Exception('Failed to add favorite recipe: $e');
    }
  }

  static Future<void> removeFavoriteRecipe(int recipeId) async {
    ensureUserAuthenticated();

    try {
      await _supabase.from('favorite_recipes').delete().eq('id', recipeId);
      await _clearCache(_CACHE_FAVORITE_RECIPES);
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
              'item': entry.value,
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

  static Map<String, String> parseGroceryItem(String itemText) {
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

  static String formatGroceryItem(String name, String quantity) {
    if (quantity.isNotEmpty) {
      return '$quantity x $name';
    } else {
      return name;
    }
  }

  static Future<void> addToGroceryList(String item, {String? quantity}) async {
    ensureUserAuthenticated();

    try {
      final currentItems = await getGroceryList();
      final newOrderIndex = currentItems.length;
      
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

  static Future<Map<String, dynamic>> addRecipeToShoppingList(
    String recipeName,
    String ingredients,
  ) async {
    ensureUserAuthenticated();

    try {
      final currentItems = await getGroceryList();
      final currentItemNames = currentItems.map((item) {
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
  // SOCIAL FEATURES - FRIENDS (CACHED)
  // ==================================================

  static Future<List<Map<String, dynamic>>> getFriends() async {
    ensureUserAuthenticated();
    
    try {
      final cacheKey = '$_CACHE_FRIENDS$currentUserId';
      final cached = await _getCachedData(cacheKey);
      
      if (cached != null) {
        final List<dynamic> decoded = jsonDecode(cached);
        return List<Map<String, dynamic>>.from(decoded);
      }
      
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
      
      await _cacheData(cacheKey, jsonEncode(friends));
      
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
      
      await _clearCache('$_CACHE_FRIENDS$currentUserId');
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
      
      await _clearCache('$_CACHE_FRIENDS$currentUserId');
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
  // MESSAGING (SMART CACHING - OLD MESSAGES CACHED)
  // ==================================================

  static Future<List<Map<String, dynamic>>> getMessages(String friendId, {bool forceRefresh = false}) async {
    ensureUserAuthenticated();
    
    try {
      final cacheKey = '$_CACHE_MESSAGES${currentUserId}_$friendId';
      final lastTimeKey = '$_CACHE_LAST_MESSAGE_TIME${currentUserId}_$friendId';
      
      if (!forceRefresh) {
        final cached = await _getCachedData(cacheKey);
        final lastFetchTime = await _getCachedData(lastTimeKey);
        
        if (cached != null && lastFetchTime != null) {
          final List<dynamic> cachedList = jsonDecode(cached);
          final cachedMessages = List<Map<String, dynamic>>.from(cachedList);
          
          final newMessages = await _supabase
              .from('messages')
              .select('*')
              .or('and(sender.eq.$currentUserId,receiver.eq.$friendId),and(sender.eq.$friendId,receiver.eq.$currentUserId)')
              .gt('created_at', lastFetchTime)
              .order('created_at');
          
          final newMessagesList = List<Map<String, dynamic>>.from(newMessages);
          
          if (newMessagesList.isNotEmpty) {
            final combined = [...cachedMessages, ...newMessagesList];
            
            await _cacheData(cacheKey, jsonEncode(combined));
            await _cacheData(lastTimeKey, DateTime.now().toIso8601String());
            
            return combined;
          }
          
          return cachedMessages;
        }
      }
      
      final response = await _supabase
          .from('messages')
          .select('*')
          .or('and(sender.eq.$currentUserId,receiver.eq.$friendId),and(sender.eq.$friendId,receiver.eq.$currentUserId)')
          .order('created_at');

      final messages = List<Map<String, dynamic>>.from(response);
      
      await _cacheData(cacheKey, jsonEncode(messages));
      await _cacheData(lastTimeKey, DateTime.now().toIso8601String());
      
      return messages;
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
      
      await _clearCache('$_CACHE_MESSAGES${currentUserId}_$receiverId');
      await _clearCache('$_CACHE_LAST_MESSAGE_TIME${currentUserId}_$receiverId');
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
  // USER SEARCH (Always fetch fresh)
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
  }
}