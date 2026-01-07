// lib/models/disease_nutrition_profile.dart


class DiseaseNutritionProfile {
  static const String NAFLD = 'Non-Alcoholic Fatty Liver Disease (NAFLD / MASLD)';
  static const String ALD = 'Alcohol-Related Liver Disease (ALD)';
  static const String HEPATITIS = 'Chronic Viral Hepatitis (B or C)';
  static const String CIRRHOSIS = 'Cirrhosis';
  static const String HE = 'Hepatic Encephalopathy (HE)';
  static const String CHOLESTATIC = 'Cholestatic Liver Disease (PBC / PSC)';
  static const String GENETIC = 'Genetic / Metabolic Liver Disease';
  static const String OTHER = 'Other (default scoring)';

  static List<String> getAllDiseaseTypes() {
    return [
      NAFLD,
      ALD,
      HEPATITIS,
      CIRRHOSIS,
      HE,
      CHOLESTATIC,
      GENETIC,
      OTHER,
    ];
  }

  /// Calculate disease-aware score (0-100)
  static int calculateDiseaseScore({
    required String diseaseType,
    required double fat,
    required double sodium,
    required double sugar,
    required double calories,
    double? protein,
    double? fiber,
    double? saturatedFat,
  }) {
    // Default fallback scoring
    if (diseaseType == OTHER || diseaseType.isEmpty) {
      return _calculateDefaultScore(
        fat: fat,
        sodium: sodium,
        sugar: sugar,
        calories: calories,
      );
    }

    // Disease-specific scoring
    switch (diseaseType) {
      case NAFLD:
        return _calculateNAFLDScore(
          fat: fat,
          sodium: sodium,
          sugar: sugar,
          calories: calories,
          fiber: fiber,
          saturatedFat: saturatedFat,
        );
      
      case ALD:
        return _calculateALDScore(
          fat: fat,
          sodium: sodium,
          sugar: sugar,
          calories: calories,
          protein: protein,
        );
      
      case HEPATITIS:
        return _calculateHepatitisScore(
          fat: fat,
          sodium: sodium,
          sugar: sugar,
          calories: calories,
          protein: protein,
        );
      
      case CIRRHOSIS:
        return _calculateCirrhosisScore(
          fat: fat,
          sodium: sodium,
          sugar: sugar,
          calories: calories,
          protein: protein,
        );
      
      case HE:
        return _calculateHEScore(
          fat: fat,
          sodium: sodium,
          sugar: sugar,
          calories: calories,
          protein: protein,
        );
      
      case CHOLESTATIC:
        return _calculateCholestaticScore(
          fat: fat,
          sodium: sodium,
          sugar: sugar,
          calories: calories,
        );
      
      case GENETIC:
        return _calculateGeneticScore(
          fat: fat,
          sodium: sodium,
          sugar: sugar,
          calories: calories,
        );
      
      default:
        return _calculateDefaultScore(
          fat: fat,
          sodium: sodium,
          sugar: sugar,
          calories: calories,
        );
    }
  }

  // ========================================
  // DEFAULT SCORING (Existing generalized)
  // ========================================
  static int _calculateDefaultScore({
    required double fat,
    required double sodium,
    required double sugar,
    required double calories,
  }) {
    const fatMax = 20.0;
    const sodiumMax = 500.0;
    const sugarMax = 20.0;
    const calMax = 400.0;

    final fatScore = 1 - (fat / fatMax).clamp(0.0, 1.0);
    final sodiumScore = 1 - (sodium / sodiumMax).clamp(0.0, 1.0);
    final sugarScore = 1 - (sugar / sugarMax).clamp(0.0, 1.0);
    final calScore = 1 - (calories / calMax).clamp(0.0, 1.0);

    final finalScore = (fatScore * 0.3) +
        (sodiumScore * 0.25) +
        (sugarScore * 0.25) +
        (calScore * 0.2);

    return (finalScore * 100).round().clamp(0, 100);
  }

  // ========================================
  // NAFLD SCORING
  // Focus: Low sugar, low saturated fat, high fiber
  // ========================================
  static int _calculateNAFLDScore({
    required double fat,
    required double sodium,
    required double sugar,
    required double calories,
    double? fiber,
    double? saturatedFat,
  }) {
    // NAFLD priorities: sugar is critical, saturated fat matters
    final sugarScore = 1 - (sugar / 15.0).clamp(0.0, 1.0); // Stricter sugar
    final satFatScore = saturatedFat != null 
        ? 1 - (saturatedFat / 10.0).clamp(0.0, 1.0)
        : 1 - (fat * 0.35 / 10.0).clamp(0.0, 1.0); // Estimate if missing
    
    final sodiumScore = 1 - (sodium / 500.0).clamp(0.0, 1.0);
    final calScore = 1 - (calories / 400.0).clamp(0.0, 1.0);
    
    // Bonus for fiber
    final fiberBonus = fiber != null && fiber >= 5.0 ? 0.05 : 0.0;

    final finalScore = (sugarScore * 0.35) +
        (satFatScore * 0.30) +
        (sodiumScore * 0.20) +
        (calScore * 0.15) +
        fiberBonus;

    return (finalScore * 100).round().clamp(0, 100);
  }

  // ========================================
  // ALD SCORING
  // Focus: High protein, moderate calories, avoid alcohol
  // ========================================
  static int _calculateALDScore({
    required double fat,
    required double sodium,
    required double sugar,
    required double calories,
    double? protein,
  }) {
    // ALD needs adequate protein for liver repair
    final proteinScore = protein != null
        ? (protein / 25.0).clamp(0.0, 1.0) // Good if >=25g protein per serving
        : 0.5; // Neutral if unknown
    
    final sodiumScore = 1 - (sodium / 500.0).clamp(0.0, 1.0);
    final sugarScore = 1 - (sugar / 20.0).clamp(0.0, 1.0);
    final calScore = 1 - (calories / 450.0).clamp(0.0, 1.0);

    final finalScore = (proteinScore * 0.35) +
        (sodiumScore * 0.25) +
        (sugarScore * 0.20) +
        (calScore * 0.20);

    return (finalScore * 100).round().clamp(0, 100);
  }

  // ========================================
  // HEPATITIS SCORING
  // Focus: Balanced nutrition, avoid excess fat
  // ========================================
  static int _calculateHepatitisScore({
    required double fat,
    required double sodium,
    required double sugar,
    required double calories,
    double? protein,
  }) {
    final fatScore = 1 - (fat / 18.0).clamp(0.0, 1.0);
    final sodiumScore = 1 - (sodium / 400.0).clamp(0.0, 1.0); // Stricter sodium
    final sugarScore = 1 - (sugar / 20.0).clamp(0.0, 1.0);
    final proteinScore = protein != null && protein >= 15.0 ? 0.05 : 0.0;

    final finalScore = (fatScore * 0.30) +
        (sodiumScore * 0.30) +
        (sugarScore * 0.25) +
        ((1 - (calories / 400.0).clamp(0.0, 1.0)) * 0.15) +
        proteinScore;

    return (finalScore * 100).round().clamp(0, 100);
  }

  // ========================================
  // CIRRHOSIS SCORING
  // Focus: Low sodium (critical), adequate protein
  // ========================================
  static int _calculateCirrhosisScore({
    required double fat,
    required double sodium,
    required double sugar,
    required double calories,
    double? protein,
  }) {
    // Sodium is CRITICAL in cirrhosis (fluid retention)
    final sodiumScore = 1 - (sodium / 300.0).clamp(0.0, 1.0); // Very strict
    
    // Need adequate protein but not excessive
    final proteinScore = protein != null
        ? (protein >= 15.0 && protein <= 30.0 ? 1.0 : 0.5)
        : 0.5;
    
    final fatScore = 1 - (fat / 20.0).clamp(0.0, 1.0);
    final sugarScore = 1 - (sugar / 20.0).clamp(0.0, 1.0);

    final finalScore = (sodiumScore * 0.40) + // Sodium is key
        (proteinScore * 0.30) +
        (fatScore * 0.15) +
        (sugarScore * 0.15);

    return (finalScore * 100).round().clamp(0, 100);
  }

  // ========================================
  // HEPATIC ENCEPHALOPATHY SCORING
  // Focus: Moderate protein, low ammonia foods
  // ========================================
  static int _calculateHEScore({
    required double fat,
    required double sodium,
    required double sugar,
    required double calories,
    double? protein,
  }) {
    // HE needs protein but not too much (ammonia concern)
    final proteinScore = protein != null
        ? (protein <= 20.0 ? 1.0 : 1 - ((protein - 20.0) / 30.0).clamp(0.0, 1.0))
        : 0.7;
    
    final sodiumScore = 1 - (sodium / 350.0).clamp(0.0, 1.0);
    final sugarScore = 1 - (sugar / 20.0).clamp(0.0, 1.0);
    final fatScore = 1 - (fat / 18.0).clamp(0.0, 1.0);

    final finalScore = (proteinScore * 0.35) +
        (sodiumScore * 0.30) +
        (sugarScore * 0.20) +
        (fatScore * 0.15);

    return (finalScore * 100).round().clamp(0, 100);
  }

  // ========================================
  // CHOLESTATIC SCORING
  // Focus: Low fat (especially saturated), fat-soluble vitamins
  // ========================================
  static int _calculateCholestaticScore({
    required double fat,
    required double sodium,
    required double sugar,
    required double calories,
  }) {
    // Fat is critical in cholestatic disease
    final fatScore = 1 - (fat / 12.0).clamp(0.0, 1.0); // Very strict on fat
    final sodiumScore = 1 - (sodium / 400.0).clamp(0.0, 1.0);
    final sugarScore = 1 - (sugar / 20.0).clamp(0.0, 1.0);
    final calScore = 1 - (calories / 350.0).clamp(0.0, 1.0);

    final finalScore = (fatScore * 0.45) + // Fat is key
        (sodiumScore * 0.25) +
        (sugarScore * 0.15) +
        (calScore * 0.15);

    return (finalScore * 100).round().clamp(0, 100);
  }

  // ========================================
  // GENETIC/METABOLIC SCORING
  // Focus: Balanced, avoid specific triggers
  // ========================================
  static int _calculateGeneticScore({
    required double fat,
    required double sodium,
    required double sugar,
    required double calories,
  }) {
    // Use balanced approach similar to default but slightly adjusted
    final fatScore = 1 - (fat / 18.0).clamp(0.0, 1.0);
    final sodiumScore = 1 - (sodium / 450.0).clamp(0.0, 1.0);
    final sugarScore = 1 - (sugar / 18.0).clamp(0.0, 1.0);
    final calScore = 1 - (calories / 400.0).clamp(0.0, 1.0);

    final finalScore = (fatScore * 0.30) +
        (sodiumScore * 0.25) +
        (sugarScore * 0.25) +
        (calScore * 0.20);

    return (finalScore * 100).round().clamp(0, 100);
  }

  /// Get user-friendly description of disease focus
  static String getDiseaseGuidance(String diseaseType) {
    switch (diseaseType) {
      case NAFLD:
        return 'Focus on: Low sugar, low saturated fat, high fiber foods';
      case ALD:
        return 'Focus on: Adequate protein, avoid alcohol, balanced nutrition';
      case HEPATITIS:
        return 'Focus on: Balanced nutrition, moderate fat, low sodium';
      case CIRRHOSIS:
        return 'Focus on: Very low sodium, adequate protein (15-30g)';
      case HE:
        return 'Focus on: Moderate protein (≤20g), low sodium';
      case CHOLESTATIC:
        return 'Focus on: Very low fat, especially saturated fat';
      case GENETIC:
        return 'Focus on: Balanced nutrition, avoid specific triggers';
      default:
        return 'Using generalized liver health scoring';
    }
  }
}