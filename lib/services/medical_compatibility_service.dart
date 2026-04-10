// lib/services/medical_compatibility_service.dart
// Single source of truth for all liver-health scoring thresholds and rules.
//
// BEFORE this file, thresholds were duplicated across:
//   - LiverHealthCalculator  (fatMax=20, sodiumMax=500, sugarMax=20, calMax=400)
//   - TrackerService.dailyTargets (fat=55g, sodium=1500mg, sugar=30g, fiber=25g)
//   - LoraDatasetService (_sodiumWarningThreshold=2000, etc.)
//   - scripts/export_training_data.py (sodium_threshold=2000, etc.)
//
// Each threshold group serves a different purpose — they are NOT the same
// numbers. This file documents WHY they differ and provides one place to
// change them all.
//
// iOS 14 Compatible | Production Ready

class MedicalCompatibilityService {
  MedicalCompatibilityService._();

  // ══════════════════════════════════════════════════════════════
  // GROUP A — PRODUCT SCAN SCORING  (LiverHealthCalculator)
  // Used to score a single scanned product per 100g serving.
  // These are intentionally tight because they evaluate one item,
  // not a full day's intake.
  // ══════════════════════════════════════════════════════════════

  /// Max fat per 100g before score penalty kicks in.
  static const double scanFatMaxG = 20.0;

  /// Max sodium per 100g before score penalty kicks in.
  static const double scanSodiumMaxMg = 500.0;

  /// Max sugar per 100g before score penalty kicks in.
  static const double scanSugarMaxG = 20.0;

  /// Max calories per 100g before score penalty kicks in.
  static const double scanCaloriesMax = 400.0;

  /// Score weights for the scan scoring formula.
  static const double scanFatWeight = 0.30;
  static const double scanSodiumWeight = 0.25;
  static const double scanSugarWeight = 0.25;
  static const double scanCaloriesWeight = 0.20;

  /// Minimum acceptable liver health score (0–100).
  /// Recipes/products below this are flagged as not liver-safe.
  static const int minLiverSafeScore = 50;

  // ══════════════════════════════════════════════════════════════
  // GROUP B — DAILY NUTRITION TARGETS  (TrackerService)
  // Full-day targets for a liver-supportive diet.
  // Based on a 2000-calorie low-sodium, moderate-fat diet.
  // ══════════════════════════════════════════════════════════════

  static const Map<String, double> dailyTargets = {
    'calories': 2000,
    'fat': 55,         // g — moderate fat for liver diet
    'sodium': 1500,    // mg — low sodium for liver health
    'sugar': 30,       // g — low sugar
    'protein': 60,     // g — adequate protein
    'fiber': 25,       // g — high fiber supports liver
    'saturatedFat': 15, // g — limit saturated fat
  };

  /// Nutrients where exceeding the target is bad.
  static const Set<String> upperLimitNutrients = {
    'fat', 'sodium', 'sugar', 'saturatedFat',
  };

  /// Nutrients where meeting the target is the goal.
  static const Set<String> lowerTargetNutrients = {
    'calories', 'protein', 'fiber',
  };

  // ══════════════════════════════════════════════════════════════
  // GROUP C — RECIPE COMPLIANCE THRESHOLDS  (LoRA / Compliance)
  // Per-recipe totals that trigger compliance warnings/errors.
  // Higher than scan thresholds because a recipe is evaluated
  // as a whole dish, not per 100g.
  // These match RecipeComplianceService and export_training_data.py.
  // ══════════════════════════════════════════════════════════════

  /// Sodium per full recipe above this triggers a compliance warning.
  static const double recipeMaxSodiumMg = 2000;

  /// Sugar per full recipe above this triggers a compliance warning.
  static const double recipeMaxSugarG = 50;

  /// Fat per full recipe above this triggers a compliance warning.
  static const double recipeMaxFatG = 50;

  // ══════════════════════════════════════════════════════════════
  // GROUP D — DISEASE-SPECIFIC CONSTRAINTS  (LoRA recipe gen)
  // Used when generating or validating recipes for specific
  // liver disease profiles.
  // ══════════════════════════════════════════════════════════════

  static const Map<String, Map<String, double>> diseaseConstraints = {
    'cirrhosis': {
      'maxSodiumMg': 1000,
      'maxSugarG': 25,
      'maxFatG': 30,
      'minProteinG': 30,
      'minHealthScore': 65,
    },
    'NAFLD': {
      'maxSodiumMg': 1500,
      'maxSugarG': 30,
      'maxFatG': 35,
      'minProteinG': 20,
      'minHealthScore': 60,
    },
    'fatty_liver': {
      'maxSodiumMg': 1500,
      'maxSugarG': 30,
      'maxFatG': 35,
      'minProteinG': 20,
      'minHealthScore': 60,
    },
  };

  // ══════════════════════════════════════════════════════════════
  // UTILITY METHODS
  // ══════════════════════════════════════════════════════════════

  /// Calculate liver score for a scanned product (Group A thresholds).
  /// Matches LiverHealthCalculator.calculate() exactly — use this
  /// as the canonical implementation going forward.
  static int calculateScanScore({
    required double fat,
    required double sodium,
    required double sugar,
    required double calories,
  }) {
    final fatScore = 1 - (fat / scanFatMaxG).clamp(0.0, 1.0);
    final sodiumScore = 1 - (sodium / scanSodiumMaxMg).clamp(0.0, 1.0);
    final sugarScore = 1 - (sugar / scanSugarMaxG).clamp(0.0, 1.0);
    final calScore = 1 - (calories / scanCaloriesMax).clamp(0.0, 1.0);
    final finalScore = (fatScore * scanFatWeight) +
        (sodiumScore * scanSodiumWeight) +
        (sugarScore * scanSugarWeight) +
        (calScore * scanCaloriesWeight);
    return (finalScore * 100).round().clamp(0, 100);
  }

  /// Check recipe-level compliance (Group C thresholds).
  /// Returns a list of violation strings; empty = compliant.
  static List<String> checkRecipeCompliance({
    required double sodiumMg,
    required double sugarG,
    required double fatG,
    required int healthScore,
  }) {
    final violations = <String>[];
    if (sodiumMg > recipeMaxSodiumMg) {
      violations.add(
        'Sodium ${sodiumMg.toInt()}mg exceeds limit of ${recipeMaxSodiumMg.toInt()}mg',
      );
    }
    if (sugarG > recipeMaxSugarG) {
      violations.add(
        'Sugar ${sugarG.toStringAsFixed(1)}g exceeds limit of ${recipeMaxSugarG.toInt()}g',
      );
    }
    if (fatG > recipeMaxFatG) {
      violations.add(
        'Fat ${fatG.toStringAsFixed(1)}g exceeds limit of ${recipeMaxFatG.toInt()}g',
      );
    }
    if (healthScore < minLiverSafeScore) {
      violations.add(
        'Health score $healthScore/100 below minimum of $minLiverSafeScore',
      );
    }
    return violations;
  }

  /// Get daily nutrition status for each nutrient.
  /// Returns 'good', 'low', or 'over' — matches TrackerService.getNutritionStatus().
  static Map<String, String> getDailyNutritionStatus(
      Map<String, double> totals) {
    final status = <String, String>{};
    for (final nutrient in dailyTargets.keys) {
      final target = dailyTargets[nutrient]!;
      final actual = totals[nutrient] ?? 0;
      final ratio = actual / target;

      if (upperLimitNutrients.contains(nutrient)) {
        if (ratio > 1.1) {
          status[nutrient] = 'over';
        } else if (ratio >= 0.7) {
          status[nutrient] = 'good';
        } else {
          status[nutrient] = 'low';
        }
      } else {
        if (ratio < 0.5) {
          status[nutrient] = 'low';
        } else if (ratio <= 1.1) {
          status[nutrient] = 'good';
        } else {
          status[nutrient] = 'over';
        }
      }
    }
    return status;
  }

  /// Get disease-specific constraint for a given nutrient.
  /// Returns null if disease is unknown or nutrient not constrained.
  static double? getDiseaseConstraint(String diseaseType, String nutrient) {
    return diseaseConstraints[diseaseType]?[nutrient];
  }

  /// Returns true if this is a known disease type with specific constraints.
  static bool hasConstraintsFor(String? diseaseType) {
    if (diseaseType == null) return false;
    return diseaseConstraints.containsKey(diseaseType);
  }
}