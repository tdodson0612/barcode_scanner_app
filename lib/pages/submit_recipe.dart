// lib/pages/submit_recipe.dart - ENHANCED with structured ingredient rows
import 'package:flutter/material.dart';
import 'package:liver_wise/services/submitted_recipes_service.dart';
import 'package:liver_wise/services/grocery_service.dart';
import '../services/database_service_core.dart';
import '../services/auth_service.dart';
import '../services/error_handling_service.dart';
import 'package:liver_wise/services/local_draft_service.dart';
import 'package:liver_wise/widgets/recipe_nutrition_display.dart';
import 'package:liver_wise/services/recipe_nutrition_service.dart';
import 'package:liver_wise/services/saved_ingredients_service.dart';
import 'package:liver_wise/models/nutrition_info.dart';
import 'dart:convert';

class IngredientRow {
  String quantity;
  String measurement;
  String name;

  IngredientRow({
    this.quantity = '',
    this.measurement = 'cup',
    this.name = '',
  });

  Map<String, dynamic> toJson() => {
    'quantity': quantity,
    'measurement': measurement,
    'name': name,
  };

  factory IngredientRow.fromJson(Map<String, dynamic> json) => IngredientRow(
    quantity: json['quantity'] ?? '',
    measurement: json['measurement'] ?? 'cup',
    name: json['name'] ?? '',
  );

  bool get isEmpty => quantity.isEmpty && name.isEmpty;
  bool get isValid => quantity.isNotEmpty && name.isNotEmpty;
}

class SubmitRecipePage extends StatefulWidget {
  final String? initialIngredients;
  final String? productName;

  const SubmitRecipePage({
    super.key,
    this.initialIngredients,
    this.productName,
  });

  @override
  _SubmitRecipePageState createState() => _SubmitRecipePageState();
}

class _SubmitRecipePageState extends State<SubmitRecipePage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _directionsController = TextEditingController();

  // 🔥 NEW: Structured ingredients
  List<IngredientRow> _ingredients = [IngredientRow()];
  final List<String> _measurements = [
    'cup', 'cups',
    'tbsp', 'tsp',
    'oz', 'lb', 'g', 'kg',
    'ml', 'l',
    'piece', 'pieces',
    'pinch', 'dash',
    'to taste',
  ];

  bool isSubmitting = false;
  bool isLoading = true;
  bool _isSaved = false;

  int _tabIndex = 0;
  Map<String, dynamic> _drafts = {};
  String? _loadedDraftName;

  // Nutrition aggregation state
  List<NutritionInfo> _matchedNutritionIngredients = [];
  RecipeNutrition? _recipeNutrition;
  bool _isAnalyzingNutrition = false;

  @override
  void initState() {
    super.initState();
    _initializeUser();
    _loadDrafts();

    // Prefill data if passed in
    if (widget.initialIngredients != null) {
      _parseInitialIngredients(widget.initialIngredients!);
    }
    if (widget.productName != null) {
      _nameController.text = '${widget.productName} Recipe';
    }
  }

  void _parseInitialIngredients(String ingredients) {
    try {
      // Try to parse as JSON first
      final List<dynamic> parsed = jsonDecode(ingredients);
      _ingredients = parsed.map((e) => IngredientRow.fromJson(e)).toList();
    } catch (e) {
      // If not JSON, parse as plain text (one per line)
      final lines = ingredients.split('\n').where((l) => l.trim().isNotEmpty).toList();
      _ingredients = lines.map((line) {
        return IngredientRow(name: line.trim());
      }).toList();
    }
    
    if (_ingredients.isEmpty) {
      _ingredients = [IngredientRow()];
    }
  }

  String _serializeIngredients() {
    final validIngredients = _ingredients.where((i) => i.isValid).toList();
    return jsonEncode(validIngredients.map((i) => i.toJson()).toList());
  }

  String _ingredientsToPlainText() {
    return _ingredients
        .where((i) => i.isValid)
        .map((i) => '${i.quantity} ${i.measurement} ${i.name}')
        .join('\n');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _directionsController.dispose();
    super.dispose();
  }

  Future<void> _initializeUser() async {
    try {
      DatabaseServiceCore.ensureUserAuthenticated();
      setState(() => isLoading = false);
    } catch (e) {
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  Future<void> _loadDrafts() async {
    final d = await LocalDraftService.getDrafts();
    setState(() => _drafts = d);
  }

  void _addIngredientRow() {
    setState(() {
      _ingredients.add(IngredientRow());
    });
  }

  void _removeIngredientRow(int index) {
    if (_ingredients.length > 1) {
      setState(() {
        _ingredients.removeAt(index);
      });
    }
  }

  // SAVE DRAFT LOCALLY
  Future<void> _saveRecipe() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => isSubmitting = true);

    try {
      final name = _nameController.text.trim();
      final ing = _serializeIngredients();
      final dir = _directionsController.text.trim();

      await LocalDraftService.saveDraft(
        name: name,
        ingredients: ing,
        directions: dir,
      );

      _loadedDraftName = name;
      _isSaved = true;
      await _loadDrafts();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Draft saved locally!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving draft: $e')),
      );
    } finally {
      setState(() => isSubmitting = false);
    }
  }

  // Add to grocery list
  Future<void> _addToGroceryList() async {
    final validIngredients = _ingredients.where((i) => i.isValid).toList();
    
    if (validIngredients.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please add ingredients first'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      int addedCount = 0;
      for (var ingredient in validIngredients) {
        final itemText = '${ingredient.quantity} ${ingredient.measurement} ${ingredient.name}'.trim();
        await GroceryService.addToGroceryList(itemText);
        addedCount++;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Added $addedCount ingredients to grocery list!'),
            backgroundColor: Colors.green,
            action: SnackBarAction(
              label: 'VIEW',
              textColor: Colors.white,
              onPressed: () {
                Navigator.pushNamed(context, '/grocery-list');
              },
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
          customMessage: 'Failed to add ingredients to grocery list',
        );
      }
    }
  }

  // SUBMIT RECIPE TO DATABASE
  Future<void> _submitRecipe() async {
    if (!_formKey.currentState!.validate()) return;

    final validIngredients = _ingredients.where((i) => i.isValid).toList();
    if (validIngredients.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please add at least one ingredient'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => isSubmitting = true);

    try {
      DatabaseServiceCore.ensureUserAuthenticated();

      await SubmittedRecipesService.submitRecipe(
        _nameController.text.trim(),
        _serializeIngredients(),
        _directionsController.text.trim(),
      );

      // delete draft if it came from one
      if (_loadedDraftName != null) {
        await LocalDraftService.deleteDraft(_loadedDraftName!);
        await _loadDrafts();
        _loadedDraftName = null;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Recipe submitted to community successfully!'),
          backgroundColor: Colors.green,
        ),
      );

      _nameController.clear();
      _directionsController.clear();
      setState(() {
        _ingredients = [IngredientRow()];
      });

      Navigator.pop(context, true);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error submitting recipe: $e')),
      );
    } finally {
      setState(() => isSubmitting = false);
    }
  }

  // Analyze recipe nutrition
  Future<void> _analyzeRecipeNutrition() async {
    final validIngredients = _ingredients.where((i) => i.isValid).toList();
    
    if (validIngredients.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add ingredients first to analyze nutrition.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isAnalyzingNutrition = true;
      _matchedNutritionIngredients = [];
      _recipeNutrition = null;
    });

    try {
      final saved = await SavedIngredientsService.loadSavedIngredients();
      if (saved.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No saved ingredients found yet.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      final List<NutritionInfo> matches = [];

      for (var ingredient in validIngredients) {
        final name = ingredient.name.trim().toLowerCase();
        
        final found = saved.where((item) {
          final itemName = item.productName.toLowerCase();
          return itemName.contains(name) || name.contains(itemName);
        }).toList();

        for (var item in found) {
          final already = matches.any(
            (m) => m.productName.toLowerCase() == item.productName.toLowerCase(),
          );
          if (!already) {
            matches.add(item);
          }
        }
      }

      if (matches.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No matching saved ingredients found in this recipe yet.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      final totals = RecipeNutritionService.calculateTotals(matches);

      if (mounted) {
        setState(() {
          _matchedNutritionIngredients = matches;
          _recipeNutrition = totals;
        });
      }
    } catch (e) {
      if (mounted) {
        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          customMessage: 'Error analyzing recipe nutrition',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isAnalyzingNutrition = false);
      }
    }
  }

  // UI BUILDERS -----------------------------------------------------

  Widget _buildTabButton(String title, int index) {
    final selected = _tabIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _tabIndex = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          color: selected ? Colors.green : Colors.grey.shade300,
          child: Center(
            child: Text(
              title,
              style: TextStyle(
                color: selected ? Colors.white : Colors.black87,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDraftList() {
    if (_drafts.isEmpty) {
      return const Center(
        child: Text("No drafts saved."),
      );
    }

    return ListView(
      children: _drafts.keys.map((name) {
        final draft = _drafts[name];
        return Card(
          margin: const EdgeInsets.all(10),
          child: ListTile(
            title: Text(name),
            subtitle: Text("Last updated: ${draft["updated_at"]}"),
            trailing: IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: () async {
                await LocalDraftService.deleteDraft(name);
                await _loadDrafts();
              },
            ),
            onTap: () {
              setState(() {
                _nameController.text = draft["name"];
                _directionsController.text = draft["directions"];
                
                // Parse ingredients
                try {
                  final List<dynamic> parsed = jsonDecode(draft["ingredients"]);
                  _ingredients = parsed.map((e) => IngredientRow.fromJson(e)).toList();
                } catch (e) {
                  _ingredients = [IngredientRow(name: draft["ingredients"])];
                }
                
                if (_ingredients.isEmpty) {
                  _ingredients = [IngredientRow()];
                }
                
                _loadedDraftName = name;
                _isSaved = true;
                _tabIndex = 0;
              });
            },
          ),
        );
      }).toList(),
    );
  }

  Widget _buildIngredientRow(int index) {
    final ingredient = _ingredients[index];
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: [
          // Quantity field
          Expanded(
            flex: 2,
            child: TextFormField(
              initialValue: ingredient.quantity,
              decoration: InputDecoration(
                labelText: 'Qty',
                hintText: '1',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                isDense: true,
              ),
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              onChanged: (value) {
                ingredient.quantity = value;
              },
            ),
          ),
          const SizedBox(width: 8),
          
          // Measurement dropdown
          Expanded(
            flex: 2,
            child: DropdownButtonFormField<String>(
              value: ingredient.measurement,
              decoration: InputDecoration(
                labelText: 'Unit',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                isDense: true,
              ),
              items: _measurements.map((m) {
                return DropdownMenuItem(value: m, child: Text(m));
              }).toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    ingredient.measurement = value;
                  });
                }
              },
            ),
          ),
          const SizedBox(width: 8),
          
          // Ingredient name field
          Expanded(
            flex: 4,
            child: TextFormField(
              initialValue: ingredient.name,
              decoration: InputDecoration(
                labelText: 'Ingredient',
                hintText: 'flour',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                isDense: true,
              ),
              onChanged: (value) {
                ingredient.name = value;
              },
              validator: (value) {
                if (ingredient.quantity.isNotEmpty && (value == null || value.trim().isEmpty)) {
                  return 'Required';
                }
                return null;
              },
            ),
          ),
          const SizedBox(width: 8),
          
          // Delete button
          IconButton(
            icon: const Icon(Icons.remove_circle, color: Colors.red),
            onPressed: _ingredients.length > 1 ? () => _removeIngredientRow(index) : null,
            tooltip: 'Remove',
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    int maxLines = 1,
    required String? Function(String?) validator,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha((0.9 * 255).toInt()),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_getIconForField(label), color: Colors.green, size: 20),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: controller,
            maxLines: maxLines,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(color: Colors.grey.shade600),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Colors.green, width: 2),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Colors.red, width: 2),
              ),
              contentPadding: const EdgeInsets.all(12),
              filled: true,
              fillColor: Colors.grey.shade50,
            ),
            validator: validator,
          ),
        ],
      ),
    );
  }

  IconData _getIconForField(String label) {
    switch (label) {
      case 'Recipe Name':
        return Icons.restaurant;
      case 'Ingredients':
        return Icons.list_alt;
      case 'Directions':
        return Icons.description;
      default:
        return Icons.edit;
    }
  }

  // MAIN BUILD -----------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Submit Your Recipe'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset('assets/background.png', fit: BoxFit.cover),
          ),
          Column(
            children: [
              Container(
                color: Colors.white.withOpacity(0.9),
                child: Row(
                  children: [
                    _buildTabButton("Submit Recipe", 0),
                    _buildTabButton("Saved Drafts", 1),
                  ],
                ),
              ),
              Expanded(
                child: _tabIndex == 0 ? _buildSubmitForm() : _buildDraftList(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSubmitForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha((0.9 * 255).toInt()),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  Icon(Icons.add_circle_outline, size: 48, color: Colors.green),
                  const SizedBox(height: 12),
                  const Text(
                    'Share Your Recipe',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            _buildTextField(
              controller: _nameController,
              label: 'Recipe Name',
              hint: 'Enter the name of your recipe',
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter a recipe name';
                }
                if (value.trim().length < 3) {
                  return 'Recipe name must be at least 3 characters';
                }
                return null;
              },
            ),

            const SizedBox(height: 20),

            // 🔥 NEW: Structured Ingredients Section
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha((0.9 * 255).toInt()),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.list_alt, color: Colors.green, size: 20),
                      const SizedBox(width: 8),
                      const Text(
                        'Ingredients',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  // Ingredient rows
                  ..._ingredients.asMap().entries.map((entry) {
                    return _buildIngredientRow(entry.key);
                  }).toList(),
                  
                  // Add ingredient button
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _addIngredientRow,
                      icon: const Icon(Icons.add_circle_outline),
                      label: const Text('Add Ingredient'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.green,
                        side: const BorderSide(color: Colors.green),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            _buildTextField(
              controller: _directionsController,
              label: 'Directions',
              hint: 'Provide step-by-step instructions',
              maxLines: 10,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter the directions';
                }
                if (value.trim().length < 20) {
                  return 'Please provide more detailed directions';
                }
                return null;
              },
            ),

            const SizedBox(height: 20),

            // Recipe Nutrition Section
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha((0.9 * 255).toInt()),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.analytics, color: Colors.green, size: 22),
                      const SizedBox(width: 8),
                      const Text(
                        'Recipe Nutrition (Saved Ingredients)',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 8),
                  const Text(
                    'We will try to match saved ingredients to your list and estimate total nutrition.',
                    style: TextStyle(fontSize: 12, color: Colors.black87),
                  ),
                  const SizedBox(height: 12),

                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: _isAnalyzingNutrition ? null : _analyzeRecipeNutrition,
                      icon: _isAnalyzingNutrition
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Icon(Icons.calculate),
                      label: Text(
                        _isAnalyzingNutrition ? 'Analyzing...' : 'Analyze Recipe Nutrition',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green.shade700,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Matched ingredient list
                  if (_matchedNutritionIngredients.isNotEmpty) ...[
                    const Text(
                      'Matched Ingredients:',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    ..._matchedNutritionIngredients.map(
                      (n) => Row(
                        children: [
                          const Icon(Icons.check, size: 14, color: Colors.green),
                          const SizedBox(width: 4),
                          Expanded(child: Text(n.productName, style: const TextStyle(fontSize: 13))),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // FINAL TOTALS + DISCLAIMER
                  if (_recipeNutrition != null) ...[
                    RecipeNutritionDisplay(nutrition: _recipeNutrition!),
                    const SizedBox(height: 8),

                    const Text(
                      "🛈 This is an estimate based on your saved ingredients. "
                      "Accuracy depends on the items you have saved.",
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 20),

            // BUTTONS SECTION
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha((0.9 * 255).toInt()),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 54,
                          child: ElevatedButton.icon(
                            onPressed: isSubmitting ? null : _saveRecipe,
                            icon: Icon(_isSaved ? Icons.check_circle : Icons.save, size: 20),
                            label: Text(
                              _isSaved ? 'Saved!' : 'Save Draft',
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _isSaved ? Colors.green.shade700 : Colors.blue,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SizedBox(
                          height: 54,
                          child: ElevatedButton.icon(
                            onPressed: isSubmitting ? null : _addToGroceryList,
                            icon: const Icon(Icons.add_shopping_cart, size: 20),
                            label: const Text(
                              'Grocery List',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.purple,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton.icon(
                      onPressed: isSubmitting ? null : _submitRecipe,
                      icon: isSubmitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Icon(Icons.send, size: 20),
                      label: Text(
                        isSubmitting ? 'Submitting...' : 'Submit to Community',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: TextButton.icon(
                      onPressed: isSubmitting
                          ? null
                          : () {
                              if (_nameController.text.isNotEmpty ||
                                  _ingredients.any((i) => i.isValid) ||
                                  _directionsController.text.isNotEmpty) {
                                showDialog(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text('Discard Recipe?'),
                                    content: const Text('Are you sure? All changes will be lost.'),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(context),
                                        child: const Text('Keep Writing'),
                                      ),
                                      TextButton(
                                        onPressed: () {
                                          Navigator.pop(context);
                                          Navigator.pop(context);
                                        },
                                        child: const Text('Discard'),
                                      ),
                                    ],
                                  ),
                                );
                              } else {
                                Navigator.pop(context);
                              }
                            },
                      icon: const Icon(Icons.cancel_outlined),
                      label: const Text('Cancel'),
                      style: TextButton.styleFrom(foregroundColor: Colors.grey),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}