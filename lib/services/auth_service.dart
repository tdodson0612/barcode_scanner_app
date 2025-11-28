// lib/services/auth_service.dart - FINAL: Handle profile creation failures gracefully

import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_config.dart';
import 'database_service.dart';

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
  
  static Future<String?> fetchCurrentUsername() async {
    if (currentUserId == null) return null;
    
    try {
      final profile = await DatabaseService.getUserProfile(currentUserId!);
      return profile?['username'] as String?;
    } catch (e) {
      print('Error fetching username: $e');
      return null;
    }
  }

  static Stream<AuthState> get authStateChanges => _supabase.auth.onAuthStateChange;

  static bool _isDefaultPremiumEmail(String email) {
    final normalizedEmail = email.trim().toLowerCase();
    return _premiumEmails.contains(normalizedEmail);
  }

  // SIGN UP - Direct Supabase with profile creation
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

        // ✅ WAIT for session to establish
        await Future.delayed(const Duration(seconds: 1));

        // Verify auth token exists
        final session = _supabase.auth.currentSession;
        if (session == null) {
          AppConfig.debugPrint('⚠️ Warning: No session established yet');
        }

        try {
          // ✅ Try to create profile
          await DatabaseService.createUserProfile(
            userId,
            email,
            isPremium: isPremium,
          );
          AppConfig.debugPrint('✅ Profile created successfully during signup');
        } catch (profileError) {
          AppConfig.debugPrint('⚠️ Profile creation failed during signup: $profileError');
          
          // ✅ NEW: Mark that this user needs profile creation on next login
          // This is a safety net - profile will be auto-created on first login if it doesn't exist
          AppConfig.debugPrint('📝 User will have profile created on first login');
          
          // Don't block signup - re-throw so user knows there was an issue
          throw Exception('Signup succeeded but profile setup had an issue. Please try signing in.');
        }
      }

      return response;
    } catch (e) {
      throw Exception('Sign up failed: $e');
    }
  }

  // SIGN IN - Direct Supabase with profile safety check
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
        
        // ✅ NEW: Safety check - ensure profile exists
        try {
          await _ensureUserProfileExists(userId, email);
        } catch (profileError) {
          AppConfig.debugPrint('⚠️ Warning: Could not verify profile: $profileError');
          // Don't block login - user can still proceed
          // Profile will be created/fixed on next app restart or when accessing profile features
        }
        
        // Set premium status if applicable
        if (_isDefaultPremiumEmail(normalizedEmail)) {
          try {
            await _ensurePremiumStatus(userId);
          } catch (premiumError) {
            AppConfig.debugPrint('⚠️ Warning: Could not set premium status: $premiumError');
          }
        }
      }

      return response;
    } catch (e) {
      throw Exception('Sign in failed: $e');
    }
  }

  /// ✅ NEW: Ensure user profile exists, create if missing
  static Future<void> _ensureUserProfileExists(String userId, String email) async {
    try {
      // Check if profile already exists
      final profile = await DatabaseService.getUserProfile(userId);
      
      if (profile == null) {
        AppConfig.debugPrint('📝 Profile missing - creating now...');
        
        // Profile doesn't exist, create it
        await DatabaseService.createUserProfile(
          userId,
          email,
          isPremium: false,
        );
        
        AppConfig.debugPrint('✅ Profile created successfully on login');
      } else {
        AppConfig.debugPrint('✅ Profile already exists');
      }
    } catch (e) {
      AppConfig.debugPrint('❌ Error ensuring profile exists: $e');
      throw e;
    }
  }

  static Future<void> _ensurePremiumStatus(String userId) async {
    try {
      final currentProfile = await DatabaseService.getUserProfile(userId);
      if (currentProfile != null && currentProfile['is_premium'] != true) {
        AppConfig.debugPrint('💎 Setting premium status for: $userId');
        await DatabaseService.setPremiumStatus(userId, true);
      }
    } catch (e) {
      AppConfig.debugPrint('⚠️ Error ensuring premium status: $e');
    }
  }

  // SIGN OUT - Direct Supabase
  static Future<void> signOut() async {
    try {
      await DatabaseService.clearAllUserCache();
      await _supabase.auth.signOut();
    } catch (e) {
      throw Exception('Sign out failed: $e');
    }
  }

  // PASSWORD RESET - Direct Supabase
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

  // UPDATE PASSWORD - Direct Supabase
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

  // EMAIL VERIFICATION - Direct Supabase
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
}