// lib/services/contact_service.dart
// Handles submitting contact/support messages through the Worker

import '../config/app_config.dart';
import '../services/database_service_core.dart';
import '../services/auth_service.dart';

class ContactService {
  // ==================================================
  // SUBMIT CONTACT MESSAGE
  // ==================================================
  static Future<void> submitContactMessage({
    required String name,
    required String email,
    required String message,
  }) async {
    // User may or may not be logged in — we allow both.
    final userId = AuthService.currentUserId;

    try {
      AppConfig.debugPrint('📨 Submitting contact message...');

      await DatabaseServiceCore.workerQuery(
        action: 'insert',
        table: 'contact_messages',
        data: {
          'name': name,
          'email': email,
          'message': message,
          'user_id': userId,
          'created_at': DateTime.now().toIso8601String(),
        },
      );

      AppConfig.debugPrint('✅ Contact message submitted');
    } catch (e) {
      AppConfig.debugPrint('❌ Failed to submit contact message: $e');
      throw Exception('Failed to submit contact message: $e');
    }
  }
}
