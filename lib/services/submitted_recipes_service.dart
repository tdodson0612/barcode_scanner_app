// lib/services/submitted_recipes_service.dart
// Handles user-submitted recipes (CRUD + caching)

import 'dart:convert';

import '../models/submitted_recipe.dart';
import '../config/app_config.dart';

import 'auth_service.dart';              // currentUserId + ensureLoggedIn
import 'database_service_core.dart';     // workerQuery + cache


class SubmittedRecipesService {
  static const String _CACHE_KEY = 'cache_submitted_recipes';

  // ==================================================
  // GET USER SUBMITTED RECIPES (Cached)
  // ==================================================
  static Future<List<SubmittedRecipe>> getSubmittedRecipes() async {
    final userId = AuthService.currentUserId;
    if (userId == null) return [];

    try {
      // Try cache
      final cached = await DatabaseServiceCore.getCachedData(_CACHE_KEY);
      if (cached != null) {
        final decoded = jsonDecode(cached) as List;
        return decoded
            .map((json) => SubmittedRecipe.fromJson(json))
            .toList();
      }

      // Fetch from Worker
      final response = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'submitted_recipes',
        columns: ['*'],
        filters: {'user_id': userId},
        orderBy: 'created_at',
        ascending: false,
      );

      final recipes = (response as List)
          .map((r) => SubmittedRecipe.fromJson(r))
          .toList();

      // Cache result
      await DatabaseServiceCore.cacheData(_CACHE_KEY, jsonEncode(response));

      return recipes;
    } catch (e) {
      throw Exception('Failed to load submitted recipes: $e');
    }
  }

  // ==================================================
  // SUBMIT NEW RECIPE
  // ==================================================
  static Future<void> submitRecipe(
    String recipeName,
    String ingredients,
    String directions,
  ) async {
    AuthService.ensureLoggedIn();

    try {
      await DatabaseServiceCore.workerQuery(
        action: 'insert',
        table: 'submitted_recipes',
        data: {
          'user_id': AuthService.currentUserId!,
          'recipe_name': recipeName,
          'ingredients': ingredients,
          'directions': directions,
          'created_at': DateTime.now().toIso8601String(),
        },
      );

      // Clear cache
      await DatabaseServiceCore.clearCache(_CACHE_KEY);

      // XP & achievements handled in xp_service / achievements_service
    } catch (e) {
      throw Exception('Failed to submit recipe: $e');
    }
  }

  // ==================================================
  // UPDATE SUBMITTED RECIPE
  // ==================================================
  static Future<void> updateRecipe({
    required int recipeId,
    required String recipeName,
    required String ingredients,
    required String directions,
  }) async {
    AuthService.ensureLoggedIn();

    try {
      // Check ownership
      final recipeData = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'submitted_recipes',
        columns: ['user_id'],
        filters: {'id': recipeId},
        limit: 1,
      );

      if (recipeData == null || (recipeData as List).isEmpty) {
        throw Exception('Recipe not found');
      }

      if (recipeData[0]['user_id'] != AuthService.currentUserId) {
        throw Exception('You can only edit your own recipes');
      }

      // Update recipe
      await DatabaseServiceCore.workerQuery(
        action: 'update',
        table: 'submitted_recipes',
        filters: {'id': recipeId},
        data: {
          'recipe_name': recipeName,
          'ingredients': ingredients,
          'directions': directions,
          'updated_at': DateTime.now().toIso8601String(),
        },
      );

      await DatabaseServiceCore.clearCache(_CACHE_KEY);
    } catch (e) {
      throw Exception('Failed to update recipe: $e');
    }
  }

  // ==================================================
  // DELETE RECIPE
  // ==================================================
  static Future<void> deleteRecipe(int recipeId) async {
    AuthService.ensureLoggedIn();

    try {
      await DatabaseServiceCore.workerQuery(
        action: 'delete',
        table: 'submitted_recipes',
        filters: {'id': recipeId},
      );

      await DatabaseServiceCore.clearCache(_CACHE_KEY);
    } catch (e) {
      throw Exception('Failed to delete recipe: $e');
    }
  }

  // ==================================================
  // GET SINGLE RECIPE
  // ==================================================
  static Future<Map<String, dynamic>?> getRecipeById(int recipeId) async {
    try {
      final response = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'submitted_recipes',
        columns: ['*'],
        filters: {'id': recipeId},
        limit: 1,
      );

      if (response == null || (response as List).isEmpty) {
        return null;
      }

      return response[0];
    } catch (e) {
      throw Exception('Failed to get recipe: $e');
    }
  }

  // ==================================================
  // SHAREABLE TEXT FORMAT
  // ==================================================
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
}
