// lib/services/profile_data_access.dart
// Neutral data-access layer for profile reads/updates.
// Breaks circular dependency between AuthService ↔ ProfileService.
//
// 🔧 FIX: createUserProfile no longer uses requireAuth: true.
//    During signup with email confirmation enabled, there is no active
//    session at the moment profile creation is attempted, so accessToken
//    is null and the Cloudflare Worker rejects the request with an auth
//    error. The Supabase anon key + RLS policy on user_profiles is the
//    correct mechanism to secure this insert instead.
//
// 🔧 FIX 2: createUserProfile now treats a 23505 duplicate key error as
//    a success. The handle_new_user database trigger fires first and inserts
//    the profile row before the app code runs. When the app then attempts
//    its own insert, the Worker returns 409/23505. This is not an error —
//    the profile exists and the user is good to go.

import 'database_service_core.dart';

class ProfileDataAccess {
  // ==================================================
  // GET USER PROFILE
  // ==================================================
  static Future<Map<String, dynamic>?> getUserProfile(String userId) async {
    try {
      final result = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'user_profiles',
        filters: {'id': userId},
        limit: 1,
      );

      if (result == null || (result as List).isEmpty) return null;
      return result[0] as Map<String, dynamic>;
    } catch (e) {
      throw Exception('Failed to fetch user profile: $e');
    }
  }

  // ==================================================
  // CREATE USER PROFILE
  // ==================================================
  // ⚠️  requireAuth intentionally omitted (defaults to false).
  //
  //     Why: signUp() may be called before Supabase creates a session
  //     (e.g. when email confirmation is required). At that point
  //     currentSession?.accessToken is null, and passing requireAuth: true
  //     causes the Cloudflare Worker to reject the insert with a 401,
  //     which then surfaces to the user as the "Hmm, who are you?" dialog.
  //
  //     Security: The Supabase RLS INSERT policy
  //       `WITH CHECK (auth.uid() = id)`
  //     already enforces that users can only insert their own row.
  //     The anon key does not bypass RLS.
  //
  //     Duplicate handling: The handle_new_user trigger on auth.users
  //     fires before this code runs and may have already created the row.
  //     A 23505 duplicate key error means the profile already exists and
  //     is treated as success — no action needed.
  static Future<void> createUserProfile(
    String userId,
    String email, {
    required bool isPremium,
  }) async {
    try {
      await DatabaseServiceCore.workerQuery(
        action: 'insert',
        table: 'user_profiles',
        // requireAuth: false  ← default; see note above
        data: {
          'id': userId,
          'email': email,
          'is_premium': isPremium,
          'daily_scans_used': 0,
          'last_scan_date': DateTime.now().toIso8601String().split('T')[0],
          'created_at': DateTime.now().toIso8601String(),
          'username': _usernameFromEmail(email),
          'friends_list_visible': true,
          'xp': 0,
          'level': 1,
        },
      );
    } catch (e) {
      final errorStr = e.toString();

      // 23505 = duplicate key — the handle_new_user trigger already created
      // this profile row. Treat as success and return normally.
      if (errorStr.contains('23505') ||
          errorStr.contains('duplicate key') ||
          errorStr.contains('already exists')) {
        return;
      }

      throw Exception('Failed to create user profile: $e');
    }
  }

  // ==================================================
  // UPDATE PREMIUM STATUS
  // ==================================================
  static Future<void> setPremium(String userId, bool isPremium) async {
    try {
      await DatabaseServiceCore.workerQuery(
        action: 'update',
        table: 'user_profiles',
        filters: {'id': userId},
        data: {
          'is_premium': isPremium,
          'updated_at': DateTime.now().toIso8601String(),
        },
      );

      await DatabaseServiceCore.clearCache('cache_user_profile_$userId');
      await DatabaseServiceCore.clearCache('cache_profile_timestamp_$userId');
    } catch (e) {
      throw Exception('Failed to update premium status: $e');
    }
  }

  // ==================================================
  // PRIVATE HELPERS
  // ==================================================

  /// Derive a safe username from an email address.
  /// Strips everything from @ onward and removes non-alphanumeric chars.
  static String _usernameFromEmail(String email) {
    final local = email.split('@').first;
    // Keep only letters, digits, underscores; fall back to 'user' if empty
    final clean = local.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '');
    return clean.isNotEmpty ? clean : 'user';
  }
}