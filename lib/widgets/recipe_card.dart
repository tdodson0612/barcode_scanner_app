// lib/widgets/recipe_card.dart
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../models/submitted_recipe.dart';
import '../services/database_service.dart';
import '../services/error_handling_service.dart';
import '../widgets/rating_dialog.dart';

class RecipeCard extends StatefulWidget {
  final SubmittedRecipe recipe;
  final VoidCallback onDelete;
  final VoidCallback onEdit;
  final VoidCallback onRatingChanged;

  const RecipeCard({
    super.key,
    required this.recipe,
    required this.onDelete,
    required this.onEdit,
    required this.onRatingChanged,
  });

  @override
  State<RecipeCard> createState() => _RecipeCardState();
}

class _RecipeCardState extends State<RecipeCard> {
  double _averageRating = 0.0;
  int _ratingCount = 0;
  bool _isLoadingRating = true;
  int? _userRating;

  @override
  void initState() {
    super.initState();
    _loadRating();
  }

  Future<void> _loadRating() async {
    if (!mounted) return;

    // Check if recipe ID is valid
    if (widget.recipe.id == null) {
      if (mounted) {
        setState(() {
          _averageRating = 0.0;
          _ratingCount = 0;
          _isLoadingRating = false;
        });
      }
      return;
    }

    setState(() {
      _isLoadingRating = true;
    });

    try {
      final ratingData = await DatabaseService.getRecipeAverageRating(widget.recipe.id!);
      final userRating = await DatabaseService.getUserRecipeRating(widget.recipe.id!);

      if (mounted) {
        setState(() {
          _averageRating = ratingData['average'] ?? 0.0;
          _ratingCount = ratingData['count'] ?? 0;
          _userRating = userRating;
          _isLoadingRating = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _averageRating = 0.0;
          _ratingCount = 0;
          _isLoadingRating = false;
        });
      }
    }
  }

  Future<void> _deleteRecipe() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Delete Recipe'),
          content: Text(
            'Are you sure you want to delete "${widget.recipe.recipeName}"? This action cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      widget.onDelete();
    }
  }

  Future<void> _shareRecipe() async {
    try {
      final recipeText = DatabaseService.generateShareableRecipeText({
        'recipe_name': widget.recipe.recipeName,
        'ingredients': widget.recipe.ingredients,
        'directions': widget.recipe.directions,
      });

      await Share.share(
        recipeText,
        subject: 'Recipe: ${widget.recipe.recipeName}',
      );
    } catch (e) {
      if (mounted) {
        ErrorHandlingService.showSimpleError(
          context,
          'Unable to share recipe',
        );
      }
    }
  }

  Future<void> _rateRecipe() async {
    // Check if recipe ID is valid
    if (widget.recipe.id == null) {
      if (mounted) {
        ErrorHandlingService.showSimpleError(
          context,
          'Invalid recipe ID',
        );
      }
      return;
    }

    final result = await showDialog<int>(
      context: context,
      builder: (BuildContext context) {
        return RatingDialog(
          recipeId: widget.recipe.id!,
          recipeName: widget.recipe.recipeName,
          currentRating: _userRating,
        );
      },
    );

    if (result != null) {
      await _loadRating();
      widget.onRatingChanged();
    }
  }

  String _getIngredientPreview() {
    final lines = widget.recipe.ingredients
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .toList();

    if (lines.isEmpty) return 'No ingredients listed';
    if (lines.length <= 3) return lines.join('\n');

    return '${lines.take(3).join('\n')}\n...';
  }

  Widget _buildStarRating() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ...List.generate(5, (index) {
          final starValue = index + 1;
          if (starValue <= _averageRating.floor()) {
            return const Icon(Icons.star, size: 16, color: Colors.amber);
          } else if (starValue - 1 < _averageRating && _averageRating < starValue) {
            return const Icon(Icons.star_half, size: 16, color: Colors.amber);
          } else {
            return Icon(Icons.star_border, size: 16, color: Colors.grey.shade400);
          }
        }),
        const SizedBox(width: 4),
        Text(
          _ratingCount > 0 
              ? '$_averageRating ($_ratingCount)' 
              : 'No ratings',
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Recipe Name
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.recipe.recipeName,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (_userRating != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.star, size: 14, color: Colors.blue),
                        const SizedBox(width: 4),
                        Text(
                          'You: $_userRating',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.blue.shade700,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),

            // Rating Display
            if (_isLoadingRating)
              const SizedBox(
                height: 16,
                width: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              _buildStarRating(),

            const SizedBox(height: 12),

            // Ingredients Preview
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.restaurant_menu, size: 16, color: Colors.grey.shade600),
                      const SizedBox(width: 4),
                      Text(
                        'Ingredients:',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _getIngredientPreview(),
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade700,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: widget.onEdit,
                    icon: const Icon(Icons.edit, size: 16),
                    label: const Text('Edit'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.blue,
                      side: const BorderSide(color: Colors.blue),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _shareRecipe,
                    icon: const Icon(Icons.share, size: 16),
                    label: const Text('Share'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.green,
                      side: const BorderSide(color: Colors.green),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _rateRecipe,
                    icon: const Icon(Icons.star, size: 16),
                    label: Text(_userRating != null ? 'Update Rating' : 'Rate'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.amber.shade700,
                      side: BorderSide(color: Colors.amber.shade700),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _deleteRecipe,
                    icon: const Icon(Icons.delete, size: 16),
                    label: const Text('Delete'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}