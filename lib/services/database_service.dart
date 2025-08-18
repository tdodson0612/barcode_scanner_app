import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/favorite_recipe.dart';
import '../models/grocery_item.dart';
import '../models/submitted_recipe.dart';

class DatabaseService {
  static final SupabaseClient _supabase = Supabase.instance.client;

  // Get current user ID
  static String? get currentUserId => _supabase.auth.currentUser?.id;

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

  static Future<void> addFavoriteRecipe(String recipeName, String ingredients, String directions) async {
    if (currentUserId == null) throw Exception('User not logged in');

    await _supabase.from('favorite_recipes').insert({
      'user_id': currentUserId!,
      'recipe_name': recipeName,
      'ingredients': ingredients,
      'directions': directions,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  static Future<void> removeFavoriteRecipe(int recipeId) async {
    await _supabase
        .from('favorite_recipes')
        .delete()
        .eq('id', recipeId);
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
    if (currentUserId == null) throw Exception('User not logged in');

    try {
      // Clear existing items
      await _supabase
          .from('grocery_items')
          .delete()
          .eq('user_id', currentUserId!);

      // Insert new items
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
    if (currentUserId == null) return;

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

  static Future<void> submitRecipe(String recipeName, String ingredients, String directions) async {
    if (currentUserId == null) throw Exception('User not logged in');

    await _supabase.from('submitted_recipes').insert({
      'user_id': currentUserId!,
      'recipe_name': recipeName,
      'ingredients': ingredients,
      'directions': directions,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  static Future<void> deleteSubmittedRecipe(int recipeId) async {
    await _supabase
        .from('submitted_recipes')
        .delete()
        .eq('id', recipeId);
  }

  // ==================================================
  // AUTH HELPER METHODS
  // ==================================================

  static bool get isUserLoggedIn => currentUserId != null;

  static Future<void> signInAnonymously() async {
    if (currentUserId == null) {
      await _supabase.auth.signInAnonymously();
    }
  }
}

// ==================================================
// 3. SQL COMMANDS FOR SUPABASE
// ==================================================

/*
Run these commands in your Supabase SQL Editor:

-- Enable Row Level Security (RLS) and create tables
-- Favorite recipes table
CREATE TABLE favorite_recipes (
    id BIGSERIAL PRIMARY KEY,
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    recipe_name TEXT NOT NULL,
    ingredients TEXT NOT NULL,
    directions TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Enable RLS
ALTER TABLE favorite_recipes ENABLE ROW LEVEL SECURITY;

-- Create policy so users can only access their own data
CREATE POLICY "Users can insert their own favorite recipes" ON favorite_recipes
    FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can view their own favorite recipes" ON favorite_recipes
    FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can delete their own favorite recipes" ON favorite_recipes
    FOR DELETE USING (auth.uid() = user_id);

-- Grocery items table
CREATE TABLE grocery_items (
    id BIGSERIAL PRIMARY KEY,
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    item TEXT NOT NULL,
    order_index INTEGER NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Enable RLS
ALTER TABLE grocery_items ENABLE ROW LEVEL SECURITY;

-- Create policies
CREATE POLICY "Users can manage their own grocery items" ON grocery_items
    FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

-- Submitted recipes table
CREATE TABLE submitted_recipes (
    id BIGSERIAL PRIMARY KEY,
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    recipe_name TEXT NOT NULL,
    ingredients TEXT NOT NULL,
    directions TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Enable RLS
ALTER TABLE submitted_recipes ENABLE ROW LEVEL SECURITY;

-- Create policies
CREATE POLICY "Users can manage their own submitted recipes" ON submitted_recipes
    FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

*/