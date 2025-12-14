import 'package:liver_wise/models/nutrition_info.dart';
import 'package:liver_wise/liverhealthbar.dart';

class RecipeNutrition {
  final double calories;
  final double fat;
  final double sugar;
  final double sodium;
  final int liverScore;

  RecipeNutrition({
    required this.calories,
    required this.fat,
    required this.sugar,
    required this.sodium,
    required this.liverScore,
  });
}

class RecipeNutritionService {
  /// Combine multiple ingredients into one nutrition summary
  static RecipeNutrition calculateTotals(List<NutritionInfo> items) {
    double totalCalories = 0;
    double totalFat = 0;
    double totalSugar = 0;
    double totalSodium = 0;

    for (final item in items) {
      totalCalories += item.calories;
      totalFat += item.fat;
      totalSugar += item.sugar;
      totalSodium += item.sodium;
    }

    // Compute recipe liver score (same formula, but scaled for total)
    final int liver = LiverHealthBar.calculateScore(
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
      liverScore: liver,
    );
  }
}
