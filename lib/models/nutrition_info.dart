class NutritionInfo {
  final String productName;
  final double fat;
  final double sodium;
  final double sugar;
  final double calories;
  
  NutritionInfo({
    required this.productName,
    required this.fat,
    required this.sodium,
    required this.sugar,
    required this.calories,
  });
  
  factory NutritionInfo.fromJson(Map<String, dynamic> json) {
    final product = json['product'] ?? {};
    final nutriments = product['nutriments'] ?? {};
    
    // Helper function to parse double values
    double parseDouble(dynamic value) {
      if (value == null) return 0.0;
      return double.tryParse(value.toString()) ?? 0.0;
    }
    
    // Helper function to try multiple field name variations
    double getField(List<String> fieldNames) {
      for (var field in fieldNames) {
        if (nutriments.containsKey(field)) {
          var value = nutriments[field];
          if (value != null) {
            double parsed = parseDouble(value);
            if (parsed > 0.0) return parsed; // Return first non-zero value found
          }
        }
      }
      return 0.0;
    }
    
    return NutritionInfo(
      productName: product['product_name'] ?? 'Unknown product',
      // Try multiple variations for each nutrient
      calories: getField([
        'energy-kcal_100g',
        'energy-kcal',
        'energy_100g',
        'energy',
        'energy-kj_100g', // Sometimes only kJ is available (divide by 4.184 if needed)
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
        'salt_100g', // Note: salt needs to be converted (salt = sodium * 2.5)
      ]),
    );
  }
  
  // Debug method to print all available nutriment fields
  static void debugNutriments(Map<String, dynamic> json) {
    final product = json['product'] ?? {};
    final nutriments = product['nutriments'] ?? {};
    
    print('🔍 DEBUG: Available nutriment fields:');
    nutriments.forEach((key, value) {
      print('  $key: $value');
    });
  }
}

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
  }) {
    final fatScore = 1 - (fat / fatMax).clamp(0, 1);
    final sodiumScore = 1 - (sodium / sodiumMax).clamp(0, 1);
    final sugarScore = 1 - (sugar / sugarMax).clamp(0, 1);
    final calScore = 1 - (calories / calMax).clamp(0, 1);
    
    final finalScore = (fatScore * 0.3) +
        (sodiumScore * 0.25) +
        (sugarScore * 0.25) +
        (calScore * 0.2);
    
    return (finalScore * 100).round().clamp(0, 100);
  }
}