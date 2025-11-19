// lib/services/auth_service.dart - SIMPLIFIED: Direct Supabase auth (no Worker routing)
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
  static Stream<AuthState> get authStateChanges => _supabase.auth.onAuthStateChange;

  static bool _isDefaultPremiumEmail(String email) {
    final normalizedEmail = email.trim().toLowerCase();
    return _premiumEmails.contains(normalizedEmail);
  }

  // SIGN UP - Direct Supabase
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
        
        // Create profile via Worker (database operation)
        await DatabaseService.createUserProfile(
          response.user!.id,
          email,
          isPremium: isPremium,
        );
      }

      return response;
    } catch (e) {
      throw Exception('Sign up failed: $e');
    }
  }

  // SIGN IN - Direct Supabase
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
        final normalizedEmail = email.trim().toLowerCase();
        if (_isDefaultPremiumEmail(normalizedEmail)) {
          await _ensurePremiumStatus(response.user!.id);
        }
      }

      return response;
    } catch (e) {
      throw Exception('Sign in failed: $e');
    }
  }

  static Future<void> _ensurePremiumStatus(String userId) async {
    try {
      final currentProfile = await DatabaseService.getUserProfile(userId);
      if (currentProfile != null && currentProfile['is_premium'] != true) {
        await DatabaseService.setPremiumStatus(userId, true);
      }
    } catch (e) {
      print('Error ensuring premium status: $e');
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