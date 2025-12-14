// lib/pages/submit_recipe.dart - ENHANCED with Save, Grocery List, and Nutrition buttons
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
  final TextEditingController _ingredientsController = TextEditingController();
  final TextEditingController _directionsController = TextEditingController();

  bool isSubmitting = false;
  bool isLoading = true;
  bool _isSaved = false;

  int _tabIndex = 0;
  Map<String, dynamic> _drafts = {};
  String? _loadedDraftName;

  // 🔥 NEW: Nutrition aggregation state
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
      _ingredientsController.text = widget.initialIngredients!;
    }
    if (widget.productName != null) {
      _nameController.text = '${widget.productName} Recipe';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _ingredientsController.dispose();
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

  // SAVE DRAFT LOCALLY (no database)
  Future<void> _saveRecipe() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => isSubmitting = true);

    try {
      final name = _nameController.text.trim();
      final ing = _ingredientsController.text.trim();
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

  // Add to grocery list unchanged
  Future<void> _addToGroceryList() async {
    if (_ingredientsController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please add ingredients first'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      final ingredients = _ingredientsController.text
          .split(RegExp(r'[,\n]'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();

      int addedCount = 0;
      for (String ingredient in ingredients) {
        final cleaned = ingredient
            .replaceAll(RegExp(r'^[•\-\d]+\.?\s*'), '')
            .replaceAll(
              RegExp(r'^\d+\s+(cup|tsp|tbsp|oz|lb|g|kg|ml|l)\s+'),
              '',
            )
            .trim();

        if (cleaned.isNotEmpty) {
          await GroceryService.addToGroceryList(cleaned);
          addedCount++;
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('Added $addedCount ingredients to grocery list!'),
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

  // SUBMIT RECIPE TO DATABASE (and delete draft if existed)
  Future<void> _submitRecipe() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => isSubmitting = true);

    try {
      DatabaseServiceCore.ensureUserAuthenticated();

      await SubmittedRecipesService.submitRecipe(
        _nameController.text.trim(),
        _ingredientsController.text.trim(),
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
      _ingredientsController.clear();
      _directionsController.clear();

      Navigator.pop(context, true);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error submitting recipe: $e')),
      );
    } finally {
      setState(() => isSubmitting = false);
    }
  }

  // 🔥 NEW: Analyze recipe nutrition using simple name matching (Option A)
  Future<void> _analyzeRecipeNutrition() async {
    final rawText = _ingredientsController.text.trim();
    if (rawText.isEmpty) {
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

      // Split ingredients by line (and commas as backup)
      final lines = rawText
          .split(RegExp(r'[\n]'))
          .expand((line) => line.split(','))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();

      final lowerLines = lines.map((e) => e.toLowerCase()).toList();

      final List<NutritionInfo> matches = [];

      for (final item in saved) {
        final name = item.productName.trim();
        if (name.isEmpty) continue;

        final lowerName = name.toLowerCase();

        final found = lowerLines.any((line) => line.contains(lowerName));
        if (found) {
          // avoid duplicates by productName
          final already = matches.any(
            (m) => m.productName.toLowerCase() == lowerName,
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
              content: Text(
                'No matching saved ingredients found in this recipe yet.',
              ),
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
          category: ErrorHandlingService.apiError,
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
                _ingredientsController.text = draft["ingredients"];
                _directionsController.text = draft["directions"];
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
              Icon(_getIconForField(label),
                  color: Colors.green, size: 20),
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
                borderSide:
                    BorderSide(color: Colors.grey.shade300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide:
                    const BorderSide(color: Colors.green, width: 2),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide:
                    const BorderSide(color: Colors.red, width: 2),
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
            child:
                Image.asset('assets/background.png', fit: BoxFit.cover),
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
                child: _tabIndex == 0
                    ? _buildSubmitForm()
                    : _buildDraftList(),
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
                  Icon(Icons.add_circle_outline,
                      size: 48, color: Colors.green),
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

            _buildTextField(
              controller: _ingredientsController,
              label: 'Ingredients',
              hint: 'List all ingredients needed',
              maxLines: 8,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter the ingredients';
                }
                if (value.trim().length < 10) {
                  return 'Please provide more detailed ingredients';
                }
                return null;
              },
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

            // 🔥 NEW: Recipe Nutrition Section
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
                      const Icon(Icons.analytics,
                          color: Colors.green, size: 22),
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
                    'We will try to match saved ingredients to your ingredient list by name and estimate total nutrition.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 12),

                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed:
                          _isAnalyzingNutrition ? null : _analyzeRecipeNutrition,
                      icon: _isAnalyzingNutrition
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            )
                          : const Icon(Icons.calculate),
                      label: Text(
                        _isAnalyzingNutrition
                            ? 'Analyzing...'
                            : 'Analyze Recipe Nutrition',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green.shade700,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  if (_matchedNutritionIngredients.isNotEmpty) ...[
                    const Text(
                      'Matched Ingredients:',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    ..._matchedNutritionIngredients.map(
                      (n) => Row(
                        children: [
                          const Icon(Icons.check,
                              size: 14, color: Colors.green),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              n.productName,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  if (_recipeNutrition != null)
                    RecipeNutritionDisplay(
                      nutrition: _recipeNutrition!,
                    ),
                ],
              ),
            ),

            const SizedBox(height: 30),

            // 🔥 NEW: Recipe Nutrition Section
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

                    // 🔥 NEW DISCLAIMER
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
                            icon: Icon(
                              _isSaved
                                  ? Icons.check_circle
                                  : Icons.save,
                              size: 20,
                            ),
                            label: Text(
                              _isSaved ? 'Saved!' : 'Save Draft',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _isSaved
                                  ? Colors.green.shade700
                                  : Colors.blue,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SizedBox(
                          height: 54,
                          child: ElevatedButton.icon(
                            onPressed:
                                isSubmitting ? null : _addToGroceryList,
                            icon: const Icon(
                              Icons.add_shopping_cart,
                              size: 20,
                            ),
                            label: const Text(
                              'Grocery List',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.purple,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(8),
                              ),
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
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            )
                          : const Icon(Icons.send, size: 20),
                      label: Text(
                        isSubmitting
                            ? 'Submitting...'
                            : 'Submit to Community',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
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
                                  _ingredientsController
                                      .text.isNotEmpty ||
                                  _directionsController
                                      .text.isNotEmpty) {
                                showDialog(
                                  context: context,
                                  builder: (context) =>
                                      AlertDialog(
                                    title: const Text(
                                        'Discard Recipe?'),
                                    content: const Text(
                                        'Are you sure? All changes will be lost.'),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context),
                                        child: const Text(
                                            'Keep Writing'),
                                      ),
                                      TextButton(
                                        onPressed: () {
                                          Navigator.pop(context);
                                          Navigator.pop(context);
                                        },
                                        child:
                                            const Text('Discard'),
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
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.grey,
                      ),
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
