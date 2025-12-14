import 'package:flutter/material.dart';
import 'package:liver_wise/models/nutrition_info.dart';
import 'package:liver_wise/liverhealthbar.dart';
import 'package:liver_wise/services/navigation_helper.dart';
import 'package:liver_wise/services/saved_ingredients_service.dart';

class NutritionDisplay extends StatelessWidget {
  final NutritionInfo nutrition;
  final int liverScore;
  final String? disclaimer;

  const NutritionDisplay({
    super.key,
    required this.nutrition,
    required this.liverScore,
    this.disclaimer,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // PRODUCT NAME
            Text(
              nutrition.productName,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),

            const SizedBox(height: 12),

            // NUTRITION ROWS
            _buildRow("Calories", "${nutrition.calories.toStringAsFixed(0)} kcal"),
            _buildRow("Fat", "${nutrition.fat.toStringAsFixed(1)} g"),
            _buildRow("Sugar", "${nutrition.sugar.toStringAsFixed(1)} g"),
            _buildRow("Sodium", "${nutrition.sodium.toStringAsFixed(0)} mg"),

            const SizedBox(height: 12),

            // LIVER HEALTH SCORE
            LiverHealthBar(healthScore: liverScore),

            const SizedBox(height: 16),

            // SAVE INGREDIENT BUTTON
            FutureBuilder<bool>(
              future: SavedIngredientsService.isSaved(nutrition.productName),
              builder: (context, snapshot) {
                final isSaved = snapshot.data ?? false;

                return SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      if (!isSaved) {
                        await SavedIngredientsService.saveIngredient(nutrition);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Ingredient saved!")),
                        );
                      } else {
                        await SavedIngredientsService.removeIngredient(
                            nutrition.productName);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Ingredient removed.")),
                        );
                      }

                      // Force widget to rebuild state
                      (context as Element).markNeedsBuild();
                    },
                    icon: Icon(isSaved ? Icons.bookmark : Icons.bookmark_border),
                    label: Text(
                      isSaved ? "Saved Ingredient" : "Save Ingredient",
                      style: const TextStyle(fontSize: 16),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                );
              },
            ),

            const SizedBox(height: 12),

            // USE IN RECIPE BUTTON
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: () {
                  NavigationHelper.openSubmitRecipeWithIngredient(
                    context,
                    nutrition.productName,
                  );
                },
                icon: const Icon(Icons.restaurant_menu),
                label: const Text(
                  "Use Ingredient in Recipe",
                  style: TextStyle(fontSize: 16),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // DISCLAIMER
            if (disclaimer != null)
              Text(
                disclaimer!,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              )),
          Text(value,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.black87,
                fontWeight: FontWeight.w400,
              )),
        ],
      ),
    );
  }
}
