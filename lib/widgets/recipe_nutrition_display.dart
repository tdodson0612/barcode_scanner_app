// lib/widgets/recipe_nutrition_display.dart - UPDATED: Added Macros section
import 'package:flutter/material.dart';
import 'package:liver_wise/services/recipe_nutrition_service.dart';
import 'package:liver_wise/liverhealthbar.dart';

class RecipeNutritionDisplay extends StatelessWidget {
  final RecipeNutrition nutrition;

  const RecipeNutritionDisplay({
    super.key,
    required this.nutrition,
  });

  /// Calculate macronutrient percentages
  Map<String, double> _calculateMacros() {
    // Calories from macros (per gram):
    // - Protein: 4 cal/g
    // - Carbs: 4 cal/g
    // - Fat: 9 cal/g

    final proteinCals = nutrition.protein * 4;
    final carbsCals = nutrition.carbohydrates * 4;
    final fatCals = nutrition.fat * 9;

    final totalMacroCals = proteinCals + carbsCals + fatCals;

    if (totalMacroCals == 0) {
      return {
        'protein': 0.0,
        'carbs': 0.0,
        'fat': 0.0,
      };
    }

    return {
      'protein': (proteinCals / totalMacroCals) * 100,
      'carbs': (carbsCals / totalMacroCals) * 100,
      'fat': (fatCals / totalMacroCals) * 100,
    };
  }

  @override
  Widget build(BuildContext context) {
    final macros = _calculateMacros();
    final hasValidMacros = macros['protein']! > 0 || 
                          macros['carbs']! > 0 || 
                          macros['fat']! > 0;

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Recipe Nutrition Summary",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),

            // Main nutrition values
            _buildRow("Total Calories", "${nutrition.calories.toStringAsFixed(0)} kcal"),
            _buildRow("Total Fat", "${nutrition.fat.toStringAsFixed(1)} g"),
            _buildRow("Total Carbohydrates", "${nutrition.carbohydrates.toStringAsFixed(1)} g"),
            _buildRow("Total Sugars", "${nutrition.sugar.toStringAsFixed(1)} g"),
            _buildRow("Total Protein", "${nutrition.protein.toStringAsFixed(1)} g"),
            _buildRow("Total Sodium", "${nutrition.sodium.toStringAsFixed(0)} mg"),

            // 🔥 NEW: Macros Section
            if (hasValidMacros) ...[
              const SizedBox(height: 20),
              const Divider(thickness: 2),
              const SizedBox(height: 12),
              
              Row(
                children: [
                  Icon(Icons.pie_chart, size: 20, color: Colors.green.shade700),
                  const SizedBox(width: 8),
                  const Text(
                    'Macros:',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Macro bars with percentages
              _buildMacroBar(
                'Protein',
                macros['protein']!,
                Colors.blue,
                '${nutrition.protein.toStringAsFixed(1)}g',
              ),
              const SizedBox(height: 8),
              
              _buildMacroBar(
                'Carbs',
                macros['carbs']!,
                Colors.orange,
                '${nutrition.carbohydrates.toStringAsFixed(1)}g',
              ),
              const SizedBox(height: 8),
              
              _buildMacroBar(
                'Fat',
                macros['fat']!,
                Colors.purple,
                '${nutrition.fat.toStringAsFixed(1)}g',
              ),
            ],

            const SizedBox(height: 20),
            
            // Liver health score
            LiverHealthBar(healthScore: nutrition.liverScore),
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
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMacroBar(String label, double percentage, Color color, String grams) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            Row(
              children: [
                Text(
                  '${percentage.toStringAsFixed(1)}%',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                Text(
                  ' ($grams)',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: percentage / 100,
            minHeight: 8,
            backgroundColor: Colors.grey.shade200,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}