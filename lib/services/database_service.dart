// lib/services/database_service.dart - UPDATED: Enhanced fuzzy search
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
        'friends_list_visible': true, // Default to visible
      });
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

  // Get current user's profile (needed by profile screen)
  static Future<Map<String, dynamic>?> getCurrentUserProfile() async {
    final userId = currentUserId;
    if (userId == null) return null;
    
    try {
      return await getUserProfile(userId);
    } catch (e) {
      // Return null for current user profile if not found (not an error condition)
      return null;
    }
  }

  // Check username availability
  static Future<bool> isUsernameAvailable(String username) async {
    try {
      final response = await _supabase
          .from('user_profiles')
          .select('id')
          .ilike('username', username)
          .maybeSingle();
      
      return response == null; // null means username is available
    } catch (e) {
      throw Exception('Failed to check username availability: $e');
    }
  }

  // Update profile
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
      throw Exception('Failed to update profile: $e');
    }
  }

  // Set premium status
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
      // If we can't check premium status, default to free
      return false;
    }
  }

  // ==================================================
  // FRIENDS LIST VISIBILITY METHODS
  // ==================================================
  
  /// Get user's friends list for profile display
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

  /// Get friends list visibility setting
  static Future<bool> getFriendsListVisibility() async {
    ensureUserAuthenticated();
    
    try {
      final profile = await getCurrentUserProfile();
      return profile?['friends_list_visible'] ?? true; // Default to visible
    } catch (e) {
      return true; // Default to visible on error
    }
  }

  /// Update friends list visibility setting
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

      // Reset count if it's a new day
      if (lastScanDate != today) {
        await _supabase.from('user_profiles').update({
          'daily_scans_used': 0,
          'last_scan_date': today,
        }).eq('id', userId);
        return 0;
      }

      return profile?['daily_scans_used'] ?? 0;
    } catch (e) {
      // If we can't get scan count, assume 0
      return 0;
    }
  }

  static Future<bool> canPerformScan() async {
    try {
      if (await isPremiumUser()) return true;
      
      final dailyCount = await getDailyScanCount();
      return dailyCount < 3; // Free users get 3 scans per day
    } catch (e) {
      // If we can't check, allow the scan
      return true;
    }
  }

  static Future<void> incrementScanCount() async {
    try {
      if (await isPremiumUser()) return; // Premium users have unlimited scans

      final currentCount = await getDailyScanCount();
      await _supabase.from('user_profiles').update({
        'daily_scans_used': currentCount + 1,
      }).eq('id', currentUserId!);
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
      // If we can't check, assume not favorited
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
      throw Exception('Failed to load grocery list: $e');
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
      throw Exception('Failed to add item to grocery list: $e');
    }
  }

  // Enhanced shopping list methods
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
      throw Exception('Failed to submit contact message: $e');
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

  /// Get pending friend requests (received)
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

  /// Get sent friend requests (outgoing, still pending)
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

  /// Send friend request with better error handling
  static Future<String?> sendFriendRequest(String receiverId) async {
    ensureUserAuthenticated();
    
    // Can't send request to yourself
    if (receiverId == currentUserId) {
      throw Exception('Cannot send friend request to yourself');
    }
    
    try {
      // Check if request already exists (in either direction)
      final existing = await _supabase
          .from('friend_requests')
          .select('id, status, sender, receiver')
          .or('and(sender.eq.$currentUserId,receiver.eq.$receiverId),and(sender.eq.$receiverId,receiver.eq.$currentUserId)')
          .maybeSingle();

      if (existing != null) {
        if (existing['status'] == 'accepted') {
          throw Exception('You are already friends with this user');
        } else if (existing['status'] == 'pending') {
          // Check if it's an incoming request they should accept instead
          if (existing['sender'] == receiverId) {
            throw Exception('This user has already sent you a friend request. Check your pending requests!');
          }
          throw Exception('Friend request already sent');
        }
      }

      // Insert new friend request
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
      // Handle specific Postgres errors
      if (e.code == '23505') {
        // Unique constraint violation
        throw Exception('Friend request already exists');
      }
      throw Exception('Failed to send friend request: ${e.message}');
    } catch (e) {
      throw Exception('Failed to send friend request: $e');
    }
  }

  /// Accept friend request with validation
  static Future<void> acceptFriendRequest(String requestId) async {
    ensureUserAuthenticated();
    
    try {
      // Verify this request is actually for the current user
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

  /// Decline/Cancel friend request
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

  /// Cancel outgoing friend request by request ID (more reliable)
  static Future<void> cancelFriendRequestById(String requestId) async {
    ensureUserAuthenticated();
    
    try {
      // Verify this is the user's own request
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

  /// Cancel outgoing friend request (legacy method - kept for backward compatibility)
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

  /// Remove friend (unfriend)
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

  /// Check friendship status with enhanced info
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
      throw Exception('Failed to load messages: $e');
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
      throw Exception('Failed to send message: $e');
    }
  }

  /// Get chat list (recent conversations)
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
      throw Exception('Failed to load chat list: $e');
    }
  }

  /// Search users with fuzzy matching (first name, last name, username, email)
  static Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    ensureUserAuthenticated();
    
    try {
      final searchQuery = query.trim();
      if (searchQuery.isEmpty) return [];

      // Try RPC call for complex fuzzy search with ranking
      try {
        final response = await _supabase.rpc('search_users_fuzzy', params: {
          'search_query': searchQuery,
          'current_user_id': currentUserId!,
        });

        return List<Map<String, dynamic>>.from(response);
      } catch (rpcError) {
        print('RPC search failed, falling back to basic search: $rpcError');
        
        // Fallback to basic search if RPC fails
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
}