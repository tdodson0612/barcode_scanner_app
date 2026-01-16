// lib/services/recipe_nutrition_service.dart - COMPLETE WITH ALL NUTRIENTS
// Calculates comprehensive nutrition for recipes
// iOS 14 Compatible | Production Ready

import 'package:liver_wise/models/nutrition_info.dart';
import 'package:liver_wise/liverhealthbar.dart';

class RecipeNutrition {
  final double calories;
  final double fat;
  final double saturatedFat;
  final double monounsaturatedFat;
  final double transFat;
  final double sugar;
  final double sodium;
  final double potassium;
  final double protein;
  final double carbohydrates;
  final double fiber;
  final double iron;
  final double cholesterol;
  final double cobalt;
  final int liverScore;

  RecipeNutrition({
    required this.calories,
    required this.fat,
    this.saturatedFat = 0.0,
    this.monounsaturatedFat = 0.0,
    this.transFat = 0.0,
    required this.sugar,
    required this.sodium,
    this.potassium = 0.0,
    required this.protein,
    required this.carbohydrates,
    this.fiber = 0.0,
    this.iron = 0.0,
    this.cholesterol = 0.0,
    this.cobalt = 0.0,
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

  /// Net carbohydrates (Total Carbs - Fiber)
  double get netCarbs {
    return (carbohydrates - fiber).clamp(0, double.infinity);
  }

  /// Convert to NutritionInfo for display widgets
  NutritionInfo toNutritionInfo({String productName = 'Recipe Total'}) {
    return NutritionInfo(
      productName: productName,
      calories: calories,
      fat: fat,
      saturatedFat: saturatedFat,
      monounsaturatedFat: monounsaturatedFat,
      transFat: transFat,
      sodium: sodium,
      potassium: potassium,
      sugar: sugar,
      protein: protein,
      carbs: carbohydrates,
      fiber: fiber,
      iron: iron,
      cholesterol: cholesterol,
      cobalt: cobalt,
    );
  }
}

class RecipeNutritionService {
  /// Combine multiple ingredients into one nutrition summary
  static RecipeNutrition calculateTotals(List<NutritionInfo> items) {
    double totalCalories = 0;
    double totalFat = 0;
    double totalSaturatedFat = 0;
    double totalMonounsaturatedFat = 0;
    double totalTransFat = 0;
    double totalSugar = 0;
    double totalSodium = 0;
    double totalPotassium = 0;
    double totalProtein = 0;
    double totalCarbohydrates = 0;
    double totalFiber = 0;
    double totalIron = 0;
    double totalCholesterol = 0;
    double totalCobalt = 0;

    for (final item in items) {
      totalCalories += item.calories;
      totalFat += item.fat;
      totalSaturatedFat += item.saturatedFat ?? 0.0;
      totalMonounsaturatedFat += item.monounsaturatedFat ?? 0.0;
      totalTransFat += item.transFat ?? 0.0;
      totalSugar += item.sugar;
      totalSodium += item.sodium;
      totalPotassium += item.potassium ?? 0.0;
      totalProtein += item.protein;
      totalCarbohydrates += item.carbs;
      totalFiber += item.fiber ?? 0.0;
      totalIron += item.iron ?? 0.0;
      totalCholesterol += item.cholesterol ?? 0.0;
      totalCobalt += item.cobalt ?? 0.0;
    }

    // Compute recipe liver score
    final int liverScore = LiverHealthCalculator.calculate(
      fat: totalFat,
      sodium: totalSodium,
      sugar: totalSugar,
      calories: totalCalories,
      protein: totalProtein,
      fiber: totalFiber,
      saturatedFat: totalSaturatedFat,
    );

    return RecipeNutrition(
      calories: totalCalories,
      fat: totalFat,
      saturatedFat: totalSaturatedFat,
      monounsaturatedFat: totalMonounsaturatedFat,
      transFat: totalTransFat,
      sugar: totalSugar,
      sodium: totalSodium,
      potassium: totalPotassium,
      protein: totalProtein,
      carbohydrates: totalCarbohydrates,
      fiber: totalFiber,
      iron: totalIron,
      cholesterol: totalCholesterol,
      cobalt: totalCobalt,
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
      saturatedFat: totals.saturatedFat / servings,
      monounsaturatedFat: totals.monounsaturatedFat / servings,
      transFat: totals.transFat / servings,
      sugar: totals.sugar / servings,
      sodium: totals.sodium / servings,
      potassium: totals.potassium / servings,
      protein: totals.protein / servings,
      carbohydrates: totals.carbohydrates / servings,
      fiber: totals.fiber / servings,
      iron: totals.iron / servings,
      cholesterol: totals.cholesterol / servings,
      cobalt: totals.cobalt / servings,
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

  /// Check if recipe is keto-friendly (<10% carbs, >70% fat)
  static bool isKeto(RecipeNutrition nutrition) {
    final macros = nutrition.macroPercentages;
    return macros['carbs']! < 10.0 && macros['fat']! > 70.0;
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
    if (isKeto(nutrition)) {
      labels.add('Keto');
    }
    if (nutrition.liverScore >= 75) {
      labels.add('Liver Friendly');
    }

    return labels.isEmpty ? 'Balanced' : labels.join(', ');
  }

  /// Get nutrient density score (nutrients per calorie)
  static double getNutrientDensity(RecipeNutrition nutrition) {
    if (nutrition.calories == 0) return 0;
    
    // Higher score = more nutrients per calorie
    final nutrientScore = 
      nutrition.protein + 
      nutrition.fiber + 
      (nutrition.potassium / 100) + 
      (nutrition.iron * 10);
    
    return (nutrientScore / nutrition.calories) * 100;
  }

  /// Check if recipe is heart-healthy
  static bool isHeartHealthy(RecipeNutrition nutrition) {
    return nutrition.saturatedFat < 2.0 &&
           nutrition.transFat == 0.0 &&
           nutrition.cholesterol < 20.0 &&
           nutrition.sodium < 140.0;
  }

  /// Get health warnings
  static List<String> getHealthWarnings(RecipeNutrition nutrition) {
    final warnings = <String>[];

    if (nutrition.saturatedFat > 5.0) {
      warnings.add('High in saturated fat');
    }
    if (nutrition.transFat > 0.0) {
      warnings.add('Contains trans fat');
    }
    if (nutrition.sodium > 400.0) {
      warnings.add('High in sodium');
    }
    if (nutrition.sugar > 15.0) {
      warnings.add('High in sugar');
    }
    if (nutrition.cholesterol > 75.0) {
      warnings.add('High in cholesterol');
    }

    return warnings;
  }

  /// Get health benefits
  static List<String> getHealthBenefits(RecipeNutrition nutrition) {
    final benefits = <String>[];

    if (nutrition.fiber >= 3.0) {
      benefits.add('Good source of fiber');
    }
    if (nutrition.protein >= 10.0) {
      benefits.add('Good source of protein');
    }
    if (nutrition.iron >= 2.0) {
      benefits.add('Good source of iron');
    }
    if (nutrition.potassium >= 300.0) {
      benefits.add('Good source of potassium');
    }
    if (isHeartHealthy(nutrition)) {
      benefits.add('Heart-healthy');
    }

    return benefits;
  }
}