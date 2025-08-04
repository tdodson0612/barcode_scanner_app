import 'package:flutter/material.dart';

String getFaceEmoji(int score) {
  if (score <= 25) return '😠';
  if (score <= 49) return '☹️';
  if (score <= 74) return '😐';
  return '😄';
}

class LiverHealthBar extends StatelessWidget {
  final int healthScore;

  const LiverHealthBar({super.key, required this.healthScore});

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
          left: 16 + (MediaQuery.of(context).size.width - 32 - 28) * (healthScore / 100),
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
