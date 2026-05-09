// lib/services/alcohol_service.dart
// Supabase CRUD + weekly analytics for alcohol tracking.
// Drop into lib/services/ — nothing existing is modified.

import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_config.dart';
import '../models/alcohol_entry.dart';

class AlcoholService {
  static final SupabaseClient _supabase = Supabase.instance.client;

  static String get _uid {
    final id = _supabase.auth.currentUser?.id;
    if (id == null) throw Exception('Please sign in to continue');
    return id;
  }

  // ── Log a drink ───────────────────────────────────────────────────────────

  static Future<AlcoholEntry> logDrink({
    required String drinkName,
    required double totalVolumeOz,
    required double abvPercent,
    String? notes,
    DateTime? at,
  }) async {
    final uid = _uid;
    final entry = AlcoholEntry(
      userId: uid,
      loggedAt: at ?? DateTime.now(),
      drinkName: drinkName,
      totalVolumeOz: totalVolumeOz,
      abvPercent: abvPercent,
      notes: notes,
    );

    final result = await _supabase
        .from('liver_alcohol_log')
        .insert(entry.toJson())
        .select()
        .single();

    AppConfig.debugPrint(
        '🍺 Drink logged: $drinkName '
        '${totalVolumeOz}oz @ $abvPercent% = '
        '${entry.pureAlcoholOz.toStringAsFixed(2)}oz pure alcohol');

    return AlcoholEntry.fromJson(result);
  }

  // ── Fetch entries ─────────────────────────────────────────────────────────

  static Future<List<AlcoholEntry>> getLog({
    DateTime? from,
    DateTime? to,
  }) async {
    final uid = _uid;
    final fromDate = from ?? DateTime.now().subtract(const Duration(days: 30));
    final toDate = to ?? DateTime.now().add(const Duration(days: 1));

    final results = await _supabase
        .from('liver_alcohol_log')
        .select()
        .eq('user_id', uid)
        .gte('logged_at', fromDate.toIso8601String())
        .lte('logged_at', toDate.toIso8601String())
        .order('logged_at', ascending: false);

    return (results as List)
        .map((r) => AlcoholEntry.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  static Future<List<AlcoholEntry>> getTodayLog() async {
    final today = DateTime.now();
    return getLog(
      from: DateTime(today.year, today.month, today.day),
      to: DateTime(today.year, today.month, today.day + 1),
    );
  }

  // ── Delete ────────────────────────────────────────────────────────────────

  static Future<void> deleteEntry(String id) async {
    await _supabase
        .from('liver_alcohol_log')
        .delete()
        .eq('id', id)
        .eq('user_id', _uid);
    AppConfig.debugPrint('🗑️ Alcohol entry deleted: $id');
  }

  // ── Weekly analytics ──────────────────────────────────────────────────────

  /// Returns a map of date-string → total pure alcohol oz for each of the
  /// last 7 days. Days with no entries will still appear with value 0.
  static Future<Map<String, double>> getWeeklyPureAlcoholOz() async {
    final entries = await getLog(
      from: DateTime.now().subtract(const Duration(days: 6)),
    );

    final result = <String, double>{};

    // Pre-fill all 7 days with 0
    for (int i = 6; i >= 0; i--) {
      final d = DateTime.now().subtract(Duration(days: i));
      result[_dateKey(d)] = 0;
    }

    for (final e in entries) {
      final key = _dateKey(e.loggedAt);
      if (result.containsKey(key)) {
        result[key] = (result[key] ?? 0) + e.pureAlcoholOz;
      }
    }

    return result;
  }

  /// Total pure alcohol oz consumed in the last 7 days
  static Future<double> getWeeklyTotalOz() async {
    final map = await getWeeklyPureAlcoholOz();
    return map.values.fold<double>(0.0, (double a, double b) => a + b);
  }

  /// Average pure alcohol oz per day over the last 7 days
  static Future<double> getWeeklyAverageDailyOz() async {
    final total = await getWeeklyTotalOz();
    return total / 7;
  }

  /// Total standard drinks in the last 7 days
  static Future<double> getWeeklyStandardDrinks() async {
    final oz = await getWeeklyTotalOz();
    return oz / 0.6;
  }

  // ── Risk classification ───────────────────────────────────────────────────

  /// NIAAA guidelines for low-risk drinking
  /// Men:   ≤4 standard drinks/day, ≤14/week
  /// Women: ≤3 standard drinks/day, ≤7/week
  /// For liver health we apply the stricter women's guideline regardless of
  /// self-reported sex since this is a liver-focused app.
  static AlcoholRiskLevel weeklyRiskLevel(double weeklyStandardDrinks) {
    if (weeklyStandardDrinks == 0) return AlcoholRiskLevel.none;
    if (weeklyStandardDrinks <= 7) return AlcoholRiskLevel.low;
    if (weeklyStandardDrinks <= 14) return AlcoholRiskLevel.moderate;
    return AlcoholRiskLevel.high;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

enum AlcoholRiskLevel { none, low, moderate, high }

extension AlcoholRiskLevelX on AlcoholRiskLevel {
  String get label => switch (this) {
        AlcoholRiskLevel.none => 'None this week 🌿',
        AlcoholRiskLevel.low => 'Low risk',
        AlcoholRiskLevel.moderate => 'Moderate — worth watching',
        AlcoholRiskLevel.high => 'High — liver stress risk',
      };

  String get emoji => switch (this) {
        AlcoholRiskLevel.none => '🌿',
        AlcoholRiskLevel.low => '✅',
        AlcoholRiskLevel.moderate => '⚠️',
        AlcoholRiskLevel.high => '🚨',
      };

  // ignore: deprecated_member_use
  int get colorValue => switch (this) {
        AlcoholRiskLevel.none => 0xFF2E7D32,     // green.shade800
        AlcoholRiskLevel.low => 0xFF388E3C,      // green.shade700
        AlcoholRiskLevel.moderate => 0xFFF57C00, // orange.shade800
        AlcoholRiskLevel.high => 0xFFC62828,     // red.shade800
      };
}