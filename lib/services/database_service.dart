// lib/services/database_service.dart
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

  /// Throws an exception if no user is signed in
  static void ensureUserAuthenticated() {
    if (currentUserId == null) {
      throw Exception('Please sign in to continue');
    }
  }

  static bool get isUserLoggedIn => currentUserId != null;

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
        'username': email.split('@')[0], // Default username from email
      });
    } catch (e) {
      print('Error creating user profile: $e');
      rethrow;
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
      print('Error getting user profile: $e');
      return null;
    }
  }

  // Get current user's profile (needed by profile screen)
  static Future<Map<String, dynamic>?> getCurrentUserProfile() async {
    final userId = currentUserId;
    if (userId == null) return null;
    return await getUserProfile(userId);
  }

  // Check username availability (NEW METHOD)
  static Future<bool> isUsernameAvailable(String username) async {
    try {
      final response = await _supabase
          .from('user_profiles')
          .select('id')
          .ilike('username', username)
          .maybeSingle();
      
      return response == null; // null means username is available
    } catch (e) {
      print('Error checking username availability: $e');
      throw Exception('Failed to check username availability');
    }
  }

  // Update profile (ENHANCED METHOD)
  static Future<void> updateProfile({
    String? username,
    String? email,
    String? firstName,
    String? lastName,
    String? avatarUrl,
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

      await _supabase
          .from('user_profiles')
          .update(updates)
          .eq('id', currentUserId!);
          
    } catch (e) {
      // Check if it's a unique constraint violation
      if (e.toString().contains('duplicate key value') || 
          e.toString().contains('unique constraint')) {
        throw Exception('Username is already taken. Please choose a different username.');
      }
      print('Error updating profile: $e');
      throw Exception('Failed to update profile: $e');
    }
  }

  // Set premium status - FIXED: Remove circular call
  static Future<void> setPremiumStatus(String userId, bool isPremium) async {
    ensureUserAuthenticated();
    
    try {
      await _supabase.from('user_profiles').update({
        'is_premium': isPremium,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', userId);
    } catch (e) {
      print('Error setting premium status: $e');
      rethrow;
    }
  }

  static Future<bool> isPremiumUser() async {
    final userId = AuthService.currentUserId;
    if (userId == null) return false;

    final profile = await getUserProfile(userId);
    return profile?['is_premium'] ?? false;
  }

  // ==================================================
  // SCAN COUNT MANAGEMENT
  // ==================================================
  static Future<int> getDailyScanCount() async {
    final userId = AuthService.currentUserId;
    if (userId == null) return 0;

    final profile = await getUserProfile(userId);
    if (profile == null) return 0;

    final today = DateTime.now().toIso8601String().split('T')[0];
    final lastScanDate = profile['last_scan_date'] ?? '';

    // Reset count if it's a new day
    if (lastScanDate != today) {
      await _supabase.from('user_profiles').update({
        'daily_scans_used': 0,
        'last_scan_date': today,
      }).eq('id', userId);
      return 0;
    }

    return profile['daily_scans_used'] ?? 0;
  }

  static Future<bool> canPerformScan() async {
    if (await isPremiumUser()) return true;
    
    final dailyCount = await getDailyScanCount();
    return dailyCount < 3; // Free users get 3 scans per day
  }

  static Future<void> incrementScanCount() async {
    if (await isPremiumUser()) return; // Premium users have unlimited scans

    final currentCount = await getDailyScanCount();
    await _supabase.from('user_profiles').update({
      'daily_scans_used': currentCount + 1,
    }).eq('id', currentUserId!);
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
          .map((recipe) => FavoriteRecipe.fromJson(recipe))
          .toList();
    } catch (e) {
      print('Error fetching favorite recipes: $e');
      return [];
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
      print('Error adding favorite recipe: $e');
      rethrow;
    }
  }

  static Future<void> removeFavoriteRecipe(int recipeId) async {
    ensureUserAuthenticated();

    try {
      await _supabase.from('favorite_recipes').delete().eq('id', recipeId);
    } catch (e) {
      print('Error removing favorite recipe: $e');
      rethrow;
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
      print('Error checking if recipe is favorited: $e');
      return false;
    }
  }

  // ==================================================
  // GROCERY LIST
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
      print('Error fetching grocery list: $e');
      return [];
    }
  }

  static Future<void> saveGroceryList(List<String> items) async {
    ensureUserAuthenticated();

    try {
      // Delete existing items
      await _supabase
          .from('grocery_items')
          .delete()
          .eq('user_id', currentUserId!);

      // Insert new items if any
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
      print('Error saving grocery list: $e');
      rethrow;
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
      print('Error clearing grocery list: $e');
      rethrow;
    }
  }

  static Future<void> addToGroceryList(String item) async {
    ensureUserAuthenticated();

    try {
      final currentItems = await getGroceryList();
      final newOrderIndex = currentItems.length;

      await _supabase.from('grocery_items').insert({
        'user_id': currentUserId!,
        'item': item,
        'order_index': newOrderIndex,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      print('Error adding to grocery list: $e');
      rethrow;
    }
  }

  // Enhanced shopping list methods from your existing code
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
      final currentItemNames = currentItems.map((item) => item.item).toList();
      final newIngredients = _parseIngredients(ingredients);
      
      final itemsToAdd = <String>[];
      final skippedItems = <String>[];
      
      for (final newItem in newIngredients) {
        bool isDuplicate = false;
        
        for (final existingItem in currentItemNames) {
          if (_areItemsSimilar(newItem, existingItem)) {
            isDuplicate = true;
            skippedItems.add(newItem);
            break;
          }
        }
        
        if (!isDuplicate) {
          bool isDuplicateInNewItems = false;
          for (final addedItem in itemsToAdd) {
            if (_areItemsSimilar(newItem, addedItem)) {
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

      final updatedList = [...currentItemNames, ...itemsToAdd];
      await saveGroceryList(updatedList);

      return {
        'added': itemsToAdd.length,
        'skipped': skippedItems.length,
        'addedItems': itemsToAdd,
        'skippedItems': skippedItems,
        'recipeName': recipeName,
      };
    } catch (e) {
      print('Error adding recipe to shopping list: $e');
      rethrow;
    }
  }

  static Future<int> getShoppingListCount() async {
    final items = await getGroceryList();
    return items.length;
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
      print('Error fetching submitted recipes: $e');
      return [];
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
    } catch (e) {
      print('Error submitting recipe: $e');
      rethrow;
    }
  }

  static Future<void> deleteSubmittedRecipe(int recipeId) async {
    ensureUserAuthenticated();

    try {
      await _supabase.from('submitted_recipes').delete().eq('id', recipeId);
    } catch (e) {
      print('Error deleting submitted recipe: $e');
      rethrow;
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
        'user_id': currentUserId, // Optional: link to user if logged in
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      print('Error submitting contact message: $e');
      rethrow;
    }
  }

  // ==================================================
  // SOCIAL FEATURES - FRIENDS & MESSAGING
  // ==================================================

  /// Fetch friends list (accepted friend requests)
  static Future<List<Map<String, dynamic>>> getFriends() async {
    ensureUserAuthenticated();
    
    try {
      final response = await _supabase
          .from('friend_requests')
          .select('sender:user_profiles!friend_requests_sender_fkey(id, email, username, avatar_url), receiver:user_profiles!friend_requests_receiver_fkey(id, email, username, avatar_url)')
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
      print('Error fetching friends: $e');
      return [];
    }
  }

  /// Get pending friend requests (received)
  static Future<List<Map<String, dynamic>>> getFriendRequests() async {
    ensureUserAuthenticated();
    
    try {
      final response = await _supabase
          .from('friend_requests')
          .select('id, sender:user_profiles!friend_requests_sender_fkey(id, email, username, avatar_url)')
          .eq('receiver', currentUserId!)
          .eq('status', 'pending');

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error fetching friend requests: $e');
      return [];
    }
  }

  /// Send friend request
  static Future<String?> sendFriendRequest(String receiverId) async {
    ensureUserAuthenticated();
    
    try {
      // Check if request already exists
      final existing = await _supabase
          .from('friend_requests')
          .select('id, status')
          .or('and(sender.eq.$currentUserId,receiver.eq.$receiverId),and(sender.eq.$receiverId,receiver.eq.$currentUserId)')
          .maybeSingle();

      if (existing != null) {
        if (existing['status'] == 'accepted') {
          throw Exception('Already friends');
        } else if (existing['status'] == 'pending') {
          throw Exception('Friend request already sent');
        }
      }

      final response = await _supabase
          .from('friend_requests')
          .insert({
            'sender': currentUserId!,
            'receiver': receiverId,
            'status': 'pending',
          })
          .select()
          .single();

      return response['id'];
    } catch (e) {
      print('Error sending friend request: $e');
      rethrow;
    }
  }

  /// Accept friend request
  static Future<void> acceptFriendRequest(String requestId) async {
    ensureUserAuthenticated();
    
    try {
      await _supabase
          .from('friend_requests')
          .update({'status': 'accepted'})
          .eq('id', requestId);
    } catch (e) {
      print('Error accepting friend request: $e');
      rethrow;
    }
  }

  /// Decline/Cancel friend request (deletes completely)
  static Future<void> declineFriendRequest(String requestId) async {
    ensureUserAuthenticated();
    
    try {
      await _supabase
          .from('friend_requests')
          .delete()
          .eq('id', requestId);
    } catch (e) {
      print('Error declining friend request: $e');
      rethrow;
    }
  }

  /// Cancel outgoing friend request
  static Future<void> cancelFriendRequest(String receiverId) async {
    ensureUserAuthenticated();
    
    try {
      await _supabase
          .from('friend_requests')
          .delete()
          .eq('sender', currentUserId!)
          .eq('receiver', receiverId);
    } catch (e) {
      print('Error canceling friend request: $e');
      rethrow;
    }
  }

  /// Check friendship status - ENHANCED for search_users_page compatibility
  static Future<Map<String, dynamic>> checkFriendshipStatus(String userId) async {
    ensureUserAuthenticated();
    
    try {
      final response = await _supabase
          .from('friend_requests')
          .select('id, status, sender, receiver')
          .or('and(sender.eq.$currentUserId,receiver.eq.$userId),and(sender.eq.$userId,receiver.eq.$currentUserId)')
          .maybeSingle();

      if (response == null) {
        return {
          'status': 'none', 
          'requestId': null, 
          'canSendRequest': true,
          'isOutgoing': false,
        };
      }

      final isOutgoing = response['sender'] == currentUserId;
      final status = response['status'];

      return {
        'status': status,
        'requestId': response['id'],
        'isOutgoing': isOutgoing,
        'canSendRequest': status == 'none',
      };
    } catch (e) {
      print('Error checking friendship status: $e');
      return {
        'status': 'error', 
        'requestId': null, 
        'canSendRequest': false,
        'isOutgoing': false,
      };
    }
  }

  /// Get messages between two users
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
      print('Error fetching messages: $e');
      return [];
    }
  }

  /// Send message
  static Future<void> sendMessage(String receiverId, String content) async {
    ensureUserAuthenticated();
    
    try {
      await _supabase.from('messages').insert({
        'sender': currentUserId!,
        'receiver': receiverId,
        'content': content,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      print('Error sending message: $e');
      rethrow;
    }
  }

  /// Get chat list (recent conversations)
  static Future<List<Map<String, dynamic>>> getChatList() async {
    ensureUserAuthenticated();
    
    try {
      // Get latest message with each friend
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

      // Sort by last message time
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
      print('Error fetching chat list: $e');
      return [];
    }
  }

  /// Search users (for adding friends) - ENHANCED for search_users_page compatibility
  static Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    ensureUserAuthenticated();
    
    try {
      final response = await _supabase
          .from('user_profiles')
          .select('id, email, username, avatar_url')
          .or('email.ilike.%$query%,username.ilike.%$query%')
          .neq('id', currentUserId!)
          .limit(50);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error searching users: $e');
      throw Exception('Failed to search users: $e');
    }
  }
}