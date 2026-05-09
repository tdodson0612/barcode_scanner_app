// lib/services/liver_snapshot_sync.dart
// Thin bridge: call LiverSnapshotSync.syncEntry(userId, entry) right after
// TrackerService.saveEntry() in your TrackerPage.
// This is the ONLY change needed in TrackerPage (one line added).
// No other existing files are modified.

import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/tracker_entry.dart';
import '../models/liver_models.dart';
import '../services/liver_features_service.dart';
import '../services/tracker_service.dart';
import '../config/app_config.dart';

class LiverSnapshotSync {
  /// Call this immediately after TrackerService.saveEntry() succeeds.
  /// It converts the local TrackerEntry to a LiverNutrientSnapshot and
  /// upserts it to Supabase so the dashboard always has up-to-date data.
  static Future<void> syncEntry(String userId, TrackerEntry entry) async {
    try {
      final totals =
          TrackerService.calculateNutritionTotals(entry.meals);

      // Parse water intake from string (e.g. "6 cups", "48 oz")
      double? waterCups;
      if (entry.waterIntake != null && entry.waterIntake!.isNotEmpty) {
        waterCups = _parseWaterCups(entry.waterIntake!);
      }

      final snapshot = LiverNutrientSnapshot(
        userId: userId,
        snapshotDate: DateTime.parse(entry.date),
        calories: totals['calories'],
        proteinG: totals['protein'],
        fatG: totals['fat'],
        saturatedFatG: totals['saturatedFat'],
        sugarG: totals['sugar'],
        sodiumMg: totals['sodium'],
        fiberG: totals['fiber'],
        waterCups: waterCups,
        dailyScore: entry.dailyScore,
        weightKg: entry.weight,
        supplementCount: entry.supplements.length,
      );

      await LiverFeaturesService.syncDailySnapshot(snapshot);
      AppConfig.debugPrint(
          '🔄 Liver snapshot synced for ${entry.date}');
    } catch (e) {
      // Non-fatal: local tracker still saved; Supabase sync is best-effort
      AppConfig.debugPrint(
          '⚠️ Liver snapshot sync failed (non-fatal): $e');
    }
  }

  static double _parseWaterCups(String water) {
    final lower = water.toLowerCase();
    if (lower.contains('oz')) {
      final match = RegExp(r'(\d+)').firstMatch(lower);
      if (match != null) {
        final oz = int.tryParse(match.group(1)!) ?? 0;
        return oz / 8.0;
      }
    }
    if (lower.contains('l') && !lower.contains('fl')) {
      final match = RegExp(r'(\d+\.?\d*)').firstMatch(lower);
      if (match != null) {
        final liters = double.tryParse(match.group(1)!) ?? 0;
        return liters * 4.23;
      }
    }
    final match = RegExp(r'(\d+\.?\d*)').firstMatch(lower);
    if (match != null) return double.tryParse(match.group(1)!) ?? 0;
    return 0;
  }
}