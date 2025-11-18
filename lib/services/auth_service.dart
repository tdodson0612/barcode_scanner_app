// lib/services/auth_service.dart - REFACTORED: Routes auth operations through Cloudflare Worker
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_config.dart';
import 'database_service.dart';

class AuthService {
  static final SupabaseClient _supabase = Supabase.instance.client;

  // Premium users list (store in lowercase for consistency)
  static const List<String> _premiumEmails = [
    'terryd0612@gmail.com',
    'liverdiseasescanner@gmail.com',
  ];

  // ==================================================
  // AUTH STATE (Keep using Supabase client for auth state)
  // ==================================================
  
  static bool get isLoggedIn {
    final loggedIn = _supabase.auth.currentUser != null;
    print('DEBUG: AuthService.isLoggedIn = $loggedIn');
    print('DEBUG: Current user: ${_supabase.auth.currentUser?.email}');
    return loggedIn;
  }

  static User? get currentUser => _supabase.auth.currentUser;
  
  static String? get currentUserId => currentUser?.id;

  static Stream<AuthState> get authStateChanges => 
      _supabase.auth.onAuthStateChange;

  // ==================================================
  // HELPER METHODS
  // ==================================================
  
  static bool _isDefaultPremiumEmail(String email) {
    final normalizedEmail = email.trim().toLowerCase();
    return _premiumEmails.contains(normalizedEmail);
  }

  /// Send an auth request to the Cloudflare Worker
  static Future<dynamic> _workerAuth({
    required String action,
    Map<String, dynamic>? data,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${AppConfig.cloudflareWorkerQueryEndpoint}/auth'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': action,
          if (data != null) ...data,
        }),
      );

      if (response.statusCode != 200) {
        final errorBody = jsonDecode(response.body);
        throw Exception(errorBody['error'] ?? 'Auth request failed: ${response.body}');
      }

      return jsonDecode(response.body);
    } catch (e) {
      throw Exception('Failed to execute auth request: $e');
    }
  }

  // ==================================================
  // SIGN UP
  // ==================================================
  
  static Future<AuthResponse> signUp({
    required String email,
    required String password,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    final isPremiumByDefault = _isDefaultPremiumEmail(normalizedEmail);
    
    try {
      // MODIFIED: Route sign up through Worker
      final result = await _workerAuth(
        action: 'signUp',
        data: {
          'email': email,
          'password': password,
          'is_premium': isPremiumByDefault,
        },
      );
      
      // Worker returns session data, now sign in locally to establish session
      if (result['session'] != null) {
        // Use the returned session to sign in on the client
        final session = result['session'];
        
        // Sign in with the credentials to establish local session
        return await _supabase.auth.signInWithPassword(
          email: email,
          password: password,
        );
      }
      
      // Fallback: create response object
      return AuthResponse(
        user: null,
        session: null,
      );
    } catch (e) {
      throw Exception('Sign up failed: $e');
    }
  }

  // ==================================================
  // SIGN IN
  // ==================================================
  
  static Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    try {
      // MODIFIED: Route sign in through Worker first to validate credentials
      await _workerAuth(
        action: 'signIn',
        data: {
          'email': email,
          'password': password,
        },
      );
      
      // Now sign in locally to establish session
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

  // ==================================================
  // PREMIUM STATUS
  // ==================================================
  
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

  // ==================================================
  // SIGN OUT
  // ==================================================
  
  static Future<void> signOut() async {
    try {
      // MODIFIED: Notify Worker of sign out (optional, for logging/cleanup)
      try {
        await _workerAuth(
          action: 'signOut',
          data: {
            'user_id': currentUserId,
          },
        );
      } catch (e) {
        print('Worker sign out notification failed: $e');
        // Continue with local sign out even if Worker notification fails
      }
      
      // Clear local caches
      await DatabaseService.clearAllUserCache();
      
      // Sign out from Supabase client
      await _supabase.auth.signOut();
    } catch (e) {
      throw Exception('Sign out failed: $e');
    }
  }

  // ==================================================
  // PASSWORD RESET
  // ==================================================
  
  static Future<void> resetPassword(String email) async {
    try {
      // MODIFIED: Route password reset through Worker
      await _workerAuth(
        action: 'resetPassword',
        data: {
          'email': email,
          'redirect_to': 'com.terrydodson.liverWiseApp://reset-password',
        },
      );
    } catch (e) {
      throw Exception('Password reset failed: $e');
    }
  }

  // ==================================================
  // UPDATE PASSWORD (after reset)
  // ==================================================
  
  static Future<void> updatePassword(String newPassword) async {
    if (currentUserId == null) {
      throw Exception('No user logged in');
    }
    
    try {
      // MODIFIED: Route password update through Worker
      await _workerAuth(
        action: 'updatePassword',
        data: {
          'user_id': currentUserId!,
          'new_password': newPassword,
        },
      );
      
      // Also update locally
      await _supabase.auth.updateUser(
        UserAttributes(password: newPassword),
      );
    } catch (e) {
      throw Exception('Password update failed: $e');
    }
  }

  // ==================================================
  // EMAIL VERIFICATION
  // ==================================================
  
  static Future<void> resendVerificationEmail() async {
    if (currentUser?.email == null) {
      throw Exception('No user email found');
    }
    
    try {
      // MODIFIED: Route email verification through Worker
      await _workerAuth(
        action: 'resendVerification',
        data: {
          'email': currentUser!.email!,
        },
      );
    } catch (e) {
      throw Exception('Failed to resend verification email: $e');
    }
  }
}