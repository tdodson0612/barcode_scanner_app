// lib/services/liver_features_service.dart
// All Supabase API calls for liver-specific features.
// Uses the same DatabaseServiceCore pattern already in the app.
// Drop this into lib/services/ — no existing file is touched.

import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_config.dart';
import '../services/database_service_core.dart';
import '../models/liver_models.dart';

class LiverFeaturesService {
  static final SupabaseClient _supabase = Supabase.instance.client;

  // ------------------------------------------------------------------
  // AUTH HELPER
  // ------------------------------------------------------------------

  static String get _uid {
    final id = DatabaseServiceCore.currentUserId;
    if (id == null) throw Exception('Please sign in to continue');
    return id;
  }

  // ==================================================================
  // HYDRATION
  // ==================================================================

  /// Log a hydration entry for today
  static Future<HydrationEntry> logHydration({
    required double cups,
    String? notes,
    DateTime? at,
  }) async {
    final uid = _uid;
    final data = HydrationEntry(
      userId: uid,
      loggedAt: at ?? DateTime.now(),
      cups: cups,
      notes: notes,
    ).toJson();

    final result = await _supabase
        .from('liver_hydration_log')
        .insert(data)
        .select()
        .single();

    AppConfig.debugPrint('💧 Hydration logged: ${cups} cups');
    return HydrationEntry.fromJson(result);
  }

  /// Get all hydration entries for a date range (defaults: last 7 days)
  static Future<List<HydrationEntry>> getHydrationLog({
    DateTime? from,
    DateTime? to,
  }) async {
    final uid = _uid;
    final fromDate = from ?? DateTime.now().subtract(const Duration(days: 7));
    final toDate = to ?? DateTime.now().add(const Duration(days: 1));

    final results = await _supabase
        .from('liver_hydration_log')
        .select()
        .eq('user_id', uid)
        .gte('logged_at', fromDate.toIso8601String())
        .lte('logged_at', toDate.toIso8601String())
        .order('logged_at', ascending: false);

    return (results as List)
        .map((r) => HydrationEntry.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  /// Total cups logged on a specific calendar date (YYYY-MM-DD)
  static Future<double> getTodayCups(String date) async {
    final uid = _uid;
    final start = DateTime.parse(date);
    final end = start.add(const Duration(days: 1));

    final results = await _supabase
        .from('liver_hydration_log')
        .select('cups')
        .eq('user_id', uid)
        .gte('logged_at', start.toIso8601String())
        .lt('logged_at', end.toIso8601String());

    return (results as List)
        .fold<double>(0.0, (sum, r) => sum + ((r['cups'] as num).toDouble()));
  }

  /// Delete a hydration entry by id
  static Future<void> deleteHydrationEntry(String id) async {
    await _supabase
        .from('liver_hydration_log')
        .delete()
        .eq('id', id)
        .eq('user_id', _uid);
    AppConfig.debugPrint('🗑️ Hydration entry deleted: $id');
  }

  // ==================================================================
  // SUPPLEMENT SCHEDULE
  // ==================================================================

  /// Fetch all active supplement schedules for this user
  static Future<List<SupplementSchedule>> getSupplementSchedules() async {
    final uid = _uid;
    final results = await _supabase
        .from('liver_supplement_schedule')
        .select()
        .eq('user_id', uid)
        .eq('is_active', true)
        .order('created_at', ascending: true);

    return (results as List)
        .map((r) => SupplementSchedule.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  /// Create a new supplement schedule
  static Future<SupplementSchedule> createSupplementSchedule(
      SupplementSchedule schedule) async {
    final result = await _supabase
        .from('liver_supplement_schedule')
        .insert(schedule.toJson())
        .select()
        .single();
    AppConfig.debugPrint('💊 Supplement schedule created: ${schedule.name}');
    return SupplementSchedule.fromJson(result);
  }

  /// Update an existing supplement schedule
  static Future<void> updateSupplementSchedule(
      SupplementSchedule schedule) async {
    if (schedule.id == null) throw Exception('Schedule id is required');
    await _supabase
        .from('liver_supplement_schedule')
        .update(schedule.toJson())
        .eq('id', schedule.id!)
        .eq('user_id', _uid);
    AppConfig.debugPrint('✅ Supplement schedule updated: ${schedule.name}');
  }

  /// Soft-delete (deactivate) a supplement schedule
  static Future<void> deactivateSupplementSchedule(String scheduleId) async {
    await _supabase
        .from('liver_supplement_schedule')
        .update({'is_active': false, 'updated_at': DateTime.now().toIso8601String()})
        .eq('id', scheduleId)
        .eq('user_id', _uid);
    AppConfig.debugPrint('🔕 Supplement schedule deactivated: $scheduleId');
  }

  // ==================================================================
  // SUPPLEMENT TAKEN LOG
  // ==================================================================

  /// Mark a supplement as taken
  static Future<SupplementTakenEntry> logSupplementTaken({
    required String name,
    required String dose,
    String? scheduleId,
    String? notes,
    DateTime? at,
  }) async {
    final uid = _uid;
    final entry = SupplementTakenEntry(
      userId: uid,
      name: name,
      dose: dose,
      scheduleId: scheduleId,
      takenAt: at ?? DateTime.now(),
      notes: notes,
    );

    final result = await _supabase
        .from('liver_supplement_taken_log')
        .insert(entry.toJson())
        .select()
        .single();

    AppConfig.debugPrint('✅ Supplement taken logged: $name $dose');
    return SupplementTakenEntry.fromJson(result);
  }

  /// Get supplement taken log for a date range
  static Future<List<SupplementTakenEntry>> getSupplementTakenLog({
    DateTime? from,
    DateTime? to,
  }) async {
    final uid = _uid;
    final fromDate = from ?? DateTime.now().subtract(const Duration(days: 7));
    final toDate = to ?? DateTime.now().add(const Duration(days: 1));

    final results = await _supabase
        .from('liver_supplement_taken_log')
        .select()
        .eq('user_id', uid)
        .gte('taken_at', fromDate.toIso8601String())
        .lte('taken_at', toDate.toIso8601String())
        .order('taken_at', ascending: false);

    return (results as List)
        .map((r) => SupplementTakenEntry.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  // ==================================================================
  // SYMPTOM LOG
  // ==================================================================

  /// Log a symptom
  static Future<SymptomEntry> logSymptom({
    required SymptomType symptomType,
    required int severity,
    String? notes,
    DateTime? at,
  }) async {
    final uid = _uid;
    final entry = SymptomEntry(
      userId: uid,
      loggedAt: at ?? DateTime.now(),
      symptomType: symptomType,
      severity: severity,
      notes: notes,
    );

    final result = await _supabase
        .from('liver_symptom_log')
        .insert(entry.toJson())
        .select()
        .single();

    AppConfig.debugPrint('🩺 Symptom logged: ${symptomType.name} (${severity}/5)');
    return SymptomEntry.fromJson(result);
  }

  /// Get symptom log for a date range
  static Future<List<SymptomEntry>> getSymptomLog({
    DateTime? from,
    DateTime? to,
    SymptomType? filterType,
  }) async {
    final uid = _uid;
    final fromDate = from ?? DateTime.now().subtract(const Duration(days: 30));
    final toDate = to ?? DateTime.now().add(const Duration(days: 1));

    var query = _supabase
        .from('liver_symptom_log')
        .select()
        .eq('user_id', uid)
        .gte('logged_at', fromDate.toIso8601String())
        .lte('logged_at', toDate.toIso8601String());

    if (filterType != null) {
      query = query.eq('symptom_type', filterType.name);
    }

    final results = await query.order('logged_at', ascending: false);

    return (results as List)
        .map((r) => SymptomEntry.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  /// Delete a symptom entry
  static Future<void> deleteSymptomEntry(String id) async {
    await _supabase
        .from('liver_symptom_log')
        .delete()
        .eq('id', id)
        .eq('user_id', _uid);
    AppConfig.debugPrint('🗑️ Symptom entry deleted: $id');
  }

  // ==================================================================
  // WEEKLY GOALS
  // ==================================================================

  /// Get the current week's goals (week starting on Monday)
  static Future<LiverWeeklyGoal?> getCurrentWeekGoal() async {
    final uid = _uid;
    final monday = _getMondayOfCurrentWeek();
    final dateStr = monday.toIso8601String().split('T').first;

    final results = await _supabase
        .from('liver_weekly_goals')
        .select()
        .eq('user_id', uid)
        .eq('week_start_date', dateStr)
        .maybeSingle();

    if (results == null) return null;
    return LiverWeeklyGoal.fromJson(results);
  }

  /// Upsert weekly goals (insert or update for the current week)
  static Future<LiverWeeklyGoal> saveWeeklyGoal(LiverWeeklyGoal goal) async {
    final result = await _supabase
        .from('liver_weekly_goals')
        .upsert(goal.toJson(), onConflict: 'user_id,week_start_date')
        .select()
        .single();
    AppConfig.debugPrint('✅ Weekly goal saved');
    return LiverWeeklyGoal.fromJson(result);
  }

  // ==================================================================
  // NUTRIENT DAILY SNAPSHOT
  // ==================================================================

  /// Upsert a daily nutrient snapshot (called from TrackerPage on save)
  static Future<void> syncDailySnapshot(LiverNutrientSnapshot snapshot) async {
    await _supabase
        .from('liver_nutrient_daily')
        .upsert(snapshot.toJson(), onConflict: 'user_id,snapshot_date');
    AppConfig.debugPrint('📊 Daily snapshot synced for ${snapshot.snapshotDate}');
  }

  /// Fetch last N days of snapshots for dashboard charts
  static Future<List<LiverNutrientSnapshot>> getDailySnapshots({
    int days = 30,
  }) async {
    final uid = _uid;
    final fromDate = DateTime.now().subtract(Duration(days: days));

    final results = await _supabase
        .from('liver_nutrient_daily')
        .select()
        .eq('user_id', uid)
        .gte('snapshot_date', fromDate.toIso8601String().split('T').first)
        .order('snapshot_date', ascending: true);

    return (results as List)
        .map((r) => LiverNutrientSnapshot.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  // ==================================================================
  // PRIVATE HELPERS
  // ==================================================================

  static DateTime _getMondayOfCurrentWeek() {
    final now = DateTime.now();
    // weekday: 1=Mon … 7=Sun
    return now.subtract(Duration(days: now.weekday - 1));
  }
}