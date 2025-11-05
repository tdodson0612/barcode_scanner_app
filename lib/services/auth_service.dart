// lib/services/auth_service.dart
import 'package:supabase_flutter/supabase_flutter.dart';
import 'database_service.dart';

class AuthService {
  static final SupabaseClient _supabase = Supabase.instance.client;

  // Premium users list (store in lowercase for consistency)
  static const List<String> _premiumEmails = [
    'terryd0612@gmail.com',
    'liverdiseasescanner@gmail.com',
  ];

  static bool get isLoggedIn {
    final loggedIn = _supabase.auth.currentUser != null;
    print('DEBUG: AuthService.isLoggedIn = $loggedIn');
    print('DEBUG: Current user: ${_supabase.auth.currentUser?.email}');
    return loggedIn;
  }

  static User? get currentUser => _supabase.auth.currentUser;
  
  static String? get currentUserId => currentUser?.id;

  static bool _isDefaultPremiumEmail(String email) {
    final normalizedEmail = email.trim().toLowerCase();
    return _premiumEmails.contains(normalizedEmail);
  }

  static Future<AuthResponse> signUp({
    required String email,
    required String password,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    final isPremiumByDefault = _isDefaultPremiumEmail(normalizedEmail);
    
    final response = await _supabase.auth.signUp(
      email: email,
      password: password,
      data: {
        'is_premium': isPremiumByDefault, // Pass premium status to trigger
      },
    );
    
    // Profile is now created automatically by database trigger!
    // No need to call DatabaseService.createUserProfile anymore
    
    return response;
  }

  static Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
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

  static Future<void> signOut() async {
    await _supabase.auth.signOut();
  }

  static Future<void> resetPassword(String email) async {
    await _supabase.auth.resetPasswordForEmail(
      email,
      redirectTo: 'com.terrydodson.liverWiseApp://reset-password',
    );
  }

  static Stream<AuthState> get authStateChanges => 
      _supabase.auth.onAuthStateChange;
}