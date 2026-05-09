// lib/utils/format_utils.dart
// Shared formatting utilities for recipe content.
// Extracted from SubmitRecipePage._ingredientsToPlainText() so all
// callers — including LoRA output injection — use one canonical path.
//
// LORA_INTEGRATION_POINT: All LoRA-generated recipe outputs must pass
// ingredientsToDisplayString() before being handed to RecipeDetailPage,
// CookbookRecipe, or any widget that expects a plain-text ingredient string.
//
// iOS 14 Compatible | Production Ready

class FormatUtils {
  FormatUtils._(); // Prevent instantiation

  // ── Ingredient serialization ─────────────────────────────────────────────

  /// Convert a structured ingredient list (from SubmitRecipePage / LoRA output)
  /// into the plain-text newline-separated string expected by RecipeDetailPage,
  /// CookbookRecipe.ingredients, and SubmittedRecipe.ingredients.
  ///
  /// Each element in [ingredientRows] must be a Map with keys:
  ///   'quantity'          — String (e.g. "2")
  ///   'measurement'       — String (e.g. "cups") or "other"
  ///   'customMeasurement' — String? (used when measurement == "other")
  ///   'name'              — String (e.g. "broccoli florets")
  ///
  /// Returns a newline-joined string, e.g.:
  ///   "2 cups broccoli florets\n1 tbsp olive oil"
  static String ingredientsToDisplayString(
      List<Map<String, dynamic>> ingredientRows) {
    return ingredientRows
        .map((row) {
          final qty = (row['quantity'] as String? ?? '').trim();
          final rawMeasurement = (row['measurement'] as String? ?? '').trim();
          final measurement = rawMeasurement == 'other'
              ? (row['customMeasurement'] as String? ?? '').trim()
              : rawMeasurement;
          final name = (row['name'] as String? ?? '').trim();

          final parts = [qty, measurement, name]
              .where((p) => p.isNotEmpty)
              .join(' ');
          return parts;
        })
        .where((line) => line.isNotEmpty)
        .join('\n');
  }

  /// Parse a plain-text ingredient string back into structured rows.
  /// Used when editing an existing recipe that was stored as plain text.
  ///
  /// Attempts to split each line into quantity / measurement / name.
  /// Falls back gracefully — worst case, the full line becomes the name.
  static List<Map<String, dynamic>> ingredientsFromDisplayString(
      String plainText) {
    final lines = plainText
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    return lines.map((line) {
      final parts = line.split(RegExp(r'\s+'));

      // Try to detect a leading number as quantity
      String quantity = '';
      String measurement = '';
      String name = line;

      if (parts.isNotEmpty && _isNumeric(parts[0])) {
        quantity = parts[0];
        if (parts.length > 2 && _isKnownMeasurement(parts[1])) {
          measurement = parts[1];
          name = parts.sublist(2).join(' ');
        } else if (parts.length > 1) {
          name = parts.sublist(1).join(' ');
        }
      }

      return {
        'quantity': quantity,
        'measurement': measurement,
        'customMeasurement': '',
        'name': name,
      };
    }).toList();
  }

  // ── Directions formatting ────────────────────────────────────────────────

  /// Normalize directions from LoRA output or user input.
  /// Ensures each step starts with "N. " format and uses \n as separator.
  static String normalizeDirections(String raw) {
    if (raw.trim().isEmpty) return raw;

    // Already has numbered steps — normalize spacing only
    final lines = raw
        .split(RegExp(r'\n|(?=\d+\.)'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    // Re-number if needed
    bool alreadyNumbered = lines.every((l) => RegExp(r'^\d+\.').hasMatch(l));
    if (alreadyNumbered) {
      return lines.join('\n');
    }

    // Add numbering
    return lines
        .asMap()
        .entries
        .map((e) => '${e.key + 1}. ${e.value}')
        .join('\n');
  }

  // ── Nutrition display helpers ────────────────────────────────────────────

  /// Format a nutrient value for display.
  /// Whole numbers show without decimal; fractional values show 1 decimal.
  static String formatNutrientValue(double value, {String unit = 'g'}) {
    if (value == value.roundToDouble()) {
      return '${value.toInt()}$unit';
    }
    return '${value.toStringAsFixed(1)}$unit';
  }

  /// Format calories (always whole number, no unit suffix).
  static String formatCalories(double calories) {
    return calories.toInt().toString();
  }

  // ── Private helpers ──────────────────────────────────────────────────────

  static bool _isNumeric(String s) {
    // Matches integers and simple fractions like "1/2"
    return RegExp(r'^\d+([./]\d+)?$').hasMatch(s);
  }

  static const _knownMeasurements = {
    'tsp', 'tbsp', 'cup', 'cups', 'oz', 'lb', 'lbs', 'g', 'kg',
    'ml', 'l', 'pinch', 'dash', 'clove', 'cloves', 'slice', 'slices',
    'piece', 'pieces', 'can', 'cans', 'pkg', 'package',
  };

  static bool _isKnownMeasurement(String s) {
    return _knownMeasurements.contains(s.toLowerCase());
  }
}