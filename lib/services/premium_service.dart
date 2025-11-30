// lib/services/premium_service.dart

import 'package:shared_preferences/shared_preferences.dart';

import 'auth_service.dart';
import 'profile_service.dart';          // NEW: replaces DatabaseService
import 'database_service_core.dart';    // For workerQuery when updating DB (via ProfileService indirectly)

class PremiumService {
  static const int FREE_DAILY_SCANS = 3;
  static const String SCAN_COUNT_KEY = 'daily_scan_count';
  static const String LAST_SCAN_DATE_KEY = 'last_scan_date';

  // ==================================================
  // CHECK IF USER IS PREMIUM
  // ==================================================
  static Future<bool> isPremiumUser() async {
    if (!AuthService.isLoggedIn) return false;

    try {
      final profile = await ProfileService.getUserProfile(AuthService.currentUserId!);

      return profile?['is_premium'] ?? false;
    } catch (e) {
      print('Error checking premium status: $e');
      return false;
    }
  }

  // ==================================================
  // CHECK ACCESS TO PREMIUM FEATURES
  // ==================================================
  static Future<bool> canAccessPremiumFeature() async {
    return await isPremiumUser();
  }

  // ==================================================
  // SET PREMIUM STATUS
  // ==================================================
  static Future<void> setPremiumStatus(bool isPremium) async {
    if (!AuthService.isLoggedIn) {
      throw Exception('User must be logged in to set premium status');
    }

    await ProfileService.setPremiumStatus(AuthService.currentUserId!, isPremium);
  }

  // ==================================================
  // REMAINING SCAN COUNT FOR FREE USERS
  // ==================================================
  static Future<int> getRemainingScanCount() async {
    final isPremium = await isPremiumUser();
    if (isPremium) return -1; // Unlimited

    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().split('T')[0];
    final lastScanDate = prefs.getString(LAST_SCAN_DATE_KEY) ?? '';
    final currentCount = prefs.getInt(SCAN_COUNT_KEY) ?? 0;

    if (lastScanDate != today) {
      // Reset count for new day
      await prefs.setString(LAST_SCAN_DATE_KEY, today);
      await prefs.setInt(SCAN_COUNT_KEY, 0);
      return FREE_DAILY_SCANS;
    }

    return FREE_DAILY_SCANS - currentCount;
  }

  // ==================================================
  // USE A SCAN (INCREMENT)
  // ==================================================
  static Future<bool> useScan() async {
    final isPremium = await isPremiumUser();
    if (isPremium) return true; // Unlimited scans

    final remaining = await getRemainingScanCount();
    if (remaining <= 0) return false;

    final prefs = await SharedPreferences.getInstance();
    final currentCount = prefs.getInt(SCAN_COUNT_KEY) ?? 0;
    await prefs.setInt(SCAN_COUNT_KEY, currentCount + 1);
    return true;
  }

  // Backward compatibility
  static Future<bool> incrementScanCount() async => await useScan();
}
