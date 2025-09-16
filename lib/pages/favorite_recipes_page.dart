import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/favorite_recipe.dart';

class FavoriteRecipesPage extends StatefulWidget {
  final List<FavoriteRecipe> favoriteRecipes; // <-- change type

  const FavoriteRecipesPage({
    Key? key,
    required this.favoriteRecipes,
  }) : super(key: key);

  @override
  _FavoriteRecipesPageState createState() => _FavoriteRecipesPageState();
}

class _FavoriteRecipesPageState extends State<FavoriteRecipesPage> {
  List<String> _favoriteRecipes = [];

  @override
  void initState() {
    super.initState();
    _favoriteRecipes = List.from(widget.favoriteRecipes);
    _loadFavoriteRecipes();
  }

  Future<void> _loadFavoriteRecipes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _favoriteRecipes = prefs.getStringList('favorite_recipes') ?? [];
      });
    } catch (e) {
      debugPrint('Error loading favorite recipes: $e');
    }
  }

  Future<void> _removeFavoriteRecipe(String recipeTitle) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _favoriteRecipes.remove(recipeTitle);
      });
      await prefs.setStringList('favorite_recipes', _favoriteRecipes);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Removed "$recipeTitle" from favorites'),
          backgroundColor: Colors.orange,
          action: SnackBarAction(
            label: 'UNDO',
            textColor: Colors.white,
            onPressed: () => _undoRemoveFavorite(recipeTitle),
          ),
        ),
      );
    } catch (e) {
      debugPrint('Error removing favorite recipe: $e');
    }
  }

  Future<void> _undoRemoveFavorite(String recipeTitle) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _favoriteRecipes.add(recipeTitle);
      });
      await prefs.setStringList('favorite_recipes', _favoriteRecipes);
    } catch (e) {
      debugPrint('Error undoing favorite removal: $e');
    }
  }

  void _showRecipeDetails(String recipeTitle) {
    // This would need to be expanded based on how you store recipe details
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(recipeTitle),
        content: Text('Recipe details would be shown here.\n\nThis requires expanding your favorite recipe storage to include ingredients and instructions.'),
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
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _loadFavoriteRecipes,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _favoriteRecipes.isEmpty
          ? _buildEmptyState()
          : RefreshIndicator(
              onRefresh: _loadFavoriteRecipes,
              child: ListView.builder(
                padding: EdgeInsets.all(16),
                itemCount: _favoriteRecipes.length,
                itemBuilder: (context, index) {
                  final recipeTitle = _favoriteRecipes[index];
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
                        recipeTitle,
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
                            _showRecipeDetails(recipeTitle);
                          } else if (value == 'remove') {
                            _removeFavoriteRecipe(recipeTitle);
                          }
                        },
                      ),
                      onTap: () => _showRecipeDetails(recipeTitle),
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
                Navigator.pop(context);
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