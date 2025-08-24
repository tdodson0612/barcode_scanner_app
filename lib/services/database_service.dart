import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/favorite_recipe.dart';
import '../models/grocery_item.dart';
import '../models/submitted_recipe.dart';

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
      });
    } catch (e) {
      print('Error creating user profile: $e');
      rethrow;
    }
  }

  static Future<Map<String, dynamic>?> getUserProfile() async {
    if (currentUserId == null) return null;

    try {
      final response = await _supabase
          .from('user_profiles')
          .select()
          .eq('id', currentUserId!)
          .single();
      return response;
    } catch (e) {
      print('Error getting user profile: $e');
      return null;
    }
  }

  static Future<void> setPremiumStatus(bool isPremium) async {
    ensureUserAuthenticated();
    
    await _supabase.from('user_profiles').update({
      'is_premium': isPremium,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', currentUserId!);
  }

  static Future<bool> isPremiumUser() async {
    final profile = await getUserProfile();
    return profile?['is_premium'] ?? false;
  }

  // ==================================================
  // SCAN COUNT MANAGEMENT
  // ==================================================
  static Future<int> getDailyScanCount() async {
    final profile = await getUserProfile();
    if (profile == null) return 0;

    final today = DateTime.now().toIso8601String().split('T')[0];
    final lastScanDate = profile['last_scan_date'] ?? '';

    // Reset count if it's a new day
    if (lastScanDate != today) {
      await _supabase.from('user_profiles').update({
        'daily_scans_used': 0,
        'last_scan_date': today,
      }).eq('id', currentUserId!);
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
}