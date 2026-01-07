// lib/liverhealthbar.dart

import 'package:flutter/material.dart';
import 'models/disease_nutrition_profile.dart';

String getFaceEmoji(int score) {
  if (score <= 25) return '😠';
  if (score <= 49) return '☹️';
  if (score <= 74) return '😐';
  return '😄';
}

class LiverHealthBar extends StatelessWidget {
  final int healthScore;

  const LiverHealthBar({super.key, required this.healthScore});

  // ⬇️ NEW STATIC FUNCTION FOR ALL NUTRITION SYSTEMS
  static int calculateScore({
    required double fat,
    required double sodium,
    required double sugar,
    required double calories,
    String? diseaseType,
    double? protein,
    double? fiber,
    double? saturatedFat,
  }) {
    if (diseaseType == null || diseaseType == 'Other (default scoring)') {
      // Use existing default calculation
      const fatMax = 20.0;
      const sodiumMax = 500.0;
      const sugarMax = 20.0;
      const calMax = 400.0;

      final fatScore = 1 - (fat / fatMax).clamp(0, 1);
      final sodiumScore = 1 - (sodium / sodiumMax).clamp(0, 1);
      final sugarScore = 1 - (sugar / sugarMax).clamp(0, 1);
      final calScore = 1 - (calories / calMax).clamp(0, 1);

      final finalScore = (fatScore * 0.3) +
          (sodiumScore * 0.25) +
          (sugarScore * 0.25) +
          (calScore * 0.2);

      return (finalScore * 100).round().clamp(0, 100);
    } else {
      // Use disease-specific calculation
      return DiseaseNutritionProfile.calculateDiseaseScore(
        diseaseType: diseaseType,
        fat: fat,
        sodium: sodium,
        sugar: sugar,
        calories: calories,
        protein: protein,
        fiber: fiber,
        saturatedFat: saturatedFat,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final face = getFaceEmoji(healthScore);

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            "Liver Health Score: $healthScore/100",
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 40),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          height: 60,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  height: 25,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: const LinearGradient(
                      colors: [Colors.red, Colors.orange, Colors.yellow, Colors.green],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: (MediaQuery.of(context).size.width - 64) *
                    (healthScore / 100) -
                    14,
                child: Text(face, style: const TextStyle(fontSize: 28)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
