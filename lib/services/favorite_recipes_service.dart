// lib/services/favorite_recipes_service.dart
// IMPROVED: Better error handling for database constraint issues

import 'dart:convert';
import '../models/favorite_recipe.dart';
import '../config/app_config.dart';
import 'database_service_core.dart';
import 'auth_service.dart';

class FavoriteRecipesService {
  static const String _CACHE_KEY = 'cache_favorite_recipes';

  // --------------------------------------------------
  // GET FAVORITE RECIPES (with caching)
  // --------------------------------------------------
  static Future<List<FavoriteRecipe>> getFavoriteRecipes() async {
    final userId = AuthService.currentUserId;
    if (userId == null) return [];

    try {
      // Try cache first
      final cached = await DatabaseServiceCore.getCachedData(_CACHE_KEY);
      if (cached != null) {
        final list = jsonDecode(cached) as List;
        return list.map((e) => FavoriteRecipe.fromJson(e)).toList();
      }

      // Fetch from Worker
      final response = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'favorite_recipes',
        columns: ['*'],
        filters: {'user_id': userId},
        orderBy: 'created_at',
        ascending: false,
      );

      final recipes = (response as List)
          .map((e) => FavoriteRecipe.fromJson(e))
          .toList();

      // Cache for next time
      await DatabaseServiceCore.cacheData(_CACHE_KEY, jsonEncode(response));

      return recipes;
    } catch (e) {
      throw Exception('Failed to load favorite recipes: $e');
    }
  }

  // --------------------------------------------------
  // ⭐ NEW: CHECK IF RECIPE IS ALREADY FAVORITED (prevents duplicates)
  // --------------------------------------------------
  static Future<FavoriteRecipe?> findExistingFavorite({
    int? recipeId,
    String? recipeName,
  }) async {
    final userId = AuthService.currentUserId;
    if (userId == null) return null;

    try {
      Map<String, dynamic> filters = {'user_id': userId};

      // Prefer searching by recipe_id if available (more reliable)
      if (recipeId != null) {
        filters['recipe_id'] = recipeId;
      } else if (recipeName != null) {
        filters['recipe_name'] = recipeName;
      } else {
        return null;
      }

      final response = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'favorite_recipes',
        columns: ['*'],
        filters: filters,
        limit: 1,
      );

      if (response != null && (response as List).isNotEmpty) {
        return FavoriteRecipe.fromJson(response.first);
      }

      return null;
    } catch (e) {
      print('⚠️ Error checking for existing favorite: $e');
      return null;
    }
  }

  // --------------------------------------------------
  // ADD FAVORITE RECIPE (with duplicate prevention)
  // --------------------------------------------------
  static Future<FavoriteRecipe> addFavoriteRecipe(
    String recipeName,
    String ingredients,
    String directions, {
    int? recipeId, // ⭐ Optional recipe_id from recipe_master
  }) async {
    if (AuthService.currentUserId == null) {
      throw Exception('Please sign in to continue');
    }

    // ⭐ Check for duplicates BEFORE inserting
    final existing = await findExistingFavorite(
      recipeId: recipeId,
      recipeName: recipeName,
    );

    if (existing != null) {
      throw Exception('This recipe is already in your favorites!');
    }

    try {
      final data = <String, dynamic>{
        'user_id': AuthService.currentUserId!,
        'recipe_name': recipeName,
        'ingredients': ingredients,
        'directions': directions,
        'created_at': DateTime.now().toIso8601String(),
      };

      // ⭐ Include recipe_id if available
      if (recipeId != null) {
        data['recipe_id'] = recipeId;
      }

      final response = await DatabaseServiceCore.workerQuery(
        action: 'insert',
        table: 'favorite_recipes',
        data: data,
      );

      // Worker returns list
      final row = (response as List).first;

      // Clear cache to force refresh
      await DatabaseServiceCore.clearCache(_CACHE_KEY);

      return FavoriteRecipe.fromJson(row);
    } catch (e) {
      final errorStr = e.toString().toLowerCase();
      
      // 🔥 IMPROVED: Better error messages for different constraint violations
      if (errorStr.contains('duplicate key') || 
          errorStr.contains('already exists') ||
          errorStr.contains('23505')) {
        
        if (errorStr.contains('user_id_key')) {
          // This means the database has the wrong constraint!
          throw Exception(
            'Database configuration error: Please contact support. '
            '(Only one favorite allowed per user - this should not happen)'
          );
        } else {
          // Normal duplicate - recipe already favorited
          throw Exception('This recipe is already in your favorites!');
        }
      }
      
      // Preserve other error messages
      if (errorStr.contains('already in your favorites')) {
        rethrow;
      }
      
      throw Exception('Failed to add favorite recipe: $e');
    }
  }

  // --------------------------------------------------
  // REMOVE FAVORITE
  // --------------------------------------------------
  static Future<void> removeFavoriteRecipe(int recipeId) async {
    if (AuthService.currentUserId == null) {
      throw Exception('Please sign in to continue');
    }

    try {
      await DatabaseServiceCore.workerQuery(
        action: 'delete',
        table: 'favorite_recipes',
        filters: {'id': recipeId},
      );

      await DatabaseServiceCore.clearCache(_CACHE_KEY);
    } catch (e) {
      throw Exception('Failed to remove favorite recipe: $e');
    }
  }

  // --------------------------------------------------
  // ⭐ IMPROVED: CHECK IF FAVORITED (supports both recipe_id and name)
  // --------------------------------------------------
  static Future<bool> isRecipeFavorited({
    int? recipeId,
    String? recipeName,
  }) async {
    final userId = AuthService.currentUserId;
    if (userId == null) return false;

    try {
      Map<String, dynamic> filters = {'user_id': userId};

      if (recipeId != null) {
        filters['recipe_id'] = recipeId;
      } else if (recipeName != null) {
        filters['recipe_name'] = recipeName;
      } else {
        return false;
      }

      final response = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'favorite_recipes',
        columns: ['id'],
        filters: filters,
        limit: 1,
      );

      return response != null && (response as List).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  // --------------------------------------------------
  // ⭐ NEW: BULK CHECK FAVORITES (efficient for lists)
  // --------------------------------------------------
  static Future<Set<String>> getFavoritedRecipeNames() async {
    final userId = AuthService.currentUserId;
    if (userId == null) return {};

    try {
      final response = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'favorite_recipes',
        columns: ['recipe_name'],
        filters: {'user_id': userId},
      );

      if (response == null) return {};

      return (response as List)
          .map((e) => e['recipe_name'] as String)
          .toSet();
    } catch (e) {
      print('⚠️ Error loading favorited recipe names: $e');
      return {};
    }
  }
}