// lib/services/recipe_nutrition_service.dart - UPDATED: Added macronutrient tracking
import 'package:liver_wise/models/nutrition_info.dart';
import 'package:liver_wise/liverhealthbar.dart';

class RecipeNutrition {
  final double calories;
  final double fat;
  final double sugar;
  final double sodium;
  final double protein;        // 🔥 NEW
  final double carbohydrates;  // 🔥 NEW
  final double fiber;          // 🔥 NEW
  final int liverScore;

  RecipeNutrition({
    required this.calories,
    required this.fat,
    required this.sugar,
    required this.sodium,
    required this.protein,
    required this.carbohydrates,
    required this.fiber,
    required this.liverScore,
  });

  /// Calculate macronutrient percentages
  Map<String, double> get macroPercentages {
    // Calories from macros (per gram):
    // - Protein: 4 cal/g
    // - Carbs: 4 cal/g
    // - Fat: 9 cal/g

    final proteinCals = protein * 4;
    final carbsCals = carbohydrates * 4;
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
}

class RecipeNutritionService {
  /// Combine multiple ingredients into one nutrition summary
  static RecipeNutrition calculateTotals(List<NutritionInfo> items) {
    double totalCalories = 0;
    double totalFat = 0;
    double totalSugar = 0;
    double totalSodium = 0;
    double totalProtein = 0;        // 🔥 NEW
    double totalCarbohydrates = 0;  // 🔥 NEW
    double totalFiber = 0;          // 🔥 NEW

    for (final item in items) {
      totalCalories += item.calories ?? 0.0;
      totalFat += item.fat ?? 0.0;
      totalSugar += item.sugar ?? 0.0;
      totalSodium += item.sodium ?? 0.0;
      totalProtein += item.protein ?? 0.0;           // 🔥 NEW
      totalCarbohydrates += item.carbs ?? 0.0; // 🔥 NEW
      totalFiber += item.fiber ?? 0.0;               // 🔥 NEW
    }

    // Compute recipe liver score
    final int liverScore = LiverHealthCalculator.calculate(
      fat: totalFat,
      sodium: totalSodium,
      sugar: totalSugar,
      calories: totalCalories,
    );

    return RecipeNutrition(
      calories: totalCalories,
      fat: totalFat,
      sugar: totalSugar,
      sodium: totalSodium,
      protein: totalProtein,           // 🔥 NEW
      carbohydrates: totalCarbohydrates, // 🔥 NEW
      fiber: totalFiber,               // 🔥 NEW
      liverScore: liverScore,
    );
  }

  /// Calculate nutrition for a single serving
  static RecipeNutrition calculatePerServing(
    List<NutritionInfo> items,
    int servings,
  ) {
    if (servings <= 0) {
      throw ArgumentError('Servings must be greater than 0');
    }

    final totals = calculateTotals(items);

    return RecipeNutrition(
      calories: totals.calories / servings,
      fat: totals.fat / servings,
      sugar: totals.sugar / servings,
      sodium: totals.sodium / servings,
      protein: totals.protein / servings,
      carbohydrates: totals.carbohydrates / servings,
      fiber: totals.fiber / servings,
      liverScore: totals.liverScore, // Liver score doesn't change per serving
    );
  }

  /// Get a summary string of macronutrients
  static String getMacroSummary(RecipeNutrition nutrition) {
    final macros = nutrition.macroPercentages;
    
    return 'Protein: ${macros['protein']!.toStringAsFixed(1)}% | '
           'Carbs: ${macros['carbs']!.toStringAsFixed(1)}% | '
           'Fat: ${macros['fat']!.toStringAsFixed(1)}%';
  }

  /// Check if recipe is high protein (>30% of calories from protein)
  static bool isHighProtein(RecipeNutrition nutrition) {
    final macros = nutrition.macroPercentages;
    return macros['protein']! >= 30.0;
  }

  /// Check if recipe is low carb (<30% of calories from carbs)
  static bool isLowCarb(RecipeNutrition nutrition) {
    final macros = nutrition.macroPercentages;
    return macros['carbs']! < 30.0;
  }

  /// Check if recipe is low fat (<30% of calories from fat)
  static bool isLowFat(RecipeNutrition nutrition) {
    final macros = nutrition.macroPercentages;
    return macros['fat']! < 30.0;
  }

  /// Get dietary label for recipe based on macros
  static String getDietaryLabel(RecipeNutrition nutrition) {
    final labels = <String>[];

    if (isHighProtein(nutrition)) {
      labels.add('High Protein');
    }
    if (isLowCarb(nutrition)) {
      labels.add('Low Carb');
    }
    if (isLowFat(nutrition)) {
      labels.add('Low Fat');
    }
    if (nutrition.liverScore >= 75) {
      labels.add('Liver Friendly');
    }

    return labels.isEmpty ? 'Balanced' : labels.join(', ');
  }
}