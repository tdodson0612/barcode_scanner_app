// lib/services/favorite_recipes_service.dart
// Handles all favorite recipe operations (add, remove, list, check)

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
  // ADD FAVORITE RECIPE
  // --------------------------------------------------
  static Future<FavoriteRecipe> addFavoriteRecipe(
    String recipeName,
    String ingredients,
    String directions,
  ) async {
    if (AuthService.currentUserId == null) {
      throw Exception('Please sign in to continue');
    }

    final response = await DatabaseServiceCore.workerQuery(
      action: 'insert',
      table: 'favorite_recipes',
      data: {
        'user_id': AuthService.currentUserId!,
        'recipe_name': recipeName,
        'ingredients': ingredients,
        'directions': directions,
        'created_at': DateTime.now().toIso8601String(),
      },
    );

    // Worker returns list
    final row = (response as List).first;

    await DatabaseServiceCore.clearCache(_CACHE_KEY);

    return FavoriteRecipe.fromJson(row);
  }

  // --------------------------------------------------
  // REMOVE FAVORITE
  // --------------------------------------------------
  static Future<void> removeFavoriteRecipe(int recipeId) async {
    // Replace ensureUserAuthenticated
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
  // CHECK IF FAVORITED
  // --------------------------------------------------
  static Future<bool> isRecipeFavorited(String recipeName) async {
    final userId = AuthService.currentUserId;
    if (userId == null) return false;

    try {
      final response = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'favorite_recipes',
        columns: ['id'],
        filters: {
          'user_id': userId,
          'recipe_name': recipeName,
        },
        limit: 1,
      );

      return response != null && (response as List).isNotEmpty;
    } catch (_) {
      return false;
    }
  }
}
