import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/favorite_recipe.dart';
import '../widgets/app_drawer.dart';
import 'dart:convert';

class FavoriteRecipesPage extends StatefulWidget {
  final List<FavoriteRecipe> favoriteRecipes;

  const FavoriteRecipesPage({
    Key? key,
    required this.favoriteRecipes,
  }) : super(key: key);

  @override
  _FavoriteRecipesPageState createState() => _FavoriteRecipesPageState();
}

class _FavoriteRecipesPageState extends State<FavoriteRecipesPage> {
  List<FavoriteRecipe> _favoriteRecipes = [];

  @override
  void initState() {
    super.initState();
    _favoriteRecipes = List.from(widget.favoriteRecipes);
    _loadFavoriteRecipes();
  }

  Future<void> _loadFavoriteRecipes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final favoriteRecipesJson = prefs.getStringList('favorite_recipes_detailed') ?? [];
      
      setState(() {
        _favoriteRecipes = favoriteRecipesJson
            .map((jsonString) {
              try {
                return FavoriteRecipe.fromJson(json.decode(jsonString));
              } catch (e) {
                debugPrint('Error parsing recipe: $e');
                return null;
              }
            })
            .where((recipe) => recipe != null)
            .cast<FavoriteRecipe>()
            .toList();
      });
    } catch (e) {
      debugPrint('Error loading favorite recipes: $e');
    }
  }

  Future<void> _removeFavoriteRecipe(FavoriteRecipe recipe) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _favoriteRecipes.remove(recipe);
      });
      
      // Save updated list
      final favoriteRecipesJson = _favoriteRecipes
          .map((recipe) => json.encode(recipe.toJson()))
          .toList();
      await prefs.setStringList('favorite_recipes_detailed', favoriteRecipesJson);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Removed "${recipe.recipeName}" from favorites'),
          backgroundColor: Colors.orange,
          action: SnackBarAction(
            label: 'UNDO',
            textColor: Colors.white,
            onPressed: () => _undoRemoveFavorite(recipe),
          ),
        ),
      );
    } catch (e) {
      debugPrint('Error removing favorite recipe: $e');
    }
  }

  Future<void> _undoRemoveFavorite(FavoriteRecipe recipe) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _favoriteRecipes.add(recipe);
      });
      
      // Save updated list
      final favoriteRecipesJson = _favoriteRecipes
          .map((recipe) => json.encode(recipe.toJson()))
          .toList();
      await prefs.setStringList('favorite_recipes_detailed', favoriteRecipesJson);
    } catch (e) {
      debugPrint('Error undoing favorite removal: $e');
    }
  }

  void _showRecipeDetails(FavoriteRecipe recipe) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(recipe.recipeName),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (recipe.ingredients.isNotEmpty) ...[
                Text(
                  'Ingredients:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 8),
                Text(recipe.ingredients),
                SizedBox(height: 16),
              ],
              if (recipe.directions.isNotEmpty) ...[
                Text(
                  'Directions:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 8),
                Text(recipe.directions),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Favorite Recipes'),
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
            onPressed: _loadFavoriteRecipes,
            tooltip: 'Refresh',
          ),
        ],
      ),
      drawer: AppDrawer(currentPage: 'favorite_recipes'),
      body: _favoriteRecipes.isEmpty
          ? _buildEmptyState()
          : RefreshIndicator(
              onRefresh: _loadFavoriteRecipes,
              child: ListView.builder(
                padding: EdgeInsets.all(16),
                itemCount: _favoriteRecipes.length,
                itemBuilder: (context, index) {
                  final recipe = _favoriteRecipes[index];
                  return Card(
                    margin: EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.red,
                        child: Icon(
                          Icons.restaurant,
                          color: Colors.white,
                        ),
                      ),
                      title: Text(
                        recipe.recipeName,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: Text('Tap to view recipe details'),
                      trailing: PopupMenuButton(
                        icon: Icon(Icons.more_vert),
                        itemBuilder: (context) => [
                          PopupMenuItem(
                            value: 'view',
                            child: Row(
                              children: [
                                Icon(Icons.visibility, size: 20),
                                SizedBox(width: 8),
                                Text('View Recipe'),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'remove',
                            child: Row(
                              children: [
                                Icon(Icons.delete, size: 20, color: Colors.red),
                                SizedBox(width: 8),
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
                      onTap: () => _showRecipeDetails(recipe),
                    ),
                  );
                },
              ),
            ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.favorite_outline,
              size: 80,
              color: Colors.grey[400],
            ),
            SizedBox(height: 24),
            Text(
              'No Favorite Recipes Yet',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.grey[600],
              ),
            ),
            SizedBox(height: 16),
            Text(
              'When you find recipes you love, save them to favorites for easy access!',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[500],
                height: 1.4,
              ),
            ),
            SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
              },
              icon: Icon(Icons.camera_alt),
              label: Text('Start Scanning Recipes'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}