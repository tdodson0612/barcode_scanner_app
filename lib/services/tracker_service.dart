// lib/services/tracker_service.dart

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/tracker_entry.dart';
import '../models/disease_nutrition_profile.dart';
import '../services/auth_service.dart';
import '../config/app_config.dart';

class TrackerService {
  static const String _STORAGE_KEY_PREFIX = 'tracker_entries_';
  static const String _DISCLAIMER_KEY = 'tracker_disclaimer_accepted';

  // ========================================
  // DISCLAIMER MANAGEMENT
  // ========================================

  /// Check if user has accepted the tracker disclaimer
  static Future<bool> hasAcceptedDisclaimer() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_DISCLAIMER_KEY) ?? false;
    } catch (e) {
      AppConfig.debugPrint('Error checking disclaimer: $e');
      return false;
    }
  }

  /// Mark disclaimer as accepted
  static Future<void> acceptDisclaimer() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_DISCLAIMER_KEY, true);
      AppConfig.debugPrint('✅ Tracker disclaimer accepted');
    } catch (e) {
      AppConfig.debugPrint('❌ Error accepting disclaimer: $e');
      throw Exception('Failed to save disclaimer acceptance');
    }
  }

  // ========================================
  // STORAGE KEY MANAGEMENT
  // ========================================

  static String _getStorageKey(String userId) {
    return '$_STORAGE_KEY_PREFIX$userId';
  }

  // ========================================
  // ENTRY MANAGEMENT
  // ========================================

  /// Get all tracker entries for current user
  static Future<List<TrackerEntry>> getEntries(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _getStorageKey(userId);
      final jsonString = prefs.getString(key);

      if (jsonString == null) {
        return [];
      }

      final List<dynamic> jsonList = json.decode(jsonString);
      final entries = jsonList
          .map((json) => TrackerEntry.fromJson(json))
          .toList();

      // Sort by date descending (newest first)
      entries.sort((a, b) => b.date.compareTo(a.date));

      AppConfig.debugPrint('📋 Loaded ${entries.length} tracker entries');
      return entries;
    } catch (e) {
      AppConfig.debugPrint('❌ Error loading entries: $e');
      return [];
    }
  }

  /// Save a tracker entry
  static Future<void> saveEntry(String userId, TrackerEntry entry) async {
    try {
      final entries = await getEntries(userId);

      // Remove existing entry for this date if it exists
      entries.removeWhere((e) => e.date == entry.date);

      // Add new entry
      entries.add(entry);

      // Save back to storage
      final prefs = await SharedPreferences.getInstance();
      final key = _getStorageKey(userId);
      final jsonString = json.encode(entries.map((e) => e.toJson()).toList());
      await prefs.setString(key, jsonString);

      AppConfig.debugPrint('✅ Saved tracker entry for ${entry.date}');
    } catch (e) {
      AppConfig.debugPrint('❌ Error saving entry: $e');
      throw Exception('Failed to save tracker entry');
    }
  }

  /// Delete a tracker entry
  static Future<void> deleteEntry(String userId, String date) async {
    try {
      final entries = await getEntries(userId);
      entries.removeWhere((e) => e.date == date);

      final prefs = await SharedPreferences.getInstance();
      final key = _getStorageKey(userId);
      final jsonString = json.encode(entries.map((e) => e.toJson()).toList());
      await prefs.setString(key, jsonString);

      AppConfig.debugPrint('✅ Deleted tracker entry for $date');
    } catch (e) {
      AppConfig.debugPrint('❌ Error deleting entry: $e');
      throw Exception('Failed to delete tracker entry');
    }
  }

  /// Get entry for a specific date
  static Future<TrackerEntry?> getEntryForDate(String userId, String date) async {
    try {
      final entries = await getEntries(userId);
      return entries.firstWhere(
        (e) => e.date == date,
        orElse: () => TrackerEntry(date: date, dailyScore: 0),
      );
    } catch (e) {
      return null;
    }
  }

  // ========================================
  // SCORE CALCULATION
  // ========================================

  /// Get today's score
  static Future<int?> getTodayScore(String userId) async {
    try {
      final today = DateTime.now().toString().split(' ')[0]; // YYYY-MM-DD
      final entry = await getEntryForDate(userId, today);
      return entry?.dailyScore;
    } catch (e) {
      AppConfig.debugPrint('❌ Error getting today score: $e');
      return null;
    }
  }

  /// Get weekly average score (last 7 days)
  static Future<int?> getWeeklyScore(String userId) async {
    try {
      final entries = await getEntries(userId);
      
      if (entries.isEmpty) return null;

      // Get entries from last 7 days
      final now = DateTime.now();
      final sevenDaysAgo = now.subtract(const Duration(days: 7));
      
      final recentEntries = entries.where((entry) {
        final entryDate = DateTime.parse(entry.date);
        return entryDate.isAfter(sevenDaysAgo) && entryDate.isBefore(now.add(const Duration(days: 1)));
      }).toList();

      if (recentEntries.isEmpty) return null;

      final totalScore = recentEntries.fold<int>(
        0,
        (sum, entry) => sum + entry.dailyScore,
      );

      final average = (totalScore / recentEntries.length).round();
      
      AppConfig.debugPrint('📊 Weekly average: $average (from ${recentEntries.length} days)');
      return average;
    } catch (e) {
      AppConfig.debugPrint('❌ Error calculating weekly score: $e');
      return null;
    }
  }

  /// Calculate daily score from entry with disease-aware logic
  static int calculateDailyScore(
    TrackerEntry entry,
    String? diseaseType,
  ) {
    // Base score starts at 70 (neutral)
    int score = 70;

    // Count meals - each meal logged adds points
    final mealCount = entry.mealCount;
    score += (mealCount * 5).clamp(0, 20); // Max +20 for all meals

    // Exercise bonus: +2 per 30 minutes, max +10
    if (entry.exercise != null) {
      final exerciseMinutes = _parseExerciseMinutes(entry.exercise!);
      final exerciseBonus = ((exerciseMinutes / 30) * 2).clamp(0, 10).round();
      score += exerciseBonus;
    }

    // Water bonus: +1 per 2 cups, max +5
    if (entry.waterIntake != null) {
      final waterCups = _parseWaterCups(entry.waterIntake!);
      final waterBonus = ((waterCups / 2) * 1).clamp(0, 5).round();
      score += waterBonus;
    }

    // Clamp final score to 0-100
    return score.clamp(0, 100);
  }

  // ========================================
  // HELPER PARSERS
  // ========================================

  static int _parseExerciseMinutes(String exercise) {
    // Parse formats like "30 minutes", "1 hour", "45 min"
    final lower = exercise.toLowerCase();
    
    if (lower.contains('hour')) {
      final match = RegExp(r'(\d+\.?\d*)').firstMatch(lower);
      if (match != null) {
        final hours = double.tryParse(match.group(1)!) ?? 0;
        return (hours * 60).round();
      }
    }
    
    final match = RegExp(r'(\d+)').firstMatch(lower);
    if (match != null) {
      return int.tryParse(match.group(1)!) ?? 0;
    }
    
    return 0;
  }

  static int _parseWaterCups(String water) {
    // Parse formats like "8 cups", "64 oz"
    final lower = water.toLowerCase();
    
    if (lower.contains('oz')) {
      final match = RegExp(r'(\d+)').firstMatch(lower);
      if (match != null) {
        final oz = int.tryParse(match.group(1)!) ?? 0;
        return (oz / 8).round(); // Convert oz to cups
      }
    }
    
    final match = RegExp(r'(\d+)').firstMatch(lower);
    if (match != null) {
      return int.tryParse(match.group(1)!) ?? 0;
    }
    
    return 0;
  }

  // ========================================
  // DATA MANAGEMENT
  // ========================================

  /// Get last 7 days of entries for graph
  static Future<List<TrackerEntry>> getLastSevenDays(String userId) async {
    try {
      final entries = await getEntries(userId);
      final now = DateTime.now();
      final sevenDaysAgo = now.subtract(const Duration(days: 7));
      
      return entries.where((entry) {
        final entryDate = DateTime.parse(entry.date);
        return entryDate.isAfter(sevenDaysAgo);
      }).toList();
    } catch (e) {
      AppConfig.debugPrint('❌ Error getting last 7 days: $e');
      return [];
    }
  }

  /// Clear all tracker data (for reset/logout)
  static Future<void> clearAllData(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_getStorageKey(userId));
      AppConfig.debugPrint('✅ Cleared all tracker data');
    } catch (e) {
      AppConfig.debugPrint('❌ Error clearing tracker data: $e');
    }
  }
}