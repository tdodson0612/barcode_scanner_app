// lib/services/recipe_adaptation_service.dart
// Adapts recipes to fit a user's per-meal nutrition constraints.
// Currently wired to Brittney's bariatric/liver-disease profile.
// iOS 14 Compatible | Production Ready

import '../models/nutrition_info.dart';
import '../models/cookbook_recipe.dart';
import '../services/recipe_nutrition_service.dart';

// ─────────────────────────────────────────────
// DATA CLASSES
// ─────────────────────────────────────────────

/// Brittney's hard per-meal limits (derived from her 1200 kcal/day plan).
/// All values are PER MEAL (÷3), matching her documented macro breakdown.
class UserMealConstraints {
  final double maxCalories;   // kcal  – 400 per meal (1200/3)
  final double maxProtein;    // g     – 35g per meal
  final double maxCarbs;      // g     – 25g per meal
  final double maxFat;        // g     – 9g per meal
  final double minFiber;      // g     – minimum 25g/day target; we don't cap this
  final double maxSodium;     // mg    – 200–300mg per meal (we use 300 as ceiling)
  final double maxSugar;      // g     – 10g per meal

  const UserMealConstraints({
    this.maxCalories = 400,
    this.maxProtein = 35,
    this.maxCarbs = 25,
    this.maxFat = 9,
    this.minFiber = 0,       // No upper cap on fiber
    this.maxSodium = 300,
    this.maxSugar = 10,
  });

  /// Brittney's bariatric + liver-disease profile (post-surgery defaults).
  static const UserMealConstraints brittney = UserMealConstraints(
    maxCalories: 400,
    maxProtein: 35,
    maxCarbs: 25,
    maxFat: 9,
    minFiber: 0,
    maxSodium: 300,
    maxSugar: 10,
  );
}

/// One nutrient that exceeded its limit, with context for the UI.
class NutrientViolation {
  final String nutrient;
  final double actualValue;
  final double limitValue;
  final String unit;
  final double scaleFactor; // How much we need to scale DOWN to fix just this nutrient

  const NutrientViolation({
    required this.nutrient,
    required this.actualValue,
    required this.limitValue,
    required this.unit,
    required this.scaleFactor,
  });

  double get overagePercent =>
      ((actualValue - limitValue) / limitValue * 100);

  String get overageLabel =>
      '+${overagePercent.toStringAsFixed(0)}% over limit';
}

/// Full result returned by RecipeAdaptationService.adapt().
class AdaptedRecipe {
  /// Whether any changes were needed.
  final bool wasAdapted;

  /// The original recipe, unmodified.
  final CookbookRecipe original;

  /// The adapted recipe (same as original if wasAdapted == false).
  final CookbookRecipe adapted;

  /// Unified scale factor applied to ALL ingredients (e.g. 0.75 = 75% of original).
  final double scaleFactor;

  /// Every nutrient that exceeded its limit (before adaptation).
  final List<NutrientViolation> violations;

  /// Human-readable summary of what changed.
  final List<String> changeLog;

  /// Adapted nutrition values (per serving, after scaling).
  final NutritionInfo adaptedNutrition;

  const AdaptedRecipe({
    required this.wasAdapted,
    required this.original,
    required this.adapted,
    required this.scaleFactor,
    required this.violations,
    required this.changeLog,
    required this.adaptedNutrition,
  });
}

// ─────────────────────────────────────────────
// SERVICE
// ─────────────────────────────────────────────

class RecipeAdaptationService {
  // ─── Public API ───────────────────────────────────────────────────────────

  /// Check whether [recipe] fits [constraints] and, if not, return an adapted
  /// version with scaled ingredient quantities and a change log.
  ///
  /// Uses the recipe's per-serving nutrition (nutrition ÷ servings).
  /// If servings is null or 0, treats the whole recipe as one serving.
  static AdaptedRecipe adapt(
    CookbookRecipe recipe, {
    UserMealConstraints constraints = UserMealConstraints.brittney,
  }) {
    final nutrition = recipe.nutrition;

    // If we have no nutrition data we can't adapt — return original unchanged.
    if (nutrition == null) {
      return AdaptedRecipe(
        wasAdapted: false,
        original: recipe,
        adapted: recipe,
        scaleFactor: 1.0,
        violations: [],
        changeLog: ['No nutrition data available — recipe shown as-is.'],
        adaptedNutrition: NutritionInfo(
          productName: recipe.recipeName,
          calories: 0,
          fat: 0,
          sodium: 0,
          sugar: 0,
          protein: 0,
          carbs: 0,
        ),
      );
    }

    final servings = (recipe.servings ?? 1).clamp(1, 999);

    // Per-serving values
    final perServing = _perServing(nutrition, servings);

    // Find all violations
    final violations = _findViolations(perServing, constraints);

    if (violations.isEmpty) {
      // Recipe already fits — no changes needed
      return AdaptedRecipe(
        wasAdapted: false,
        original: recipe,
        adapted: recipe,
        scaleFactor: 1.0,
        violations: [],
        changeLog: ['Recipe meets all nutrition targets — no changes needed!'],
        adaptedNutrition: perServing,
      );
    }

    // The most restrictive violation determines the global scale factor.
    // e.g. if sodium needs 0.6× and fat needs 0.8×, we use 0.6×.
    final scaleFactor = violations
        .map((v) => v.scaleFactor)
        .reduce((a, b) => a < b ? a : b);

    // Scale nutrition
    final adaptedNutrition = _scaleNutrition(perServing, scaleFactor, recipe.recipeName);

    // Scale ingredient quantities in the text
    final adaptedIngredients = _scaleIngredientText(recipe.ingredients, scaleFactor);

    // Build change log
    final changeLog = _buildChangeLog(violations, scaleFactor, adaptedNutrition);

    final adaptedRecipe = recipe.copyWith(
      ingredients: adaptedIngredients,
      nutrition: adaptedNutrition,
      notes: _appendAdaptationNote(recipe.notes, scaleFactor),
    );

    return AdaptedRecipe(
      wasAdapted: true,
      original: recipe,
      adapted: adaptedRecipe,
      scaleFactor: scaleFactor,
      violations: violations,
      changeLog: changeLog,
      adaptedNutrition: adaptedNutrition,
    );
  }

  /// Convenience: check compliance only, without building a full adapted recipe.
  static List<NutrientViolation> checkViolations(
    CookbookRecipe recipe, {
    UserMealConstraints constraints = UserMealConstraints.brittney,
  }) {
    final nutrition = recipe.nutrition;
    if (nutrition == null) return [];
    final servings = (recipe.servings ?? 1).clamp(1, 999);
    return _findViolations(_perServing(nutrition, servings), constraints);
  }

  // ─── Private helpers ──────────────────────────────────────────────────────

  /// Divide total recipe nutrition by serving count.
  static NutritionInfo _perServing(NutritionInfo n, int servings) {
    final s = servings.toDouble();
    return NutritionInfo(
      productName: n.productName,
      calories: n.calories / s,
      fat: n.fat / s,
      saturatedFat: (n.saturatedFat ?? 0) / s,
      monounsaturatedFat: (n.monounsaturatedFat ?? 0) / s,
      transFat: (n.transFat ?? 0) / s,
      sodium: n.sodium / s,
      potassium: (n.potassium ?? 0) / s,
      sugar: n.sugar / s,
      protein: n.protein / s,
      carbs: n.carbs / s,
      fiber: (n.fiber ?? 0) / s,
      iron: (n.iron ?? 0) / s,
      cholesterol: (n.cholesterol ?? 0) / s,
      cobalt: (n.cobalt ?? 0) / s,
    );
  }

  /// Build the list of nutrients that exceed their per-meal limit.
  static List<NutrientViolation> _findViolations(
    NutritionInfo perServing,
    UserMealConstraints c,
  ) {
    final violations = <NutrientViolation>[];

    void check(String name, double actual, double limit, String unit) {
      if (limit <= 0) return;
      if (actual > limit) {
        violations.add(NutrientViolation(
          nutrient: name,
          actualValue: actual,
          limitValue: limit,
          unit: unit,
          // Scale factor needed to bring THIS nutrient to exactly its limit.
          scaleFactor: limit / actual,
        ));
      }
    }

    check('Calories',      perServing.calories,           c.maxCalories, 'kcal');
    check('Sodium',        perServing.sodium,             c.maxSodium,   'mg');
    check('Sugar',         perServing.sugar,              c.maxSugar,    'g');
    check('Fat',           perServing.fat,                c.maxFat,      'g');
    check('Carbohydrates', perServing.carbs,              c.maxCarbs,    'g');
    check('Protein',       perServing.protein,            c.maxProtein,  'g');

    return violations;
  }

  /// Apply a uniform scale factor to all nutrition values.
  static NutritionInfo _scaleNutrition(
    NutritionInfo n,
    double factor,
    String productName,
  ) {
    return NutritionInfo(
      productName: productName,
      calories:           n.calories           * factor,
      fat:                n.fat                * factor,
      saturatedFat:       (n.saturatedFat  ?? 0) * factor,
      monounsaturatedFat: (n.monounsaturatedFat ?? 0) * factor,
      transFat:           (n.transFat      ?? 0) * factor,
      sodium:             n.sodium             * factor,
      potassium:          (n.potassium     ?? 0) * factor,
      sugar:              n.sugar              * factor,
      protein:            n.protein            * factor,
      carbs:              n.carbs              * factor,
      fiber:              (n.fiber         ?? 0) * factor,
      iron:               (n.iron          ?? 0) * factor,
      cholesterol:        (n.cholesterol   ?? 0) * factor,
      cobalt:             (n.cobalt        ?? 0) * factor,
    );
  }

  /// Attempt to scale numeric quantities found in plain-text ingredient lists.
  ///
  /// Handles common formats:
  ///   "2 cups flour"        → "1.5 cups flour"        (factor 0.75)
  ///   "1/2 tsp salt"        → "3/8 tsp salt"          (factor 0.75) — converted to decimal
  ///   "½ cup milk"          → "0.4 cup milk"           (factor 0.75)
  ///   "2-3 cloves garlic"   → "1.5-2.3 cloves garlic" (each number scaled)
  ///
  /// Lines with no leading number are left unchanged (e.g. "to taste").
  static String _scaleIngredientText(String ingredients, double factor) {
    // Map of Unicode vulgar fractions → decimal
    const fractionMap = {
      '½': 0.5,  '⅓': 1/3,  '⅔': 2/3,
      '¼': 0.25, '¾': 0.75,
      '⅛': 0.125,'⅜': 0.375,'⅝': 0.625,'⅞': 0.875,
    };

    final lines = ingredients.split('\n');
    final scaled = lines.map((line) {
      var result = line;

      // Replace Unicode fractions with decimals first
      fractionMap.forEach((glyph, value) {
        result = result.replaceAll(glyph, value.toString());
      });

      // Replace ASCII fractions like 1/2, 3/4 with decimals
      result = result.replaceAllMapped(
        RegExp(r'\b(\d+)/(\d+)\b'),
        (m) {
          final num = double.tryParse(m.group(1)!) ?? 0;
          final den = double.tryParse(m.group(2)!) ?? 1;
          return (den == 0 ? 0 : num / den).toStringAsFixed(3);
        },
      );

      // Scale all leading/inline decimal or integer numbers
      result = result.replaceAllMapped(
        RegExp(r'(?<!\w)(\d+(?:\.\d+)?)(?!\w)'),
        (m) {
          final original = double.tryParse(m.group(1)!);
          if (original == null) return m.group(0)!;
          final scaled = original * factor;
          // Show integer if result is whole, else 1 decimal place
          return scaled == scaled.roundToDouble()
              ? scaled.toInt().toString()
              : scaled.toStringAsFixed(1);
        },
      );

      return result;
    });

    return scaled.join('\n');
  }

  /// Build the human-readable list of changes for display in the UI.
  static List<String> _buildChangeLog(
    List<NutrientViolation> violations,
    double scaleFactor,
    NutritionInfo adapted,
  ) {
    final log = <String>[];
    final pct = ((1 - scaleFactor) * 100).round();

    log.add('Portions reduced by ~$pct% to fit your meal targets:');

    for (final v in violations) {
      log.add(
        '• ${v.nutrient}: ${v.actualValue.toStringAsFixed(1)}${v.unit} → '
        '${(v.actualValue * scaleFactor).toStringAsFixed(1)}${v.unit} '
        '(limit ${v.limitValue.toStringAsFixed(0)}${v.unit})',
      );
    }

    log.add('Adapted nutrition per serving:');
    log.add('  Calories: ${adapted.calories.toStringAsFixed(0)} kcal');
    log.add('  Protein:  ${adapted.protein.toStringAsFixed(1)}g');
    log.add('  Carbs:    ${adapted.carbs.toStringAsFixed(1)}g');
    log.add('  Fat:      ${adapted.fat.toStringAsFixed(1)}g');
    log.add('  Sodium:   ${adapted.sodium.toStringAsFixed(0)}mg');
    log.add('  Sugar:    ${adapted.sugar.toStringAsFixed(1)}g');

    return log;
  }

  /// Append a short note to the recipe's existing notes field.
  static String? _appendAdaptationNote(String? existing, double scaleFactor) {
    final pct = ((1 - scaleFactor) * 100).round();
    final note =
        '[Auto-adapted: portions scaled to ~$pct% to meet your nutrition targets.]';
    return existing != null && existing.isNotEmpty
        ? '$existing\n\n$note'
        : note;
  }
}