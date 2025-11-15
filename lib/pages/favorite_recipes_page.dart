// lib/pages/favorite_recipes_page.dart - OPTIMIZED: Better caching with timestamp validation
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/favorite_recipe.dart';
import '../widgets/app_drawer.dart';
import '../services/error_handling_service.dart';
import 'dart:convert';

class FavoriteRecipesPage extends StatefulWidget {
  final List<FavoriteRecipe> favoriteRecipes;

  const FavoriteRecipesPage({
    super.key,
    required this.favoriteRecipes,
  });

  @override
  _FavoriteRecipesPageState createState() => _FavoriteRecipesPageState();
}

class _FavoriteRecipesPageState extends State<FavoriteRecipesPage> {
  List<FavoriteRecipe> _favoriteRecipes = [];
  bool _isLoading = false;

  // Cache configuration - favorites rarely change once loaded
  static const Duration _cacheDuration = Duration(minutes: 10);

  @override
  void initState() {
    super.initState();
    _favoriteRecipes = List.from(widget.favoriteRecipes);
    _loadFavoriteRecipes();
  }

  // ========== CACHING HELPERS ==========

  Future<List<FavoriteRecipe>?> _getCachedFavorites() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Check if we have a cached version with timestamp
      final cachedData = prefs.getString('favorite_recipes_cached');
      if (cachedData != null) {
        final data = json.decode(cachedData);
        final timestamp = data['_cached_at'] as int?;
        
        if (timestamp != null) {
          final age = DateTime.now().millisecondsSinceEpoch - timestamp;
          
          if (age < _cacheDuration.inMilliseconds) {
            // Cache is still valid
            final recipes = (data['recipes'] as List)
                .map((jsonString) {
                  try {
                    return FavoriteRecipe.fromJson(json.decode(jsonString));
                  } catch (e) {
                    return null;
                  }
                })
                .where((recipe) => recipe != null)
                .cast<FavoriteRecipe>()
                .toList();
            
            print('📦 Using cached favorites (${recipes.length} recipes)');
            return recipes;
          }
        }
      }
      
      // Fall back to old format if new format doesn't exist or is stale
      final favoriteRecipesJson = prefs.getStringList('favorite_recipes_detailed') ?? [];
      
      if (favoriteRecipesJson.isEmpty) return null;
      
      final recipes = favoriteRecipesJson
          .map((jsonString) {
            try {
              return FavoriteRecipe.fromJson(json.decode(jsonString));
            } catch (e) {
              return null;
            }
          })
          .where((recipe) => recipe != null)
          .cast<FavoriteRecipe>()
          .toList();
      
      // Migrate to new format with timestamp
      await _cacheFavorites(recipes);
      
      print('📦 Loaded from old cache format and migrated (${recipes.length} recipes)');
      return recipes;
      
    } catch (e) {
      print('Error loading cached favorites: $e');
      return null;
    }
  }

  Future<void> _cacheFavorites(List<FavoriteRecipe> recipes) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Save with timestamp for validation
      final cacheData = {
        'recipes': recipes.map((recipe) => json.encode(recipe.toJson())).toList(),
        '_cached_at': DateTime.now().millisecondsSinceEpoch,
      };
      await prefs.setString('favorite_recipes_cached', json.encode(cacheData));
      
      // Also maintain old format for backwards compatibility
      final favoriteRecipesJson = recipes
          .map((recipe) => json.encode(recipe.toJson()))
          .toList();
      await prefs.setStringList('favorite_recipes_detailed', favoriteRecipesJson);
      
      print('💾 Cached ${recipes.length} favorite recipes');
    } catch (e) {
      print('Error caching favorites: $e');
    }
  }

  Future<void> _invalidateFavoritesCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('favorite_recipes_cached');
      print('🗑️ Invalidated favorites cache');
    } catch (e) {
      print('Error invalidating favorites cache: $e');
    }
  }

  /// Static method to invalidate cache from other pages
  static Future<void> invalidateCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('favorite_recipes_cached');
    } catch (e) {
      print('Error invalidating favorites cache: $e');
    }
  }

  // ========== LOAD FUNCTION WITH CACHING ==========

  Future<void> _loadFavoriteRecipes({bool forceRefresh = false}) async {
    try {
      setState(() => _isLoading = true);
      
      // Try cache first unless force refresh
      if (!forceRefresh) {
        final cachedRecipes = await _getCachedFavorites();
        
        if (cachedRecipes != null) {
          if (mounted) {
            setState(() {
              _favoriteRecipes = cachedRecipes;
              _isLoading = false;
            });
          }
          return;
        }
      }

      // Cache miss or force refresh - load from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final favoriteRecipesJson = prefs.getStringList('favorite_recipes_detailed') ?? [];
      
      final recipes = favoriteRecipesJson
          .map((jsonString) {
            try {
              return FavoriteRecipe.fromJson(json.decode(jsonString));
            } catch (e) {
              return null;
            }
          })
          .where((recipe) => recipe != null)
          .cast<FavoriteRecipe>()
          .toList();
      
      // Cache the loaded recipes
      await _cacheFavorites(recipes);
      
      if (mounted) {
        setState(() {
          _favoriteRecipes = recipes;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        
        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          category: ErrorHandlingService.databaseError,
          showSnackBar: true,
          customMessage: 'Unable to load favorite recipes',
          onRetry: () => _loadFavoriteRecipes(forceRefresh: true),
        );
      }
    }
  }

  Future<void> _removeFavoriteRecipe(FavoriteRecipe recipe) async {
    try {
      // Store removed recipe for undo functionality
      final removedRecipe = recipe;
      final removedIndex = _favoriteRecipes.indexOf(recipe);
      
      setState(() {
        _favoriteRecipes.remove(recipe);
      });
      
      // Invalidate cache and save updated list
      await _invalidateFavoritesCache();
      await _cacheFavorites(_favoriteRecipes);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Removed "${recipe.recipeName}" from favorites'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 4),
            action: SnackBarAction(
              label: 'UNDO',
              textColor: Colors.white,
              onPressed: () => _undoRemoveFavorite(removedRecipe, removedIndex),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          category: ErrorHandlingService.databaseError,
          customMessage: 'Unable to remove recipe from favorites',
        );
      }
    }
  }

  Future<void> _undoRemoveFavorite(FavoriteRecipe recipe, int index) async {
    try {
      setState(() {
        _favoriteRecipes.insert(index, recipe);
      });
      
      // Invalidate cache and save updated list
      await _invalidateFavoritesCache();
      await _cacheFavorites(_favoriteRecipes);
      
      if (mounted) {
        ErrorHandlingService.showSuccess(context, 'Recipe restored to favorites');
      }
    } catch (e) {
      if (mounted) {
        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          category: ErrorHandlingService.databaseError,
          customMessage: 'Unable to restore recipe',
        );
      }
    }
  }

  void _showRecipeDetails(FavoriteRecipe recipe) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.restaurant, color: Colors.red),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                recipe.recipeName,
                style: TextStyle(fontSize: 20),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (recipe.ingredients.isNotEmpty) ...[
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.list_alt, size: 18, color: Colors.orange.shade700),
                          SizedBox(width: 6),
                          Text(
                            'Ingredients',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.orange.shade700,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 8),
                      Text(
                        recipe.ingredients,
                        style: TextStyle(height: 1.4),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 16),
              ],
              if (recipe.directions.isNotEmpty) ...[
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.description, size: 18, color: Colors.blue.shade700),
                          SizedBox(width: 6),
                          Text(
                            'Directions',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade700,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 8),
                      Text(
                        recipe.directions,
                        style: TextStyle(height: 1.4),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: Icon(Icons.close),
            label: Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Favorite Recipes (${_favoriteRecipes.length})'),
        backgroundColor: Colors.red,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: () async {
              try {
                await _loadFavoriteRecipes(forceRefresh: true);
                if (mounted) {
                  ErrorHandlingService.showSuccess(context, 'Recipes refreshed');
                }
              } catch (e) {
                if (mounted) {
                  await ErrorHandlingService.handleError(
                    context: context,
                    error: e,
                    category: ErrorHandlingService.databaseError,
                    showSnackBar: true,
                    customMessage: 'Failed to refresh recipes',
                  );
                }
              }
            },
            tooltip: 'Refresh',
          ),
        ],
      ),
      drawer: AppDrawer(currentPage: 'favorite_recipes'),
      body: _isLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text(
                    'Loading favorite recipes...',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ],
              ),
            )
          : _favoriteRecipes.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: () => _loadFavoriteRecipes(forceRefresh: true),
                  child: ListView.builder(
                    padding: EdgeInsets.all(16),
                    itemCount: _favoriteRecipes.length,
                    itemBuilder: (context, index) {
                      final recipe = _favoriteRecipes[index];
                      return Card(
                        margin: EdgeInsets.only(bottom: 12),
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: InkWell(
                          onTap: () => _showRecipeDetails(recipe),
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: EdgeInsets.all(12),
                            child: Row(
                              children: [
                                Container(
                                  width: 50,
                                  height: 50,
                                  decoration: BoxDecoration(
                                    color: Colors.red.shade50,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    Icons.restaurant,
                                    color: Colors.red,
                                    size: 28,
                                  ),
                                ),
                                SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        recipe.recipeName,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                      SizedBox(height: 4),
                                      Text(
                                        'Tap to view recipe details',
                                        style: TextStyle(
                                          color: Colors.grey.shade600,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                PopupMenuButton<String>(
                                  icon: Icon(Icons.more_vert, color: Colors.grey.shade600),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  itemBuilder: (context) => [
                                    PopupMenuItem(
                                      value: 'view',
                                      child: Row(
                                        children: [
                                          Icon(Icons.visibility, size: 20, color: Colors.blue),
                                          SizedBox(width: 12),
                                          Text('View Recipe'),
                                        ],
                                      ),
                                    ),
                                    PopupMenuItem(
                                      value: 'remove',
                                      child: Row(
                                        children: [
                                          Icon(Icons.delete, size: 20, color: Colors.red),
                                          SizedBox(width: 12),
                                          Text('Remove', style: TextStyle(color: Colors.red)),
                                        ],
                                      ),
                                    ),
                                  ],
                                  onSelected: (value) {
                                    if (value == 'view') {
                                      _showRecipeDetails(recipe);
                                    } else if (value == 'remove') {
                                      _removeFavoriteRecipe(recipe);
                                    }
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.favorite_outline,
                size: 80,
                color: Colors.red.shade300,
              ),
            ),
            SizedBox(height: 24),
            Text(
              'No Favorite Recipes Yet',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade800,
              ),
            ),
            SizedBox(height: 16),
            Text(
              'When you find recipes you love while scanning products, save them here for easy access anytime!',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey.shade600,
                height: 1.5,
              ),
            ),
            SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
              },
              icon: Icon(Icons.camera_alt, size: 22),
              label: Text(
                'Start Scanning Products',
                style: TextStyle(fontSize: 16),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}