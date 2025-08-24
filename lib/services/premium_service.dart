import 'package:shared_preferences/shared_preferences.dart';
import 'database_service.dart';
import 'auth_service.dart';

class PremiumService {
  static const int FREE_DAILY_SCANS = 3;
  static const String SCAN_COUNT_KEY = 'daily_scan_count';
  static const String LAST_SCAN_DATE_KEY = 'last_scan_date';

  // Check if user is premium
  static Future<bool> isPremiumUser() async {
    if (!AuthService.isLoggedIn) return false;

    try {
      final profile = await DatabaseService.getUserProfile();
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
  static Future<void> setPremiumStatus(bool isPremium) async {
    await DatabaseService.setPremiumStatus(isPremium);
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




// ==================================================
// 3. UPDATED DATABASE SERVICE - ADD MISSING METHODS
// ==================================================

// ADD THESE METHODS TO YOUR EXISTING database_service.dart:

/*
Add these methods to your existing DatabaseService class:

  
*/

// ==================================================
// 4. CREATE MISSING WIDGET FILES
// ==================================================

// lib/widgets/scan_button_with_restriction.dart


// ==================================================
// 5. UPDATED MAIN.dart - FIX ROUTE CONSISTENCY
// ==================================================

// Replace your main.dart with this corrected version:



// ==================================================
// 6. UPDATED LOGIN PAGE - INTEGRATE WITH AUTH SERVICE
// ==================================================

// Update your login.dart with better integration:


// ==================================================
// 8. DIRECTORY STRUCTURE
// ==================================================

/*
Your final directory structure should be:

lib/
├── main.dart
├── home_screen.dart
├── purchase_screen.dart  
├── login.dart
├── premium_screen.dart
├── profile_screen.dart
├── barcode_utils.dart
├── contact_screen.dart
├── liverhealthbar.dart
├── logger.dart
├── user_manager.dart
├── services/
│   ├── auth_service.dart          (CREATE THIS)
│   ├── premium_service.dart       (CREATE THIS) 
│   └── database_service.dart      (UPDATE EXISTING)
├── widgets/
│   ├── app_drawer.dart
│   ├── scan_button_with_restriction.dart  (CREATE THIS)
│   └── recipe_with_restriction.dart
└── pages/
│   ├── grocery_list_page.dart
│   └── submit_recipe_page.dart
└── models/
│       ├── favorite_recipe.dart
│       ├── grocery_item.dart
│       └── submitted_recipe.dart
*/