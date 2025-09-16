import 'package:shared_preferences/shared_preferences.dart';
import 'database_service.dart';
import 'auth_service.dart';

class PremiumService {
  static const int FREE_DAILY_SCANS = 3;
  static const String SCAN_COUNT_KEY = 'daily_scan_count';
  static const String LAST_SCAN_DATE_KEY = 'last_scan_date';

  // Check if user is premium
  // Check if user is premium
  static Future<bool> isPremiumUser() async {
    if (!AuthService.isLoggedIn) return false;

    try {
      final profile = await DatabaseService.getUserProfile(AuthService.currentUserId!);
      print('DEBUG: User profile: $profile'); // Debug line
      print('DEBUG: is_premium value: ${profile?['is_premium']}'); // Debug line
      return profile?['is_premium'] ?? false;
    } catch (e) {
      print('Error checking premium status: $e');
      return false;
    }
  }

  // Check if user can access premium features
  static Future<bool> canAccessPremiumFeature() async {
    return await isPremiumUser();
  }

  // Set premium status
  // Set premium status
  static Future<void> setPremiumStatus(bool isPremium) async {
    if (!AuthService.isLoggedIn) {
      throw Exception('User must be logged in to set premium status');
    }
  
    await DatabaseService.setPremiumStatus(AuthService.currentUserId!, isPremium);
  }

  // Get remaining scan count for free users
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

  // Use a scan (increment count)
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

  // Increment scan count (alias for useScan - matches your widget's expectation)
  static Future<bool> incrementScanCount() async {
    return await useScan();
  }
}