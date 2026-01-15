// lib/widgets/nutrition_display.dart - UPDATED: Added Macros section
import 'package:flutter/material.dart';
import '../models/nutrition_info.dart';

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

  /// Calculate macronutrient percentages
  Map<String, double> _calculateMacros() {
    // Calories from macros (per gram):
    // - Protein: 4 cal/g
    // - Carbs: 4 cal/g
    // - Fat: 9 cal/g

    final protein = nutrition.protein ?? 0.0;
    final carbs = nutrition.carbs ?? 0.0;
    final fat = nutrition.fat ?? 0.0;

    final proteinCals = protein * 4;
    final carbsCals = carbs * 4;
    final fatCals = fat * 9;

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

    // Local nullable-safe values
    final calories = nutrition.calories ?? 0.0;
    final fat = nutrition.fat ?? 0.0;
    final saturatedFat = nutrition.saturatedFat ?? 0.0;
    final carbs = nutrition.carbs ?? 0.0;
    final sugar = nutrition.sugar ?? 0.0;
    final fiber = nutrition.fiber ?? 0.0;
    final protein = nutrition.protein ?? 0.0;
    final sodium = nutrition.sodium ?? 0.0;

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
            // Product name header
            Text(
              nutrition.productName,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),

            // Main nutrition info
            _buildNutritionRow('Energy', '${calories.toStringAsFixed(0)} kcal'),
            const Divider(),
            _buildNutritionRow('Fat', '${fat.toStringAsFixed(1)} g'),
            _buildNutritionRow('  Saturated Fat', '${saturatedFat.toStringAsFixed(1)} g', indent: true),
            const Divider(),
            _buildNutritionRow('Carbs', '${carbs.toStringAsFixed(1)} g'),
            _buildNutritionRow('  Sugars', '${sugar.toStringAsFixed(1)} g', indent: true),
            const Divider(),
            _buildNutritionRow('Fiber', '${fiber.toStringAsFixed(1)} g'),
            _buildNutritionRow('Protein', '${protein.toStringAsFixed(1)} g'),
            _buildNutritionRow('Sodium', '${sodium.toStringAsFixed(0)} mg'),

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
                '${protein.toStringAsFixed(1)}g',
              ),
              const SizedBox(height: 8),

              _buildMacroBar(
                'Carbs',
                macros['carbs']!,
                Colors.orange,
                '${carbs.toStringAsFixed(1)}g',
              ),
              const SizedBox(height: 8),

              _buildMacroBar(
                'Fat',
                macros['fat']!,
                Colors.purple,
                '${fat.toStringAsFixed(1)}g',
              ),
            ],

            // Disclaimer if provided
            if (disclaimer != null && disclaimer!.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, size: 16, color: Colors.blue.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        disclaimer!,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.blue.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildNutritionRow(String label, String value, {bool indent = false}) {
    return Padding(
      padding: EdgeInsets.only(
        left: indent ? 16 : 0,
        top: 4,
        bottom: 4,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: indent ? FontWeight.normal : FontWeight.w600,
              color: indent ? Colors.grey.shade700 : Colors.black87,
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