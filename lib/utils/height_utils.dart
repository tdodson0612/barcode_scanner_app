// lib/utils/height_utils.dart

class HeightUtils {
  // ========================================
  // CONVERSION
  // ========================================

  /// Convert centimeters to feet and inches map
  static Map<String, int> cmToFeetInches(double cm) {
    final totalInches = cm / 2.54;
    final feet = totalInches ~/ 12;
    final inches = (totalInches % 12).round();
    // Handle edge case where rounding pushes inches to 12
    if (inches == 12) {
      return {'feet': feet + 1, 'inches': 0};
    }
    return {'feet': feet, 'inches': inches};
  }

  /// Convert feet and inches to centimeters
  static double feetInchesToCm(int feet, int inches) {
    final totalInches = (feet * 12) + inches;
    return totalInches * 2.54;
  }

  // ========================================
  // FORMATTING
  // ========================================

  /// Format a height in cm for display, respecting unit preference
  static String formatHeight(double cm, String unitPreference) {
    if (unitPreference == 'imperial') {
      final parts = cmToFeetInches(cm);
      return "${parts['feet']}' ${parts['inches']}\"";
    } else {
      return '${cm.toStringAsFixed(0)} cm';
    }
  }

  /// Get a hint string for the common height range in the given system
  static String getCommonHeightRange(String unitPreference) {
    if (unitPreference == 'imperial') {
      return 'Common range: 4\'10\" – 6\'6\"';
    } else {
      return 'Common range: 147 – 198 cm';
    }
  }

  // ========================================
  // VALIDATION
  // ========================================

  /// Returns true if the height (in cm) is within a plausible human range
  static bool isValidHeight(double cm) {
    return cm >= 50 && cm <= 250;
  }
}