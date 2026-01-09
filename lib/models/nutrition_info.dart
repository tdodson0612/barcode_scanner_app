// lib/models/nutrition_info.dart - MERGED VERSION
// Combines your existing NutritionInfo with Sprint 1's NutritionData features
// iOS 14 Compatible | Backward Compatible | Production Ready

class NutritionInfo {
  final String productName;
  final double fat;
  final double sodium;
  final double sugar;
  final double calories;
  
  // ✅ NEW: Enhanced nutrition fields (Sprint 1)
  final double? protein;
  final double? fiber;
  final double? saturatedFat;
  final double? carbs;
  final String? servingSize;
  final String? servingSizeUnit;
  
  NutritionInfo({
    required this.productName,
    required this.fat,
    required this.sodium,
    required this.sugar,
    required this.calories,
    this.protein,
    this.fiber,
    this.saturatedFat,
    this.carbs,
    this.servingSize,
    this.servingSizeUnit,
  });
  
  // ✅ EXISTING: Your original fromJson (Open Food Facts)
  factory NutritionInfo.fromJson(Map<String, dynamic> json) {
    final product = json['product'] ?? {};
    final nutriments = product['nutriments'] ?? {};
    
    double parseDouble(dynamic value) {
      if (value == null) return 0.0;
      return double.tryParse(value.toString()) ?? 0.0;
    }
    
    double getField(List<String> fieldNames) {
      for (var field in fieldNames) {
        if (nutriments.containsKey(field)) {
          var value = nutriments[field];
          if (value != null) {
            double parsed = parseDouble(value);
            if (parsed > 0.0) return parsed;
          }
        }
      }
      return 0.0;
    }
    
    // ✅ NEW: Nullable version for optional fields
    double? getFieldNullable(List<String> fieldNames) {
      for (var field in fieldNames) {
        if (nutriments.containsKey(field)) {
          var value = nutriments[field];
          if (value != null) {
            double parsed = parseDouble(value);
            if (parsed > 0.0) return parsed;
          }
        }
      }
      return null;
    }
    
    return NutritionInfo(
      productName: product['product_name'] ?? 'Unknown product',
      calories: getField([
        'energy-kcal_100g',
        'energy-kcal',
        'energy_100g',
        'energy',
        'energy-kj_100g',
      ]),
      fat: getField([
        'fat_100g',
        'fat',
        'total_fat_100g',
        'lipids_100g',
      ]),
      sugar: getField([
        'sugars_100g',
        'sugar_100g',
        'sugars',
        'sugar',
      ]),
      sodium: getField([
        'sodium_100g',
        'sodium',
        'salt_100g',
      ]),
      // ✅ NEW: Parse additional nutrition
      protein: getFieldNullable([
        'proteins_100g',
        'protein_100g',
        'proteins',
      ]),
      fiber: getFieldNullable([
        'fiber_100g',
        'dietary-fiber_100g',
      ]),
      saturatedFat: getFieldNullable([
        'saturated-fat_100g',
        'saturated_fat_100g',
      ]),
      carbs: getFieldNullable([
        'carbohydrates_100g',
        'carbs_100g',
      ]),
      servingSize: product['serving_size'] as String?,
    );
  }
  
  // ✅ NEW: Create from database JSON (for custom ingredients & draft recipes)
  factory NutritionInfo.fromDatabaseJson(Map<String, dynamic> json) {
    return NutritionInfo(
      productName: json['productName'] ?? json['product_name'] ?? 'Unknown',
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
  
  // ✅ NEW: Create empty nutrition
  factory NutritionInfo.empty() {
    return NutritionInfo(
      productName: 'Unknown',
      calories: 0,
      fat: 0,
      sodium: 0,
      sugar: 0,
    );
  }
  
  // ✅ NEW: Convert to JSON (for database storage)
  Map<String, dynamic> toJson() {
    return {
      'productName': productName,
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
  
  // ✅ NEW: Calculate liver health score with disease awareness
  int calculateLiverScore({String? diseaseType}) {
    return LiverHealthCalculator.calculate(
      fat: fat,
      sodium: sodium,
      sugar: sugar,
      calories: calories,
      diseaseType: diseaseType,
      protein: protein,
      fiber: fiber,
      saturatedFat: saturatedFat,
    );
  }
  
  // ✅ NEW: Scale nutrition by serving multiplier
  NutritionInfo scale(double multiplier) {
    return NutritionInfo(
      productName: productName,
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
  
  // ✅ NEW: Add nutrition from another source
  NutritionInfo operator +(NutritionInfo other) {
    return NutritionInfo(
      productName: '$productName + ${other.productName}',
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
  
  // ✅ NEW: Check if nutrition data is complete
  bool get isComplete {
    return protein != null &&
        fiber != null &&
        saturatedFat != null &&
        carbs != null;
  }
  
  // ✅ NEW: Check if empty
  bool get isEmpty {
    return calories == 0 &&
        fat == 0 &&
        sodium == 0 &&
        sugar == 0 &&
        (protein == null || protein == 0) &&
        (fiber == null || fiber == 0);
  }
  
  // ✅ NEW: Get serving size display
  String get servingSizeDisplay {
    if (servingSize == null) return '100g';
    if (servingSizeUnit != null) {
      return '$servingSize $servingSizeUnit';
    }
    return servingSize!;
  }
  
  // ✅ NEW: Copy with modifications
  NutritionInfo copyWith({
    String? productName,
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
    return NutritionInfo(
      productName: productName ?? this.productName,
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
  
  static double? _addNullable(double? a, double? b) {
    if (a == null && b == null) return null;
    return (a ?? 0.0) + (b ?? 0.0);
  }
  
  // ✅ EXISTING: Your original debug method
  static void debugNutriments(Map<String, dynamic> json) {
    final product = json['product'] ?? {};
    final nutriments = product['nutriments'] ?? {};
    
    print('🔍 DEBUG: Available nutriment fields:');
    nutriments.forEach((key, value) {
      print('  $key: $value');
    });
  }
}

// ✅ ENHANCED: Your existing LiverHealthCalculator with disease awareness
class LiverHealthCalculator {
  static const double fatMax = 20.0;
  static const double sodiumMax = 500.0;
  static const double sugarMax = 20.0;
  static const double calMax = 400.0;
  
  static int calculate({
    required double fat,
    required double sodium,
    required double sugar,
    required double calories,
    String? diseaseType,
    double? protein,
    double? fiber,
    double? saturatedFat,
  }) {
    final fatScore = 1 - (fat / fatMax).clamp(0, 1);
    final sodiumScore = 1 - (sodium / sodiumMax).clamp(0, 1);
    final sugarScore = 1 - (sugar / sugarMax).clamp(0, 1);
    final calScore = 1 - (calories / calMax).clamp(0, 1);
    
    double finalScore = (fatScore * 0.3) +
        (sodiumScore * 0.25) +
        (sugarScore * 0.25) +
        (calScore * 0.2);
    
    // ✅ NEW: Disease-specific adjustments
    if (diseaseType != null) {
      switch (diseaseType.toLowerCase()) {
        case 'nafld':
        case 'nash':
          finalScore -= (sugar / sugarMax) * 0.1;
          break;
        case 'cirrhosis':
          finalScore -= (sodium / sodiumMax) * 0.15;
          break;
        case 'hepatitis':
          finalScore -= (fat / fatMax) * 0.1;
          break;
      }
    }
    
    // ✅ NEW: Bonus for beneficial nutrients
    if (protein != null && protein > 0) {
      finalScore += 0.05;
    }
    if (fiber != null && fiber > 0) {
      finalScore += 0.05;
    }
    
    return (finalScore * 100).round().clamp(0, 100);
  }
}