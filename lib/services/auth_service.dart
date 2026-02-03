// lib/services/auth_service.dart - FIXED FOR iOS APP REVIEW
// ✅ iOS-specific FCM handling (skips FCM on iOS completely)
// ✅ Increased timeout from 15s → 30s for iPad compatibility
// ✅ Optimized database calls during login

import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_config.dart';

// ✅ NEW: Replaces ProfileService imports
import 'profile_data_access.dart';

// KEEP: Database service + FCM
import 'database_service_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class AuthService {
  static final SupabaseClient _supabase = Supabase.instance.client;

  static const List<String> _premiumEmails = [
    'terryd0612@gmail.com',
    'liverdiseasescanner@gmail.com',
  ];

  static bool get isLoggedIn => _supabase.auth.currentUser != null;
  static User? get currentUser => _supabase.auth.currentUser;
  static String? get currentUserId => currentUser?.id;

  static String? get currentUsername {
    final username = currentUser?.userMetadata?['username'] as String?;
    if (username != null) return username;
    return null;
  }

  static void ensureLoggedIn() {
    if (!isLoggedIn || currentUserId == null) {
      throw Exception('User must be logged in to perform this action.');
    }
  }

  // --------------------------------------------------------
  // FETCH CURRENT USERNAME
  // --------------------------------------------------------
  static Future<String?> fetchCurrentUsername() async {
    if (currentUserId == null) return null;

    try {
      final profile = await ProfileDataAccess.getUserProfile(currentUserId!);
      return profile?['username'] as String?;
    } catch (e) {
      AppConfig.debugPrint('Error fetching username: $e');
      return null;
    }
  }

  static Stream<AuthState> get authStateChanges =>
      _supabase.auth.onAuthStateChange;

  static bool _isDefaultPremiumEmail(String email) {
    final normalizedEmail = email.trim().toLowerCase();
    return _premiumEmails.contains(normalizedEmail);
  }

  // --------------------------------------------------------
  // 🔥 iOS-AWARE FCM TOKEN HANDLER (NON-BLOCKING)
  // --------------------------------------------------------
  /// Only runs on Android - iOS FCM is disabled in main.dart
  static Future<void> _saveFcmTokenIfAndroid(String userId) async {
    // ✅ CRITICAL FIX: Skip FCM entirely on iOS to match main.dart
    if (kIsWeb || Platform.isIOS) {
      AppConfig.debugPrint("ℹ️ Skipping FCM on iOS (disabled in main.dart)");
      return;
    }

    // Android only from here
    try {
      final token = await FirebaseMessaging.instance.getToken();

      if (token == null) {
        AppConfig.debugPrint("⚠️ FCM token is null (Android), skipping save.");
        return;
      }

      AppConfig.debugPrint("📱 Saving FCM token (Android): ${token.substring(0, 20)}...");

      await DatabaseServiceCore.workerQuery(
        action: 'update',
        table: 'user_profiles',
        filters: {'id': userId},
        data: {
          'fcm_token': token,
          'updated_at': DateTime.now().toIso8601String(),
        },
      );
      
      AppConfig.debugPrint("✅ FCM token saved successfully (Android)");
    } catch (e) {
      // ✅ CRITICAL: Don't throw - just log and continue
      AppConfig.debugPrint("⚠️ Failed to save FCM token (non-critical): $e");
      // App continues to work without push notifications
    }
  }

  /// Listen for FCM token refresh (Android only)
  static void _listenForFcmTokenRefreshIfAndroid(String userId) {
    // ✅ CRITICAL FIX: Skip FCM entirely on iOS
    if (kIsWeb || Platform.isIOS) {
      return;
    }

    // Android only from here
    try {
      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
        AppConfig.debugPrint("🔄 FCM token refreshed (Android): ${newToken.substring(0, 20)}...");

        try {
          await DatabaseServiceCore.workerQuery(
            action: 'update',
            table: 'user_profiles',
            filters: {'id': userId},
            data: {
              'fcm_token': newToken,
              'updated_at': DateTime.now().toIso8601String(),
            },
          );
          AppConfig.debugPrint("✅ Refreshed FCM token saved (Android)");
        } catch (e) {
          AppConfig.debugPrint("⚠️ Failed to save refreshed FCM token: $e");
        }
      });
    } catch (e) {
      AppConfig.debugPrint("⚠️ FCM token refresh listener failed: $e");
    }
  }

  // --------------------------------------------------------
  // SIGN UP
  // --------------------------------------------------------
  static Future<AuthResponse> signUp({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _supabase.auth.signUp(
        email: email,
        password: password,
      );

      if (response.user != null) {
        final normalizedEmail = email.trim().toLowerCase();
        final isPremium = _isDefaultPremiumEmail(normalizedEmail);
        final userId = response.user!.id;

        await Future.delayed(const Duration(seconds: 1));

        try {
          await ProfileDataAccess.createUserProfile(
            userId,
            email,
            isPremium: isPremium,
          );

          AppConfig.debugPrint('✅ Profile created during signup');
        } catch (profileError) {
          AppConfig.debugPrint('⚠️ Profile creation failed: $profileError');

          throw Exception(
              'Signup succeeded but profile setup failed. Please sign in.');
        }

        // 🔥 Save FCM token after profile creation (Android only, NON-BLOCKING)
        _saveFcmTokenIfAndroid(userId).catchError((error) {
          AppConfig.debugPrint("⚠️ FCM token save failed (continuing anyway): $error");
        });

        // 🔄 Listen for token refresh (Android only, also non-blocking)
        _listenForFcmTokenRefreshIfAndroid(userId);
      }

      return response;
    } catch (e) {
      throw Exception('Sign up failed: $e');
    }
  }

  // --------------------------------------------------------
  // 🔥 SIGN IN (FIXED: iOS-compatible, better timeout, optimized)
  // --------------------------------------------------------
  static Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    const maxRetries = 3;
    int attempt = 0;

    while (attempt < maxRetries) {
      attempt++;
      
      try {
        AppConfig.debugPrint('🔐 Login attempt $attempt/$maxRetries for: ${email.trim().toLowerCase()}');

        // Always clear session before attempting login (iOS fix)
        try {
          final currentSession = _supabase.auth.currentSession;
          if (currentSession != null) {
            AppConfig.debugPrint('🧹 Clearing existing session before login (attempt $attempt)');
            await _supabase.auth.signOut();
            await Future.delayed(const Duration(milliseconds: 500));
          }
        } catch (clearError) {
          AppConfig.debugPrint('⚠️ Session clear failed (continuing): $clearError');
        }

        // ✅ FIX: Increased timeout from 15s → 30s for iPad compatibility
        final response = await _supabase.auth.signInWithPassword(
          email: email,
          password: password,
        ).timeout(
          const Duration(seconds: 30), // ← INCREASED FROM 15s
          onTimeout: () {
            throw Exception('Connection timed out. Please check your internet and try again.');
          },
        );

        // ✅ SUCCESS PATH
        if (response.user != null && response.session != null) {
          final userId = response.user!.id;
          final normalizedEmail = email.trim().toLowerCase();

          AppConfig.debugPrint('✅ Login successful (attempt $attempt): $userId');

          // ✅ OPTIMIZED: Single combined profile check + setup
          try {
            await _ensureUserProfileExistsOptimized(userId, email, normalizedEmail);
          } catch (profileError) {
            AppConfig.debugPrint('⚠️ Profile setup failed (non-critical): $profileError');
            // Continue anyway - user can still use the app
          }

          // ✅ Save FCM token (Android only, non-blocking)
          _saveFcmTokenIfAndroid(userId).catchError((error) {
            AppConfig.debugPrint("⚠️ FCM token save failed: $error");
          });

          _listenForFcmTokenRefreshIfAndroid(userId);

          return response; // ✅ SUCCESS - Return immediately
        }

        // If we got here, login returned but no user/session
        throw Exception('Login failed: No user or session returned');

      } catch (e) {
        final errorStr = e.toString().toLowerCase();
        
        AppConfig.debugPrint('❌ Login attempt $attempt failed: $e');

        // 🍎 iOS-SPECIFIC: Session conflict errors - retry
        final isSessionError = errorStr.contains('session') ||
                            errorStr.contains('expired') ||
                            errorStr.contains('invalid_grant') ||
                            errorStr.contains('refresh_token') ||
                            errorStr.contains('jwt');

        if (isSessionError && attempt < maxRetries) {
          AppConfig.debugPrint('🔄 Session conflict detected, will retry (attempt ${attempt + 1}/$maxRetries)');
          await Future.delayed(Duration(milliseconds: 500 * attempt)); // Exponential backoff
          continue; // Try again
        }

        // ❌ FATAL ERRORS - Don't retry
        if (errorStr.contains('invalid login credentials') ||
            errorStr.contains('invalid email or password')) {
          throw Exception('Invalid email or password. Please try again.');
        }
        
        if (errorStr.contains('email not confirmed')) {
          throw Exception('Please verify your email before signing in.');
        }
        
        if (errorStr.contains('network') || errorStr.contains('socket')) {
          throw Exception('Network error. Please check your internet connection.');
        }

        // If we've exhausted retries, throw the error
        if (attempt >= maxRetries) {
          AppConfig.debugPrint('❌ All $maxRetries login attempts failed');
          throw Exception('Unable to sign in right now. Please try again.\nYour login might have timed out - happens to the best of us!');
        }

        // For other errors on early attempts, retry
        AppConfig.debugPrint('⚠️ Retrying login due to error: $e');
        await Future.delayed(Duration(milliseconds: 500 * attempt));
        continue;
      }
    }

    // Should never reach here, but just in case
    throw Exception('Login failed after $maxRetries attempts');
  }

  // --------------------------------------------------------
  // 🍎 FORCE RESET SESSION (for iOS troubleshooting)
  // --------------------------------------------------------
  static Future<void> forceResetSession() async {
    try {
      AppConfig.debugPrint('🧹 Force resetting all session data...');
      
      // Sign out from Supabase
      await _supabase.auth.signOut();
      
      // Clear all local caches
      await DatabaseServiceCore.clearAllUserCache();
      
      // Wait for iOS to settle
      await Future.delayed(const Duration(seconds: 1));
      
      AppConfig.debugPrint('✅ Session reset complete');
    } catch (e) {
      AppConfig.debugPrint('⚠️ Session reset error: $e');
      throw Exception('Failed to reset session: $e');
    }
  }

  // --------------------------------------------------------
  // ✅ OPTIMIZED: Combined profile check + premium setup
  // --------------------------------------------------------
  static Future<void> _ensureUserProfileExistsOptimized(
      String userId, String email, String normalizedEmail) async {
    try {
      final profile = await ProfileDataAccess.getUserProfile(userId);

      if (profile == null) {
        AppConfig.debugPrint('📝 Profile missing → creating');
        
        // Create profile with premium status in one go
        final isPremium = _isDefaultPremiumEmail(normalizedEmail);
        await ProfileDataAccess.createUserProfile(
          userId,
          email,
          isPremium: isPremium,
        );
        
        AppConfig.debugPrint('✅ Profile created on login with premium=$isPremium');
      } else {
        // Profile exists - check if premium needs updating
        final isPremium = _isDefaultPremiumEmail(normalizedEmail);
        final currentPremium = profile['is_premium'] as bool? ?? false;
        
        if (isPremium && !currentPremium) {
          AppConfig.debugPrint('⭐ Upgrading to premium');
          await ProfileDataAccess.setPremium(userId, true);
        }
        
        AppConfig.debugPrint('✅ Profile exists for user: $userId');
      }
    } catch (e) {
      AppConfig.debugPrint('❌ Profile setup failed: $e');
      // Don't rethrow - allow login to continue
    }
  }

  // --------------------------------------------------------
  // SIGN OUT
  // --------------------------------------------------------
  static Future<void> signOut() async {
    try {
      AppConfig.debugPrint('🔓 Signing out user...');
      await DatabaseServiceCore.clearAllUserCache();
      await _supabase.auth.signOut();
      AppConfig.debugPrint('✅ User signed out successfully');
    } catch (e) {
      AppConfig.debugPrint('❌ Sign out error: $e');
      throw Exception('Sign out failed: $e');
    }
  }

  // --------------------------------------------------------
  // RESET PASSWORD
  // --------------------------------------------------------
  static Future<void> resetPassword(String email) async {
    try {
      await _supabase.auth.resetPasswordForEmail(
        email,
        redirectTo: 'com.terrydodson.liverWiseApp://reset-password',
      );
      AppConfig.debugPrint('✅ Password reset email sent to: $email');
    } catch (e) {
      AppConfig.debugPrint('❌ Password reset failed: $e');
      throw Exception('Password reset failed: $e');
    }
  }

  // --------------------------------------------------------
  // UPDATE PASSWORD
  // --------------------------------------------------------
  static Future<void> updatePassword(String newPassword) async {
    if (currentUserId == null) {
      throw Exception('No user logged in');
    }

    try {
      await _supabase.auth.updateUser(
        UserAttributes(password: newPassword),
      );
      AppConfig.debugPrint('✅ Password updated for user: $currentUserId');
    } catch (e) {
      AppConfig.debugPrint('❌ Password update failed: $e');
      throw Exception('Password update failed: $e');
    }
  }

  // --------------------------------------------------------
  // RESEND VERIFICATION EMAIL
  // --------------------------------------------------------
  static Future<void> resendVerificationEmail() async {
    if (currentUser?.email == null) {
      throw Exception('No user email found');
    }

    try {
      await _supabase.auth.resend(
        type: OtpType.signup,
        email: currentUser!.email!,
      );
      AppConfig.debugPrint('✅ Verification email resent to: ${currentUser!.email}');
    } catch (e) {
      AppConfig.debugPrint('❌ Failed to resend verification email: $e');
      throw Exception('Failed to resend verification email: $e');
    }
  }

  static void ensureUserAuthenticated() {
    if (!isLoggedIn) {
      throw Exception('User must be logged in');
    }
  }

  // --------------------------------------------------------
  // ⭐ PUBLIC METHOD TO SET PREMIUM
  // --------------------------------------------------------
  static Future<void> markUserAsPremium(String userId) async {
    try {
      await ProfileDataAccess.setPremium(userId, true);

      AppConfig.debugPrint("🌟 User upgraded to premium: $userId");

      // Refresh FCM token for this user (Android only, optional)
      if (currentUserId == userId) {
        _saveFcmTokenIfAndroid(userId).catchError((error) {
          AppConfig.debugPrint("⚠️ FCM token save failed: $error");
        });
      }
    } catch (e) {
      AppConfig.debugPrint("❌ Failed to set premium status: $e");
      throw Exception("Failed to set premium status: $e");
    }
  }
}