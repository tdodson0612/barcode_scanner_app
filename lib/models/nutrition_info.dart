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

    double parseDouble(dynamic value) {
      if (value == null) return 0.0;
      return double.tryParse(value.toString()) ?? 0.0;
    }

    return NutritionInfo(
      productName: product['product_name'] ?? 'Unknown product',
      calories: parseDouble(nutriments['energy-kcal_100g']),
      fat: parseDouble(nutriments['fat_100g']),
      sugar: parseDouble(nutriments['sugars_100g']),
      sodium: parseDouble(nutriments['sodium_100g']),
    );
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
