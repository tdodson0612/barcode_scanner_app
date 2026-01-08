// lib/models/nutrition_data.dart
// Complete nutrition data model with disease-aware calculations
// iOS 14 Compatible | Production Ready

class NutritionData {
  final double calories;
  final double fat;
  final double sodium;
  final double sugar;
  final double? protein;
  final double? fiber;
  final double? saturatedFat;
  final double? carbs;
  
  // Optional metadata
  final String? servingSize;
  final String? servingSizeUnit;

  const NutritionData({
    required this.calories,
    required this.fat,
    required this.sodium,
    required this.sugar,
    this.protein,
    this.fiber,
    this.saturatedFat,
    this.carbs,
    this.servingSize,
    this.servingSizeUnit,
  });

  // ========================================
  // FACTORY CONSTRUCTORS
  // ========================================

  /// Create from JSON (database format)
  factory NutritionData.fromJson(Map<String, dynamic> json) {
    return NutritionData(
      calories: _parseDouble(json['calories']),
      fat: _parseDouble(json['fat']),
      sodium: _parseDouble(json['sodium']),
      sugar: _parseDouble(json['sugar']),
      protein: _parseDoubleNullable(json['protein']),
      fiber: _parseDoubleNullable(json['fiber']),
      saturatedFat: _parseDoubleNullable(json['saturatedFat']),
      carbs: _parseDoubleNullable(json['carbs']),
      servingSize: json['servingSize'] as String?,
      servingSizeUnit: json['servingSizeUnit'] as String?,
    );
  }

  /// Create from Open Food Facts API
  factory NutritionData.fromOpenFoodFacts(Map<String, dynamic> json) {
    final product = json['product'] ?? {};
    final nutriments = product['nutriments'] ?? {};

    return NutritionData(
      calories: _getField(nutriments, [
        'energy-kcal_100g',
        'energy-kcal',
        'energy_100g',
      ]),
      fat: _getField(nutriments, [
        'fat_100g',
        'fat',
        'total_fat_100g',
      ]),
      sodium: _getField(nutriments, [
        'sodium_100g',
        'sodium',
      ]),
      sugar: _getField(nutriments, [
        'sugars_100g',
        'sugar_100g',
        'sugars',
      ]),
      protein: _getFieldNullable(nutriments, [
        'proteins_100g',
        'protein_100g',
        'proteins',
      ]),
      fiber: _getFieldNullable(nutriments, [
        'fiber_100g',
        'dietary-fiber_100g',
      ]),
      saturatedFat: _getFieldNullable(nutriments, [
        'saturated-fat_100g',
        'saturated_fat_100g',
      ]),
      carbs: _getFieldNullable(nutriments, [
        'carbohydrates_100g',
        'carbs_100g',
      ]),
      servingSize: product['serving_size'] as String?,
    );
  }

  /// Create from USDA FoodData Central API
  factory NutritionData.fromUSDA(Map<String, dynamic> json) {
    final nutrients = json['foodNutrients'] as List? ?? [];

    double findNutrient(List<int> nutrientIds) {
      for (final id in nutrientIds) {
        final nutrient = nutrients.firstWhere(
          (n) => n['nutrient']?['id'] == id,
          orElse: () => null,
        );
        if (nutrient != null) {
          return _parseDouble(nutrient['amount']);
        }
      }
      return 0.0;
    }

    return NutritionData(
      calories: findNutrient([1008]), // Energy (kcal)
      fat: findNutrient([1004]), // Total lipid (fat)
      sodium: findNutrient([1093]), // Sodium
      sugar: findNutrient([2000, 1063]), // Total sugars
      protein: findNutrient([1003]), // Protein
      fiber: findNutrient([1079]), // Dietary fiber
      saturatedFat: findNutrient([1258]), // Saturated fatty acids
      carbs: findNutrient([1005]), // Carbohydrate
      servingSize: json['servingSize']?.toString(),
      servingSizeUnit: json['servingSizeUnit'] as String?,
    );
  }

  /// Create empty nutrition data
  factory NutritionData.empty() {
    return const NutritionData(
      calories: 0,
      fat: 0,
      sodium: 0,
      sugar: 0,
    );
  }

  // ========================================
  // JSON SERIALIZATION
  // ========================================

  Map<String, dynamic> toJson() {
    return {
      'calories': calories,
      'fat': fat,
      'sodium': sodium,
      'sugar': sugar,
      if (protein != null) 'protein': protein,
      if (fiber != null) 'fiber': fiber,
      if (saturatedFat != null) 'saturatedFat': saturatedFat,
      if (carbs != null) 'carbs': carbs,
      if (servingSize != null) 'servingSize': servingSize,
      if (servingSizeUnit != null) 'servingSizeUnit': servingSizeUnit,
    };
  }

  // ========================================
  // CALCULATIONS
  // ========================================

  /// Calculate liver health score (0-100)
  /// Disease-aware if diseaseType is provided
  int calculateLiverScore({String? diseaseType}) {
    // Base thresholds
    const double fatMax = 20.0;
    const double sodiumMax = 500.0;
    const double sugarMax = 20.0;
    const double calMax = 400.0;

    // Calculate component scores (0-1)
    final fatScore = 1 - (fat / fatMax).clamp(0.0, 1.0);
    final sodiumScore = 1 - (sodium / sodiumMax).clamp(0.0, 1.0);
    final sugarScore = 1 - (sugar / sugarMax).clamp(0.0, 1.0);
    final calScore = 1 - (calories / calMax).clamp(0.0, 1.0);

    // Base weighted score
    double finalScore = (fatScore * 0.3) +
        (sodiumScore * 0.25) +
        (sugarScore * 0.25) +
        (calScore * 0.2);

    // Disease-specific adjustments
    if (diseaseType != null) {
      switch (diseaseType.toLowerCase()) {
        case 'nafld':
        case 'nash':
          // Penalize sugar more heavily
          finalScore -= (sugar / sugarMax) * 0.1;
          break;
        case 'cirrhosis':
          // Penalize sodium more heavily
          finalScore -= (sodium / sodiumMax) * 0.15;
          break;
        case 'hepatitis':
          // Penalize fat more heavily
          finalScore -= (fat / fatMax) * 0.1;
          break;
      }
    }

    // Bonus for beneficial nutrients
    if (protein != null && protein! > 0) {
      finalScore += 0.05;
    }
    if (fiber != null && fiber! > 0) {
      finalScore += 0.05;
    }

    return (finalScore * 100).round().clamp(0, 100);
  }

  /// Scale nutrition by serving multiplier
  NutritionData scale(double multiplier) {
    return NutritionData(
      calories: calories * multiplier,
      fat: fat * multiplier,
      sodium: sodium * multiplier,
      sugar: sugar * multiplier,
      protein: protein != null ? protein! * multiplier : null,
      fiber: fiber != null ? fiber! * multiplier : null,
      saturatedFat: saturatedFat != null ? saturatedFat! * multiplier : null,
      carbs: carbs != null ? carbs! * multiplier : null,
      servingSize: servingSize,
      servingSizeUnit: servingSizeUnit,
    );
  }

  /// Add nutrition from another source
  NutritionData operator +(NutritionData other) {
    return NutritionData(
      calories: calories + other.calories,
      fat: fat + other.fat,
      sodium: sodium + other.sodium,
      sugar: sugar + other.sugar,
      protein: _addNullable(protein, other.protein),
      fiber: _addNullable(fiber, other.fiber),
      saturatedFat: _addNullable(saturatedFat, other.saturatedFat),
      carbs: _addNullable(carbs, other.carbs),
    );
  }

  // ========================================
  // HELPER METHODS
  // ========================================

  /// Check if nutrition data is complete (has all optional fields)
  bool get isComplete {
    return protein != null &&
        fiber != null &&
        saturatedFat != null &&
        carbs != null;
  }

  /// Check if nutrition data is empty (all zeros)
  bool get isEmpty {
    return calories == 0 &&
        fat == 0 &&
        sodium == 0 &&
        sugar == 0 &&
        (protein == null || protein == 0) &&
        (fiber == null || fiber == 0);
  }

  /// Get human-readable serving size
  String get servingSizeDisplay {
    if (servingSize == null) return '100g';
    if (servingSizeUnit != null) {
      return '$servingSize $servingSizeUnit';
    }
    return servingSize!;
  }

  // ========================================
  // PRIVATE HELPERS
  // ========================================

  static double _parseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  static double? _parseDoubleNullable(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  static double _getField(Map<String, dynamic> nutriments, List<String> fields) {
    for (final field in fields) {
      if (nutriments.containsKey(field)) {
        final value = _parseDouble(nutriments[field]);
        if (value > 0) return value;
      }
    }
    return 0.0;
  }

  static double? _getFieldNullable(
    Map<String, dynamic> nutriments,
    List<String> fields,
  ) {
    for (final field in fields) {
      if (nutriments.containsKey(field)) {
        final value = _parseDoubleNullable(nutriments[field]);
        if (value != null && value > 0) return value;
      }
    }
    return null;
  }

  static double? _addNullable(double? a, double? b) {
    if (a == null && b == null) return null;
    return (a ?? 0.0) + (b ?? 0.0);
  }

  // ========================================
  // EQUALITY & HASHCODE
  // ========================================

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is NutritionData &&
        other.calories == calories &&
        other.fat == fat &&
        other.sodium == sodium &&
        other.sugar == sugar &&
        other.protein == protein &&
        other.fiber == fiber &&
        other.saturatedFat == saturatedFat &&
        other.carbs == carbs;
  }

  @override
  int get hashCode {
    return Object.hash(
      calories,
      fat,
      sodium,
      sugar,
      protein,
      fiber,
      saturatedFat,
      carbs,
    );
  }

  @override
  String toString() {
    return 'NutritionData(cal: $calories, fat: $fat, sodium: $sodium, sugar: $sugar)';
  }

  /// Copy with modifications
  NutritionData copyWith({
    double? calories,
    double? fat,
    double? sodium,
    double? sugar,
    double? protein,
    double? fiber,
    double? saturatedFat,
    double? carbs,
    String? servingSize,
    String? servingSizeUnit,
  }) {
    return NutritionData(
      calories: calories ?? this.calories,
      fat: fat ?? this.fat,
      sodium: sodium ?? this.sodium,
      sugar: sugar ?? this.sugar,
      protein: protein ?? this.protein,
      fiber: fiber ?? this.fiber,
      saturatedFat: saturatedFat ?? this.saturatedFat,
      carbs: carbs ?? this.carbs,
      servingSize: servingSize ?? this.servingSize,
      servingSizeUnit: servingSizeUnit ?? this.servingSizeUnit,
    );
  }
}