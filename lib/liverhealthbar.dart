// lib/liverhealthbar.dart
import 'package:flutter/material.dart';
import 'models/disease_nutrition_profile.dart';

String getFaceEmoji(int score) {
  if (score <= 25) return '😠';
  if (score <= 49) return '☹️';
  if (score <= 74) return '😐';
  return '😄';
}

/// Returns a human-readable rating label for a score
String getScoreLabel(int score) {
  if (score <= 25) return 'Poor';
  if (score <= 49) return 'Fair';
  if (score <= 74) return 'Good';
  return 'Excellent';
}

/// Returns the color matching the score
Color getScoreColor(int score) {
  if (score <= 25) return Colors.red.shade700;
  if (score <= 49) return Colors.orange.shade700;
  if (score <= 74) return Colors.yellow.shade800;
  return Colors.green.shade700;
}

/// 🔥 Standalone calculator class for all pages to use
class LiverHealthCalculator {
  static const double fatMax = 20.0;
  static const double sodiumMax = 500.0;
  static const double sugarMax = 20.0;
  static const double calMax = 400.0;

  /// Main calculate method - matches the signature used across all pages
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
    if (diseaseType == null || diseaseType == 'Other (default scoring)') {
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

  /// Returns a list of reasons explaining the score based on nutrient values
  static List<_ScoreReason> explainScore({
    required double fat,
    required double sodium,
    required double sugar,
    required double calories,
  }) {
    final reasons = <_ScoreReason>[];

    // Fat
    final fatPct = (fat / fatMax).clamp(0, 1);
    if (fatPct >= 0.8) {
      reasons.add(_ScoreReason(
        label: 'High fat',
        detail: '${fat.toStringAsFixed(1)}g per 100g — exceeds liver-safe limit of ${fatMax.toInt()}g',
        isNegative: true,
        icon: Icons.warning_rounded,
      ));
    } else if (fatPct <= 0.3) {
      reasons.add(_ScoreReason(
        label: 'Low fat',
        detail: '${fat.toStringAsFixed(1)}g per 100g — great for liver health',
        isNegative: false,
        icon: Icons.check_circle_rounded,
      ));
    }

    // Sodium
    final sodiumPct = (sodium / sodiumMax).clamp(0, 1);
    if (sodiumPct >= 0.8) {
      reasons.add(_ScoreReason(
        label: 'High sodium',
        detail: '${sodium.toStringAsFixed(0)}mg per 100g — can strain the liver and raise blood pressure',
        isNegative: true,
        icon: Icons.warning_rounded,
      ));
    } else if (sodiumPct <= 0.3) {
      reasons.add(_ScoreReason(
        label: 'Low sodium',
        detail: '${sodium.toStringAsFixed(0)}mg per 100g — good for liver and heart health',
        isNegative: false,
        icon: Icons.check_circle_rounded,
      ));
    }

    // Sugar
    final sugarPct = (sugar / sugarMax).clamp(0, 1);
    if (sugarPct >= 0.8) {
      reasons.add(_ScoreReason(
        label: 'High sugar',
        detail: '${sugar.toStringAsFixed(1)}g per 100g — excess sugar converts to liver fat',
        isNegative: true,
        icon: Icons.warning_rounded,
      ));
    } else if (sugarPct <= 0.3) {
      reasons.add(_ScoreReason(
        label: 'Low sugar',
        detail: '${sugar.toStringAsFixed(1)}g per 100g — reduces liver fat risk',
        isNegative: false,
        icon: Icons.check_circle_rounded,
      ));
    }

    // Calories
    final calPct = (calories / calMax).clamp(0, 1);
    if (calPct >= 0.8) {
      reasons.add(_ScoreReason(
        label: 'High calories',
        detail: '${calories.toStringAsFixed(0)} kcal per 100g — calorie-dense foods increase liver load',
        isNegative: true,
        icon: Icons.warning_rounded,
      ));
    } else if (calPct <= 0.3) {
      reasons.add(_ScoreReason(
        label: 'Low calories',
        detail: '${calories.toStringAsFixed(0)} kcal per 100g — light on the liver',
        isNegative: false,
        icon: Icons.check_circle_rounded,
      ));
    }

    // If nothing notable either way
    if (reasons.isEmpty) {
      reasons.add(_ScoreReason(
        label: 'Moderate overall',
        detail: 'No single nutrient is significantly high or low — a reasonable choice in moderation',
        isNegative: false,
        icon: Icons.info_rounded,
      ));
    }

    return reasons;
  }
}

/// Internal data class for score explanation items
class _ScoreReason {
  final String label;
  final String detail;
  final bool isNegative;
  final IconData icon;

  const _ScoreReason({
    required this.label,
    required this.detail,
    required this.isNegative,
    required this.icon,
  });
}

/// The gradient score bar widget — unchanged visual, used on scanner results
class LiverHealthBar extends StatelessWidget {
  final int healthScore;

  const LiverHealthBar({super.key, required this.healthScore});

  /// Legacy static function for backwards compatibility
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

  @override
  Widget build(BuildContext context) {
    final face = getFaceEmoji(healthScore);
    return Stack(
      children: [
        // Gradient Bar
        Container(
          height: 25,
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: const LinearGradient(
              colors: [Colors.red, Colors.orange, Colors.yellow, Colors.green],
            ),
          ),
        ),
        // Emoji sliding over bar
        Positioned(
          left: 16 +
              (MediaQuery.of(context).size.width - 32 - 28) *
                  (healthScore / 100),
          top: -30,
          child: Text(
            face,
            style: const TextStyle(fontSize: 28),
          ),
        ),
      ],
    );
  }
}

/// 🔥 NEW: Full scan results card — replaces the plain green text box
/// Shows score, rating, nutrient grid, why explanation, and alternatives
class ScanResultsCard extends StatelessWidget {
  final String productName;
  final double fat;
  final double sodium;
  final double sugar;
  final double calories;
  final int liverScore;

  const ScanResultsCard({
    super.key,
    required this.productName,
    required this.fat,
    required this.sodium,
    required this.sugar,
    required this.calories,
    required this.liverScore,
  });

  @override
  Widget build(BuildContext context) {
    final scoreColor = getScoreColor(liverScore);
    final scoreLabel = getScoreLabel(liverScore);
    final face = getFaceEmoji(liverScore);
    final reasons = LiverHealthCalculator.explainScore(
      fat: fat,
      sodium: sodium,
      sugar: sugar,
      calories: calories,
    );
    final alternatives = _getAlternatives(liverScore);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header: product name + score badge ──
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: scoreColor.withOpacity(0.08),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Score circle
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: scoreColor,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '$liverScore',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        '/100',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.white.withOpacity(0.85),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 14),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        productName,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            face,
                            style: const TextStyle(fontSize: 20),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 3),
                            decoration: BoxDecoration(
                              color: scoreColor,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              scoreLabel,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Liver-friendliness score',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Score bar ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
            child: SizedBox(
              height: 60,
              child: LiverHealthBar(healthScore: liverScore),
            ),
          ),

          const SizedBox(height: 8),

          // ── Nutrient grid ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _buildNutrientTile(
                  'Calories',
                  '${calories.toStringAsFixed(0)} kcal',
                  calories,
                  LiverHealthCalculator.calMax,
                ),
                const SizedBox(width: 8),
                _buildNutrientTile(
                  'Fat',
                  '${fat.toStringAsFixed(1)}g',
                  fat,
                  LiverHealthCalculator.fatMax,
                ),
                const SizedBox(width: 8),
                _buildNutrientTile(
                  'Sugar',
                  '${sugar.toStringAsFixed(1)}g',
                  sugar,
                  LiverHealthCalculator.sugarMax,
                ),
                const SizedBox(width: 8),
                _buildNutrientTile(
                  'Sodium',
                  '${sodium.toStringAsFixed(0)}mg',
                  sodium,
                  LiverHealthCalculator.sodiumMax,
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ── Why this score ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info_outline_rounded,
                        size: 16, color: Colors.grey.shade700),
                    const SizedBox(width: 6),
                    Text(
                      'Why this score?',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey.shade800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ...reasons.map((r) => _buildReasonRow(r)),
              ],
            ),
          ),

          // ── Alternatives (only if score is poor/fair) ──
          if (alternatives.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.lightbulb_rounded,
                          size: 16, color: Colors.green.shade700),
                      const SizedBox(width: 6),
                      Text(
                        'Liver-friendly alternatives',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Colors.green.shade800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...alternatives.map((alt) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.arrow_right_rounded,
                                size: 18, color: Colors.green.shade600),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                alt,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.green.shade900,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )),
                ],
              ),
            ),
          ],

          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildNutrientTile(
      String label, String value, double actual, double max) {
    final pct = (actual / max).clamp(0.0, 1.0);
    Color barColor;
    if (pct >= 0.8) {
      barColor = Colors.red.shade600;
    } else if (pct >= 0.5) {
      barColor = Colors.orange.shade600;
    } else {
      barColor = Colors.green.shade600;
    }

    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: barColor,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: pct,
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation<Color>(barColor),
                minHeight: 5,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${(pct * 100).toInt()}% of limit',
              style: TextStyle(
                fontSize: 9,
                color: Colors.grey.shade500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReasonRow(_ScoreReason reason) {
    final color =
        reason.isNegative ? Colors.red.shade700 : Colors.green.shade700;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(reason.icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: '${reason.label}: ',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                  TextSpan(
                    text: reason.detail,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<String> _getAlternatives(int score) {
    if (score > 74) return []; // Excellent — no need for alternatives

    if (score <= 25) {
      // Poor
      return [
        'Fresh or frozen vegetables — naturally low in fat, sodium, and sugar',
        'Whole grains like oats or brown rice — fiber-rich and liver-supportive',
        'Legumes (lentils, chickpeas) — high protein with minimal liver impact',
        'Fresh fruit instead of processed snacks for natural sweetness',
      ];
    } else if (score <= 49) {
      // Fair
      return [
        'Look for a low-sodium version of this product',
        'Choose products with less than 5g sugar per 100g',
        'Greek yogurt or cottage cheese as a high-protein, lower-fat swap',
        'Unsalted nuts in small amounts for healthy fats',
      ];
    } else {
      // Good (51–74) — minor suggestions
      return [
        'This is a reasonable choice — enjoy in moderation',
        'Pair with vegetables or fiber-rich foods to balance the meal',
      ];
    }
  }
}