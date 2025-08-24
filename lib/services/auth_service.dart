import 'package:supabase_flutter/supabase_flutter.dart';
import 'database_service.dart';

class AuthService {
  static final SupabaseClient _supabase = Supabase.instance.client;

  // Premium users list
  static const List<String> _premiumEmails = [
    'terryd0612@gmail.com',
    'liverdiseasescanner@gmail.com',
  ];

  static bool get isLoggedIn => _supabase.auth.currentUser != null;
  static User? get currentUser => _supabase.auth.currentUser;

  static bool _isDefaultPremiumEmail(String email) {
    return _premiumEmails.contains(email.toLowerCase().trim());
  }

  static Future<AuthResponse> signUp({
    required String email,
    required String password,
  }) async {
    final response = await _supabase.auth.signUp(
      email: email,
      password: password,
    );
    
    if (response.user != null) {
      final isPremiumByDefault = _isDefaultPremiumEmail(email);
      await DatabaseService.createUserProfile(
        response.user!.id,
        email,
        isPremium: isPremiumByDefault,
      );
    }
    
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

    if (response.user != null && _isDefaultPremiumEmail(email)) {
      await _ensurePremiumStatus(response.user!.id);
    }

    return response;
  }

  static Future<void> _ensurePremiumStatus(String userId) async {
    try {
      final currentProfile = await DatabaseService.getUserProfile();
      if (currentProfile != null && currentProfile['is_premium'] != true) {
        await DatabaseService.setPremiumStatus(true);
      }
    } catch (e) {
      print('Error ensuring premium status: $e');
    }
  }

  static Future<void> signOut() async {
    await _supabase.auth.signOut();
  }

  static Future<void> resetPassword(String email) async {
    await _supabase.auth.resetPasswordForEmail(email);
  }

  static Stream<AuthState> get authStateChanges => 
      _supabase.auth.onAuthStateChange;
}