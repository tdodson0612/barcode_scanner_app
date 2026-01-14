// lib/pages/nutrition_search_screen.dart
// Updated with filter options: product, brand, ingredient, substitutes

import 'package:flutter/material.dart';
import 'package:liver_wise/models/nutrition_info.dart';
import 'package:liver_wise/services/nutrition_api_service.dart';
import 'package:liver_wise/widgets/nutrition_display.dart';
import 'package:liver_wise/services/error_handling_service.dart';
import 'package:liver_wise/services/search_history_service.dart';
import 'package:liver_wise/liverhealthbar.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../config/app_config.dart';
import '../services/favorite_recipes_service.dart';
import '../models/favorite_recipe.dart';

class Recipe {
  final String title;
  final String description;
  final List<String> ingredients;
  final String instructions;

  Recipe({
    required this.title,
    required this.description,
    required this.ingredients,
    required this.instructions,
  });

  factory Recipe.fromJson(Map<String, dynamic> json) => Recipe(
        title: json['title'] ?? json['name'] ?? '',
        description: json['description'] ?? '',
        ingredients: json['ingredients'] is String
            ? (json['ingredients'] as String)
                .split(',')
                .map((e) => e.trim())
                .toList()
            : List<String>.from(json['ingredients'] ?? []),
        instructions: json['instructions'] ?? json['directions'] ?? '',
      );
}

class NutritionSearchScreen extends StatefulWidget {
  const NutritionSearchScreen({super.key});

  @override
  State<NutritionSearchScreen> createState() => _NutritionSearchScreenState();
}

class _NutritionSearchScreenState extends State<NutritionSearchScreen> {
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = false;
  List<NutritionInfo> _results = [];
  NutritionInfo? _selectedItem;

  List<String> _searchHistory = [];

  // Search filter
  String _searchType = 'product'; // 'product', 'brand', 'ingredient', 'substitute'

  // Recipe suggestions
  List<Recipe> _recipeSuggestions = [];
  bool _isLoadingRecipes = false;
  List<String> _keywordTokens = [];
  Set<String> _selectedKeywords = {};
  int _currentRecipeIndex = 0;
  static const int _recipesPerPage = 2;

  // Favorites
  List<FavoriteRecipe> _favoriteRecipes = [];

  static const String disclaimer =
      "These are average nutritional values and may vary depending on brand or source. "
      "For more accurate details, try scanning the barcode.";

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _loadFavoriteRecipes();
  }

  Future<void> _loadHistory() async {
    final history = await SearchHistoryService.loadHistory();
    setState(() => _searchHistory = history);
  }

  Future<void> _loadFavoriteRecipes() async {
    try {
      final recipes = await FavoriteRecipesService.getFavoriteRecipes();
      if (mounted) {
        setState(() => _favoriteRecipes = recipes);
      }
    } catch (e) {
      print('Error loading favorites: $e');
    }
  }

  bool _isRecipeFavorited(String recipeTitle) {
    return _favoriteRecipes.any((fav) => fav.recipeName == recipeTitle);
  }

  Future<void> _toggleFavoriteRecipe(Recipe recipe) async {
    try {
      final name = recipe.title;
      final ingredients = recipe.ingredients.join(', ');
      final directions = recipe.instructions;

      final existing = await FavoriteRecipesService.findExistingFavorite(recipeName: name);

      if (existing != null) {
        if (existing.id == null) {
          throw Exception('Favorite recipe has no ID — cannot remove');
        }

        await FavoriteRecipesService.removeFavoriteRecipe(existing.id!);

        setState(() {
          _favoriteRecipes.removeWhere((r) => r.recipeName == name);
        });

        if (mounted) {
          ErrorHandlingService.showSuccess(context, 'Removed from favorites');
        }
      } else {
        try {
          final created = await FavoriteRecipesService.addFavoriteRecipe(
            name,
            ingredients,
            directions,
          );

          setState(() => _favoriteRecipes.add(created));

          if (mounted) {
            ErrorHandlingService.showSuccess(context, 'Added to favorites!');
          }
        } catch (e) {
          if (e.toString().contains('already in your favorites')) {
            if (mounted) {
              ErrorHandlingService.showSimpleError(
                context,
                'This recipe is already in your favorites',
              );
            }
            return;
          }
          rethrow;
        }
      }
    } catch (e) {
      if (mounted) {
        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          category: ErrorHandlingService.databaseError,
          customMessage: 'Error saving recipe',
        );
      }
    }
  }

  Future<void> _performSearch() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      ErrorHandlingService.showSimpleError(
        context,
        "Enter a ${_getSearchTypeLabel()} to search.",
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _results = [];
      _selectedItem = null;
      _recipeSuggestions = [];
      _keywordTokens = [];
      _selectedKeywords = {};
    });

    try {
      await SearchHistoryService.addToHistory(query);
      await _loadHistory();

      final items = await NutritionApiService.searchByName(
        query,
        searchType: _searchType,
      );

      if (items.isEmpty) {
        ErrorHandlingService.showSimpleError(
          context,
          "No results found for $_searchType: $query",
        );
      }

      setState(() => _results = items);
    } catch (e) {
      ErrorHandlingService.handleError(
        context: context,
        error: e,
        customMessage: "Error searching for $_searchType.",
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  String _getSearchTypeLabel() {
    switch (_searchType) {
      case 'brand':
        return 'brand name';
      case 'ingredient':
        return 'ingredient';
      case 'substitute':
        return 'food item';
      default:
        return 'food name';
    }
  }

  String _getSearchTypeDescription() {
    switch (_searchType) {
      case 'brand':
        return 'Search by brand (e.g., "Tyson", "Organic Valley")';
      case 'ingredient':
        return 'Search by ingredient (e.g., "beef", "almonds")';
      case 'substitute':
        return 'Find healthier alternatives (e.g., "ground beef" → turkey/chicken)';
      default:
        return 'Search by product name';
    }
  }

  void _selectItem(NutritionInfo item) {
    setState(() {
      _selectedItem = item;
      _recipeSuggestions = [];
      _currentRecipeIndex = 0;
    });
    
    _initKeywordButtonsFromProductName(item.productName);
    _searchRecipesBySelectedKeywords();
    
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        Scrollable.ensureVisible(
          context,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedItem = null;
      _recipeSuggestions = [];
      _keywordTokens = [];
      _selectedKeywords = {};
    });
  }

  void _initKeywordButtonsFromProductName(String productName) {
    final tokens = productName
        .split(RegExp(r'\s+'))
        .map((w) => w.replaceAll(RegExp(r'[^\w]'), ''))
        .where((w) => w.length > 2)
        .toList();

    setState(() {
      _keywordTokens = tokens;
      _selectedKeywords = tokens.toSet();
    });
  }

  void _toggleKeyword(String word) {
    setState(() {
      if (_selectedKeywords.contains(word)) {
        _selectedKeywords.remove(word);
      } else {
        _selectedKeywords.add(word);
      }
    });
  }

  Future<void> _searchRecipesBySelectedKeywords() async {
    if (_selectedKeywords.isEmpty) {
      ErrorHandlingService.showSimpleError(
        context,
        'Please select at least one keyword.',
      );
      return;
    }

    try {
      setState(() {
        _isLoadingRecipes = true;
        _currentRecipeIndex = 0;
      });

      final recipes = await _searchRecipes(_selectedKeywords.toList());

      if (mounted) {
        setState(() => _recipeSuggestions = recipes);
      }

      if (recipes.isEmpty) {
        ErrorHandlingService.showSimpleError(
          context,
          'No recipes found for those ingredients.',
        );
      }
    } catch (e) {
      if (mounted) {
        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          category: ErrorHandlingService.databaseError,
          customMessage: 'Error searching recipes',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingRecipes = false);
      }
    }
  }

  Future<List<Recipe>> _searchRecipes(List<String> keywords) async {
    final cleanKeywords = keywords
        .map((w) => w.trim().toLowerCase())
        .where((w) => w.isNotEmpty)
        .toSet()
        .toList();

    if (cleanKeywords.isEmpty) {
      return [];
    }

    try {
      final response = await http.post(
        Uri.parse(AppConfig.cloudflareWorkerQueryEndpoint),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'search_recipes',
          'keyword': cleanKeywords,
          'limit': 50,
        }),
      );

      if (response.statusCode != 200) {
        return [];
      }

      final data = jsonDecode(response.body);

      if (data is Map<String, dynamic>) {
        final results = data['results'] as List? ?? [];

        if (results.isEmpty) {
          return [];
        }

        final recipes = results
            .map((item) => Recipe.fromJson(item as Map<String, dynamic>))
            .where((r) => r.title.isNotEmpty)
            .toList();

        return recipes;
      }

      return [];
    } catch (e) {
      print('Error searching recipes: $e');
      return [];
    }
  }

  void _loadNextRecipeSuggestions() {
    if (_recipeSuggestions.isEmpty) return;
    
    setState(() {
      _currentRecipeIndex += _recipesPerPage;
      if (_currentRecipeIndex >= _recipeSuggestions.length) {
        _currentRecipeIndex = 0;
      }
    });
  }

  List<Recipe> _getCurrentPageRecipes() {
    if (_recipeSuggestions.isEmpty) return [];
    
    final endIndex = (_currentRecipeIndex + _recipesPerPage).clamp(0, _recipeSuggestions.length);
    
    return _recipeSuggestions.sublist(_currentRecipeIndex, endIndex);
  }

  Widget _buildRecipeCard(Recipe recipe) {
    final isFavorite = _isRecipeFavorited(recipe.title);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ExpansionTile(
        title: Text(
          recipe.title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(
                isFavorite ? Icons.favorite : Icons.favorite_border,
                color: isFavorite ? Colors.red : Colors.grey,
                size: 20,
              ),
              onPressed: () => _toggleFavoriteRecipe(recipe),
            ),
            const Icon(Icons.expand_more),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  recipe.description,
                  style: const TextStyle(fontSize: 14, color: Colors.black87),
                ),
                const SizedBox(height: 8),
                Text(
                  'Ingredients: ${recipe.ingredients.join(', ')}',
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
                const SizedBox(height: 8),
                Text(
                  'Instructions: ${recipe.instructions}',
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
                const SizedBox(height: 12),
                
                ElevatedButton.icon(
                  onPressed: () => _toggleFavoriteRecipe(recipe),
                  icon: Icon(isFavorite ? Icons.favorite : Icons.favorite_border),
                  label: Text(isFavorite ? 'Unfavorite' : 'Favorite'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isFavorite ? Colors.grey : Colors.red,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecipeSuggestions() {
    if (_selectedItem == null) return const SizedBox.shrink();

    final hasKeywords = _keywordTokens.isNotEmpty;
    final hasRecipes = _recipeSuggestions.isNotEmpty;

    if (!hasKeywords && !hasRecipes && !_isLoadingRecipes) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(top: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.shade800,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Recipe Suggestions:',
            style: TextStyle(
              fontSize: 20,
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),

          if (hasKeywords) ...[
            const Text(
              'Select your key search word(s):',
              style: TextStyle(
                fontSize: 14,
                color: Colors.white70,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),

            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _keywordTokens.map((word) {
                final selected = _selectedKeywords.contains(word);
                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => _toggleKeyword(word),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: selected 
                            ? Colors.green 
                            : Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: selected ? Colors.white : Colors.white30,
                          width: 1.5,
                        ),
                      ),
                      child: Text(
                        word,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 14),

            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                onPressed: _isLoadingRecipes ? null : _searchRecipesBySelectedKeywords,
                icon: _isLoadingRecipes
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.search),
                label: Text(_isLoadingRecipes ? 'Searching...' : 'Search Recipes'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                ),
              ),
            ),

            const SizedBox(height: 18),
          ],

          if (_isLoadingRecipes)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(color: Colors.white),
              ),
            )
          else if (hasRecipes) ...[
            const SizedBox(height: 8),
            
            ..._getCurrentPageRecipes().map((r) => _buildRecipeCard(r)),
            
            if (_recipeSuggestions.length > _recipesPerPage) ...[
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Showing ${_currentRecipeIndex + 1}-${(_currentRecipeIndex + _recipesPerPage).clamp(0, _recipeSuggestions.length)} of ${_recipeSuggestions.length} recipes',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.white70,
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: _loadNextRecipeSuggestions,
                    icon: const Icon(Icons.arrow_forward, size: 16),
                    label: const Text('Next'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ] else if (!_isLoadingRecipes && hasKeywords) ...[
            const Text(
              'No recipes found. Try selecting different keywords.',
              style: TextStyle(fontSize: 12, color: Colors.white60),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHistorySection() {
    if (_searchHistory.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Recent Searches",
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _searchHistory.map((term) {
            return ActionChip(
              label: Text(term),
              onPressed: () {
                _searchController.text = term;
                _performSearch();
              },
            );
          }).toList(),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildResultsList() {
    if (_results.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              "Results:",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (_selectedItem != null)
              TextButton.icon(
                onPressed: _clearSelection,
                icon: const Icon(Icons.close, size: 18),
                label: const Text("Clear Selection"),
              ),
          ],
        ),
        const SizedBox(height: 12),
        ..._results.map((item) {
          final isSelected = _selectedItem?.productName == item.productName;
          
          return Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: isSelected
                  ? const BorderSide(color: Colors.green, width: 2)
                  : BorderSide.none,
            ),
            color: isSelected ? Colors.green.shade50 : null,
            child: ListTile(
              title: Text(
                item.productName,
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              subtitle: isSelected
                  ? const Text(
                      "Selected - View details below",
                      style: TextStyle(
                        color: Colors.green,
                        fontSize: 12,
                      ),
                    )
                  : null,
              trailing: Icon(
                isSelected ? Icons.check_circle : Icons.chevron_right,
                color: isSelected ? Colors.green : null,
              ),
              onTap: () => _selectItem(item),
            ),
          );
        }),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Search Nutrition"),
        backgroundColor: Colors.green,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Search Type Dropdown
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.filter_list, color: Colors.green.shade700, size: 20),
                  const SizedBox(width: 8),
                  const Text(
                    'Search by:',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButton<String>(
                      value: _searchType,
                      isExpanded: true,
                      underline: const SizedBox(),
                      items: const [
                        DropdownMenuItem(
                          value: 'product',
                          child: Text('Product Name'),
                        ),
                        DropdownMenuItem(
                          value: 'brand',
                          child: Text('Brand'),
                        ),
                        DropdownMenuItem(
                          value: 'ingredient',
                          child: Text('Ingredient'),
                        ),
                        DropdownMenuItem(
                          value: 'substitute',
                          child: Text('Healthy Substitutes'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(() {
                            _searchType = value;
                            _results = [];
                            _selectedItem = null;
                          });
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // Description text
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: Colors.blue.shade700),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _getSearchTypeDescription(),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blue.shade900,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Search field
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: "Search ${_getSearchTypeLabel()}",
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                prefixIcon: const Icon(Icons.search),
              ),
              onSubmitted: (_) => _performSearch(),
            ),

            const SizedBox(height: 16),

            // Search button
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _performSearch,
                icon: const Icon(Icons.search),
                label: Text(
                  _isLoading ? "Searching..." : "Search",
                  style: const TextStyle(fontSize: 18),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 20),

            if (_isLoading)
              const Center(child: CircularProgressIndicator()),

            if (!_isLoading) _buildHistorySection(),

            if (!_isLoading) _buildResultsList(),

            const SizedBox(height: 20),

            if (_selectedItem != null) ...[
              const Divider(thickness: 2),
              const SizedBox(height: 12),
              const Text(
                "Nutrition Information",
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              
              NutritionDisplay(
                nutrition: _selectedItem!,
                liverScore: LiverHealthCalculator.calculate(
                  fat: _selectedItem!.fat,
                  sodium: _selectedItem!.sodium,
                  sugar: _selectedItem!.sugar,
                  calories: _selectedItem!.calories,
                ),
                disclaimer: disclaimer,
              ),
              
              const SizedBox(height: 16),
              
              LiverHealthBar(
                healthScore: LiverHealthCalculator.calculate(
                  fat: _selectedItem!.fat,
                  sodium: _selectedItem!.sodium,
                  sugar: _selectedItem!.sugar,
                  calories: _selectedItem!.calories,
                ),
              ),
              
              const SizedBox(height: 20),
              
              _buildRecipeSuggestions(),
            ],
          ],
        ),
      ),
    );
  }
}