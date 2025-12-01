// lib/services/auth_service.dart - FINAL + FCM SUPPORT

import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_config.dart';

// NEW: correct imports
import 'profile_service.dart';
import 'database_service_core.dart';

// 🔥 Firebase Messaging
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

  static Future<String?> fetchCurrentUsername() async {
    if (currentUserId == null) return null;

    try {
      final profile = await ProfileService.getUserProfile(currentUserId!);
      return profile?['username'] as String?;
    } catch (e) {
      print('Error fetching username: $e');
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
  // 🔥 STORE / UPDATE FCM TOKEN
  // --------------------------------------------------------
  static Future<void> _saveFcmToken(String userId) async {
    try {
      final token = await FirebaseMessaging.instance.getToken();

      if (token == null) {
        AppConfig.debugPrint("⚠️ FCM token is null, cannot save.");
        return;
      }

      AppConfig.debugPrint("📱 Saving FCM token: $token");

      await DatabaseServiceCore.workerQuery(
        action: 'update',
        table: 'user_profiles',
        filters: {'id': userId},
        data: {
          'fcm_token': token,
          'updated_at': DateTime.now().toIso8601String(),
        },
      );
    } catch (e) {
      AppConfig.debugPrint("❌ Failed to save FCM token: $e");
    }
  }

  static void _listenForFcmTokenRefresh(String userId) {
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
      AppConfig.debugPrint("🔄 FCM token refreshed: $newToken");

      await DatabaseServiceCore.workerQuery(
        action: 'update',
        table: 'user_profiles',
        filters: {'id': userId},
        data: {
          'fcm_token': newToken,
          'updated_at': DateTime.now().toIso8601String(),
        },
      );
    });
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

        // Delay for session
        await Future.delayed(const Duration(seconds: 1));

        try {
          await ProfileService.createUserProfile(
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

        // 🔥 Save FCM token after profile creation
        await _saveFcmToken(userId);

        // 🔄 Listen for token refresh
        _listenForFcmTokenRefresh(userId);
      }

      return response;
    } catch (e) {
      throw Exception('Sign up failed: $e');
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
      final response = await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (response.user != null) {
        final userId = response.user!.id;
        final normalizedEmail = email.trim().toLowerCase();

        try {
          await _ensureUserProfileExists(userId, email);
        } catch (profileError) {
          AppConfig.debugPrint('⚠️ Profile check failed: $profileError');
        }

        if (_isDefaultPremiumEmail(normalizedEmail)) {
          try {
            await _ensurePremiumStatus(userId);
          } catch (premiumError) {
            AppConfig.debugPrint('⚠️ Premium setup failed: $premiumError');
          }
        }

        // 🔥 Save FCM token after login
        await _saveFcmToken(userId);

        // 🔄 Listen for token refresh
        _listenForFcmTokenRefresh(userId);
      }

      return response;
    } catch (e) {
      throw Exception('Sign in failed: $e');
    }
  }

  // --------------------------------------------------------
  // Ensure user profile exists
  // --------------------------------------------------------
  static Future<void> _ensureUserProfileExists(
      String userId, String email) async {
    try {
      final profile = await ProfileService.getUserProfile(userId);

      if (profile == null) {
        AppConfig.debugPrint('📝 Profile missing → creating');
        await ProfileService.createUserProfile(
          userId,
          email,
          isPremium: false,
        );
        AppConfig.debugPrint('✅ Profile created on login');
      }
    } catch (e) {
      AppConfig.debugPrint('❌ Ensure profile failed: $e');
      throw e;
    }
  }

  // --------------------------------------------------------
  // Ensure premium status
  // --------------------------------------------------------
  static Future<void> _ensurePremiumStatus(String userId) async {
    try {
      final currentProfile = await ProfileService.getUserProfile(userId);
      if (currentProfile != null && currentProfile['is_premium'] != true) {
        AppConfig.debugPrint('💎 Setting premium status: $userId');
        await ProfileService.setPremiumStatus(userId, true);
      }
    } catch (e) {
      AppConfig.debugPrint('⚠️ Premium ensure failed: $e');
    }
  }

  // --------------------------------------------------------
  // SIGN OUT
  // --------------------------------------------------------
  static Future<void> signOut() async {
    try {
      await DatabaseServiceCore.clearAllUserCache();
      await _supabase.auth.signOut();
    } catch (e) {
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
    } catch (e) {
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
    } catch (e) {
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
    } catch (e) {
      throw Exception('Failed to resend verification email: $e');
    }
  }

  static void ensureUserAuthenticated() {
    if (!isLoggedIn) {
      throw Exception('User must be logged in');
    }
  }
}
