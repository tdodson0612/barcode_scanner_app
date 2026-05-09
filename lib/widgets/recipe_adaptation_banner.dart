// lib/widgets/recipe_adaptation_banner.dart
// Displays an inline adaptation notice when a recipe has been auto-adjusted
// to fit the user's per-meal nutrition constraints.
// iOS 14 Compatible | Production Ready

import 'package:flutter/material.dart';
import '../services/recipe_adaptation_service.dart';

class RecipeAdaptationBanner extends StatefulWidget {
  /// The full result from RecipeAdaptationService.adapt().
  final AdaptedRecipe adaptedRecipe;

  /// Called when the user taps "Show original" or "Show adapted".
  final ValueChanged<bool> onToggleVersion;

  /// Whether the UI is currently showing the adapted version.
  final bool showingAdapted;

  const RecipeAdaptationBanner({
    super.key,
    required this.adaptedRecipe,
    required this.onToggleVersion,
    required this.showingAdapted,
  });

  @override
  State<RecipeAdaptationBanner> createState() => _RecipeAdaptationBannerState();
}

class _RecipeAdaptationBannerState extends State<RecipeAdaptationBanner> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final result = widget.adaptedRecipe;

    // Recipe already compliant — show a quiet green badge
    if (!result.wasAdapted) {
      return Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.green.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.green.shade200),
        ),
        child: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green.shade700, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'This recipe fits your meal targets',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.green.shade800,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final pct = ((1 - result.scaleFactor) * 100).round();

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.orange.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header row ──────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.tune, color: Colors.orange.shade700, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Recipe adapted for your profile',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange.shade900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Portions reduced ~$pct% to meet your per-meal limits',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.orange.shade800,
                        ),
                      ),
                    ],
                  ),
                ),
                // Expand / collapse chevron
                GestureDetector(
                  onTap: () => setState(() => _expanded = !_expanded),
                  child: Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    color: Colors.orange.shade700,
                    size: 22,
                  ),
                ),
              ],
            ),
          ),

          // ── Violation pills ─────────────────────────────────────────────
          if (result.violations.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: result.violations.map((v) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.red.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${v.nutrient} ${v.overageLabel}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.red.shade800,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),

          // ── Expandable change log ────────────────────────────────────────
          if (_expanded) ...[
            const Divider(height: 1, thickness: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
              child: Text(
                'What changed',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.orange.shade900,
                ),
              ),
            ),
            ...result.changeLog.map(
              (line) => Padding(
                padding: const EdgeInsets.fromLTRB(12, 2, 12, 2),
                child: Text(
                  line,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.orange.shade800,
                    height: 1.5,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],

          // ── Toggle original / adapted ────────────────────────────────────
          const Divider(height: 1, thickness: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: _VersionToggleButton(
                    label: 'Adapted (recommended)',
                    icon: Icons.check_circle_outline,
                    active: widget.showingAdapted,
                    color: Colors.green,
                    onTap: () => widget.onToggleVersion(true),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _VersionToggleButton(
                    label: 'Original recipe',
                    icon: Icons.history,
                    active: !widget.showingAdapted,
                    color: Colors.grey,
                    onTap: () => widget.onToggleVersion(false),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Small toggle button ────────────────────────────────────────────────────

class _VersionToggleButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final Color color;
  final VoidCallback onTap;

  const _VersionToggleButton({
    required this.label,
    required this.icon,
    required this.active,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
        decoration: BoxDecoration(
          color: active ? color.withOpacity(0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: active ? color : Colors.grey.shade300,
            width: active ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: active ? color : Colors.grey),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: active ? FontWeight.bold : FontWeight.normal,
                  color: active ? color : Colors.grey,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}