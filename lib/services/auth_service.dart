// lib/services/auth_service.dart
// ✅ Simplified login flow - no complex retry logic
// ✅ Proper session handling for iOS and Android
// ✅ Non-blocking profile setup
// ✅ FCM only on Android (iOS disabled)
// 🔧 FIX: Removed _clearExistingSession() from signIn() - was breaking
//         Android login after sign-out by calling signOut() on a null session,
//         producing a session/token error that the error handler misclassified
//         as an auth error, causing the "Hmm, who are you?" loop.

import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';

// Database access
import 'profile_data_access.dart';
import 'database_service_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class AuthService {
  static final SupabaseClient _supabase = Supabase.instance.client;

  static const List<String> _premiumEmails = [
    'terryd0612@gmail.com',
    'liverdiseasescanner@gmail.com',
  ];

  // --------------------------------------------------------
  // BASIC AUTH STATE
  // --------------------------------------------------------

  static bool get isLoggedIn => _supabase.auth.currentUser != null;
  static User? get currentUser => _supabase.auth.currentUser;
  static String? get currentUserId => currentUser?.id;

  static String? get currentUsername {
    final username = currentUser?.userMetadata?['username'] as String?;
    return username;
  }

  static Stream<AuthState> get authStateChanges =>
      _supabase.auth.onAuthStateChange;

  static void ensureLoggedIn() {
    if (!isLoggedIn || currentUserId == null) {
      throw Exception('User must be logged in to perform this action.');
    }
  }

  static void ensureUserAuthenticated() {
    if (!isLoggedIn) {
      throw Exception('User must be logged in');
    }
  }

  static bool _isDefaultPremiumEmail(String email) {
    final normalizedEmail = email.trim().toLowerCase();
    return _premiumEmails.contains(normalizedEmail);
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

  // --------------------------------------------------------
  // SIGN IN
  // --------------------------------------------------------

  static Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final normalizedEmail = email.trim().toLowerCase();

      AppConfig.debugPrint('🔐 Starting login for: $normalizedEmail');

      // NOTE: _clearExistingSession() intentionally removed here.
      // Calling signOut() before login when there is no active session
      // produces a session/token error on Android that causes the
      // "Hmm, who are you?" error loop. forceResetSession() in the UI
      // handles the edge case where a stale session needs clearing.

      AppConfig.debugPrint('🔑 Calling Supabase signIn...');

      final response = await _supabase.auth
          .signInWithPassword(
            email: normalizedEmail,
            password: password,
          )
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              throw Exception(
                  'Login timed out. Please check your connection and try again.');
            },
          );

      // Verify we got a valid session
      if (response.user == null || response.session == null) {
        throw Exception('Login failed - no session created');
      }

      final userId = response.user!.id;
      AppConfig.debugPrint('✅ Supabase login successful: $userId');

      // Setup profile (non-blocking, best effort)
      _setupProfileAfterLogin(userId, normalizedEmail).catchError((error) {
        AppConfig.debugPrint('⚠️ Profile setup failed (continuing): $error');
      });

      // Setup FCM (Android only, non-blocking)
      _setupFcmAfterLogin(userId).catchError((error) {
        AppConfig.debugPrint('⚠️ FCM setup failed (continuing): $error');
      });

      AppConfig.debugPrint('✅ Login complete, returning response');
      return response;
    } on AuthException catch (e) {
      AppConfig.debugPrint('❌ Supabase auth error: ${e.message}');
      throw _createUserFriendlyError(e);
    } catch (e) {
      AppConfig.debugPrint('❌ Login error: $e');
      throw _createUserFriendlyError(e);
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
      final normalizedEmail = email.trim().toLowerCase();

      AppConfig.debugPrint('📝 Starting signup for: $normalizedEmail');

      final response = await _supabase.auth
          .signUp(
            email: normalizedEmail,
            password: password,
          )
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              throw Exception(
                  'Signup timed out. Please check your connection and try again.');
            },
          );

      if (response.user == null) {
        throw Exception('Signup failed - no user created');
      }

      final userId = response.user!.id;
      final isPremium = _isDefaultPremiumEmail(normalizedEmail);

      AppConfig.debugPrint('✅ User created: $userId');

      // Wait a moment for Supabase to settle
      await Future.delayed(const Duration(milliseconds: 1000));

      // Create profile (blocking - needed before proceeding)
      try {
        await ProfileDataAccess.createUserProfile(
          userId,
          normalizedEmail,
          isPremium: isPremium,
        );
        AppConfig.debugPrint('✅ Profile created during signup');
      } catch (profileError) {
        AppConfig.debugPrint('❌ Profile creation failed: $profileError');
        throw Exception(
            'Signup succeeded but profile setup failed. Please sign in.');
      }

      // Setup FCM (non-blocking)
      _setupFcmAfterLogin(userId).catchError((error) {
        AppConfig.debugPrint('⚠️ FCM setup failed: $error');
      });

      return response;
    } on AuthException catch (e) {
      AppConfig.debugPrint('❌ Signup auth error: ${e.message}');
      throw _createUserFriendlyError(e);
    } catch (e) {
      AppConfig.debugPrint('❌ Signup error: $e');
      throw _createUserFriendlyError(e);
    }
  }

  // --------------------------------------------------------
  // FORCE RESET SESSION (Debug / "Clear Session" button)
  // --------------------------------------------------------

  static Future<void> forceResetSession() async {
    try {
      AppConfig.debugPrint('🧹 Force resetting session...');

      // Sign out from Supabase (ignore errors if already signed out)
      try {
        await _supabase.auth.signOut();
      } catch (e) {
        AppConfig.debugPrint('⚠️ signOut during reset failed (continuing): $e');
      }

      // Clear local cache
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('isPremiumUser');
      await prefs.remove('saved_email');

      // Clear database cache
      await DatabaseServiceCore.clearAllUserCache();

      // Wait for state to settle
      await Future.delayed(const Duration(seconds: 1));

      AppConfig.debugPrint('✅ Session reset complete');
    } catch (e) {
      AppConfig.debugPrint('❌ Session reset failed: $e');
      throw Exception('Failed to reset session: $e');
    }
  }

  // --------------------------------------------------------
  // SIGN OUT
  // --------------------------------------------------------

  static Future<void> signOut() async {
    try {
      AppConfig.debugPrint('🔓 Signing out...');

      await DatabaseServiceCore.clearAllUserCache();
      await _supabase.auth.signOut();

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('isPremiumUser');

      AppConfig.debugPrint('✅ Signed out successfully');
    } catch (e) {
      AppConfig.debugPrint('❌ Sign out error: $e');
      throw Exception('Sign out failed: $e');
    }
  }

  // --------------------------------------------------------
  // PASSWORD RESET
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

  static Future<void> updatePassword(String newPassword) async {
    // Note: when called from ResetPasswordPage, setSession() is called first
    // so currentUserId will be non-null even though user wasn't "logged in"
    // via the normal flow.
    if (currentUserId == null) {
      throw Exception('No user session found. Please request a new reset link.');
    }

    try {
      await _supabase.auth.updateUser(
        UserAttributes(password: newPassword),
      );
      AppConfig.debugPrint('✅ Password updated');
    } catch (e) {
      AppConfig.debugPrint('❌ Password update failed: $e');
      throw Exception('Password update failed: $e');
    }
  }

  static Future<void> resendVerificationEmail() async {
    if (currentUser?.email == null) {
      throw Exception('No user email found');
    }

    try {
      await _supabase.auth.resend(
        type: OtpType.signup,
        email: currentUser!.email!,
      );
      AppConfig.debugPrint('✅ Verification email resent');
    } catch (e) {
      AppConfig.debugPrint('❌ Failed to resend verification email: $e');
      throw Exception('Failed to resend verification email: $e');
    }
  }

  // --------------------------------------------------------
  // PREMIUM STATUS
  // --------------------------------------------------------

  static Future<void> markUserAsPremium(String userId) async {
    try {
      await ProfileDataAccess.setPremium(userId, true);
      AppConfig.debugPrint('🌟 User upgraded to premium: $userId');

      if (currentUserId == userId) {
        _setupFcmAfterLogin(userId).catchError((error) {
          AppConfig.debugPrint('⚠️ FCM update failed: $error');
        });
      }
    } catch (e) {
      AppConfig.debugPrint('❌ Failed to set premium status: $e');
      throw Exception('Failed to set premium status: $e');
    }
  }

  // ========================================================
  // PRIVATE HELPER METHODS
  // ========================================================

  /// Setup user profile after successful login (best effort, non-blocking)
  static Future<void> _setupProfileAfterLogin(
    String userId,
    String email,
  ) async {
    try {
      AppConfig.debugPrint('📋 Checking user profile...');

      final profile = await ProfileDataAccess.getUserProfile(userId);

      if (profile == null) {
        final isPremium = _isDefaultPremiumEmail(email);
        AppConfig.debugPrint('📝 Creating missing profile');
        await ProfileDataAccess.createUserProfile(
          userId,
          email,
          isPremium: isPremium,
        );
        AppConfig.debugPrint('✅ Profile created with premium=$isPremium');
      } else {
        final isPremium = _isDefaultPremiumEmail(email);
        final currentPremium = profile['is_premium'] as bool? ?? false;

        if (isPremium && !currentPremium) {
          AppConfig.debugPrint('⭐ Upgrading to premium');
          await ProfileDataAccess.setPremium(userId, true);
        }

        AppConfig.debugPrint('✅ Profile exists');
      }
    } catch (e) {
      AppConfig.debugPrint('⚠️ Profile setup error: $e');
      // Don't rethrow - allow login to continue
    }
  }

  /// Setup FCM token (Android only, best effort, non-blocking)
  static Future<void> _setupFcmAfterLogin(String userId) async {
    if (kIsWeb || Platform.isIOS) {
      AppConfig.debugPrint('ℹ️ Skipping FCM (iOS/Web)');
      return;
    }

    try {
      AppConfig.debugPrint('📱 Setting up FCM (Android)...');

      final token = await FirebaseMessaging.instance.getToken();

      if (token == null) {
        AppConfig.debugPrint('⚠️ FCM token is null');
        return;
      }

      AppConfig.debugPrint('📱 Saving FCM token: ${token.substring(0, 20)}...');

      await DatabaseServiceCore.workerQuery(
        action: 'update',
        table: 'user_profiles',
        filters: {'id': userId},
        data: {
          'fcm_token': token,
          'updated_at': DateTime.now().toIso8601String(),
        },
      );

      AppConfig.debugPrint('✅ FCM token saved');

      _listenForFcmTokenRefresh(userId);
    } catch (e) {
      AppConfig.debugPrint('⚠️ FCM setup failed: $e');
      // Don't rethrow - FCM is optional
    }
  }

  /// Listen for FCM token refresh (Android only)
  static void _listenForFcmTokenRefresh(String userId) {
    if (kIsWeb || Platform.isIOS) return;

    try {
      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
        AppConfig.debugPrint(
            '🔄 FCM token refreshed: ${newToken.substring(0, 20)}...');

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
          AppConfig.debugPrint('✅ Refreshed FCM token saved');
        } catch (e) {
          AppConfig.debugPrint('⚠️ Failed to save refreshed token: $e');
        }
      });
    } catch (e) {
      AppConfig.debugPrint('⚠️ FCM listener setup failed: $e');
    }
  }

  /// Convert auth exceptions to user-friendly messages
  static Exception _createUserFriendlyError(dynamic error) {
    final errorString = error.toString().toLowerCase();

    if (errorString.contains('invalid login credentials') ||
        errorString.contains('invalid email or password')) {
      return Exception('Incorrect email or password. Please try again.');
    }

    if (errorString.contains('email not confirmed')) {
      return Exception('Please verify your email before signing in.');
    }

    if (errorString.contains('user already registered')) {
      return Exception(
          'This email is already registered. Try signing in instead.');
    }

    if (errorString.contains('password should be at least 6 characters')) {
      return Exception('Password must be at least 6 characters long.');
    }

    if (errorString.contains('timeout')) {
      return Exception(
          'Connection timed out. Please check your internet and try again.');
    }

    if (errorString.contains('network') || errorString.contains('socket')) {
      return Exception(
          'Network error. Please check your internet connection.');
    }

    if (errorString.contains('session') || errorString.contains('expired')) {
      return Exception(
          'Session expired. Please try the "Clear Session" button and try again.');
    }

    return Exception('Unable to complete request. Please try again.');
  }
}