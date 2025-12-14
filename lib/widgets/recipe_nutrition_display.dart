// lib/widgets/recipe_nutrition_display.dart

import 'package:flutter/material.dart';
import 'package:liver_wise/services/recipe_nutrition_service.dart';
import 'package:liver_wise/liverhealthbar.dart';

class RecipeNutritionDisplay extends StatelessWidget {
  final RecipeNutrition nutrition;

  const RecipeNutritionDisplay({super.key, required this.nutrition});

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
            const Text(
              "Recipe Nutrition Summary",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),

            _buildRow("Total Calories", "${nutrition.calories.toStringAsFixed(0)} kcal"),
            _buildRow("Total Fat", "${nutrition.fat.toStringAsFixed(1)} g"),
            _buildRow("Total Sugar", "${nutrition.sugar.toStringAsFixed(1)} g"),
            _buildRow("Total Sodium", "${nutrition.sodium.toStringAsFixed(0)} mg"),

            const SizedBox(height: 20),
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
          Text(label, style: const TextStyle(fontSize: 14)),
          Text(value, style: const TextStyle(fontSize: 14)),
        ],
      ),
    );
  }
}
