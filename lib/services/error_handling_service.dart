// lib/services/error_handling_service.dart - IMPROVED: iPad-friendly, user-friendly error handling
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../logger.dart';

/// Centralized error handling service for the entire app
/// Apple-compliant: No technical jargon, user-friendly messages, retry options
class ErrorHandlingService {
  static final ErrorHandlingService _instance = ErrorHandlingService._internal();
  factory ErrorHandlingService() => _instance;
  ErrorHandlingService._internal();

  // Error categories
  static const String networkError = 'NETWORK_ERROR';
  static const String authError = 'AUTH_ERROR';
  static const String premiumError = 'PREMIUM_ERROR';
  static const String databaseError = 'DATABASE_ERROR';
  static const String scanError = 'SCAN_ERROR';
  static const String imageError = 'IMAGE_ERROR';
  static const String adError = 'AD_ERROR';
  static const String validationError = 'VALIDATION_ERROR';
  static const String initializationError = 'INITIALIZATION_ERROR';
  static const String navigationError = 'NAVIGATION_ERROR';
  static const String unknownError = 'UNKNOWN_ERROR';

  /// Handle error and show appropriate UI response
  /// Apple-friendly: Clean, simple, actionable messages
  static Future<void> handleError({
    required BuildContext context,
    required dynamic error,
    String? category,
    String? customMessage,
    bool showDialog = true,
    bool showSnackBar = false,
    VoidCallback? onRetry,
    VoidCallback? onCancel,
  }) async {
    try {
      final errorInfo = _categorizeError(error, category);
      
      // Log error for debugging (dev only, not shown to users)
      await _logError(errorInfo, error);
      
      if (!context.mounted) return;

      // Show user-friendly dialog or snackbar
      if (showDialog) {
        _showErrorDialog(
          context: context,
          errorInfo: errorInfo,
          customMessage: customMessage,
          onRetry: onRetry,
          onCancel: onCancel,
        );
      }
      
      if (showSnackBar) {
        _showErrorSnackBar(
          context: context,
          errorInfo: errorInfo,
          customMessage: customMessage,
        );
      }
    } catch (e) {
      // Ultimate fallback - simple, clean message
      if (kDebugMode) {
        debugPrint('Error handler failed: $e');
      }
      if (context.mounted) {
        _showFallbackError(context);
      }
    }
  }

  /// Categorize error with user-friendly, Apple-compliant messages
  /// NO technical jargon, NO raw error messages, YES helpful guidance
  static ErrorInfo _categorizeError(dynamic error, String? category) {
    final errorString = error.toString().toLowerCase();
    
    // Network/Connection issues
    if (_isNetworkError(errorString) || category == networkError) {
      return ErrorInfo(
        category: networkError,
        title: 'Connection Issue',
        message: 'Please check your internet connection and try again.',
        userMessage: 'Make sure WiFi or cellular data is enabled.',
        icon: Icons.wifi_off_rounded,
        color: Colors.orange,
        canRetry: true,
        isUserFacingError: true,
      );
    }
    
    // Authentication - user needs to log in
    if (_isAuthError(errorString) || category == authError) {
      return ErrorInfo(
        category: authError,
        title: 'Please Log In',
        message: 'You need to log in to use this feature.',
        userMessage: 'Your session may have expired. Please sign in again.',
        icon: Icons.lock_outline_rounded,
        color: Colors.blue,
        canRetry: false,
        redirectRoute: '/login',
        isUserFacingError: true,
      );
    }
    
    // Premium features
    if (_isPremiumError(errorString) || category == premiumError) {
      return ErrorInfo(
        category: premiumError,
        title: 'Premium Feature',
        message: 'Upgrade to Premium to unlock this feature.',
        userMessage: 'Get unlimited scans and access to all recipes!',
        icon: Icons.star_rounded,
        color: Colors.amber,
        canRetry: false,
        redirectRoute: '/purchase',
        isUserFacingError: true,
      );
    }
    
    // Database/sync issues
    if (_isDatabaseError(errorString) || category == databaseError) {
      return ErrorInfo(
        category: databaseError,
        title: 'Sync Issue',
        message: 'Unable to load data right now.',
        userMessage: 'Please try again in a moment.',
        icon: Icons.sync_problem_rounded,
        color: Colors.red.shade400,
        canRetry: true,
        isUserFacingError: true,
      );
    }
    
    // Barcode scanning issues
    if (_isScanError(errorString) || category == scanError) {
      return ErrorInfo(
        category: scanError,
        title: 'Scan Failed',
        message: 'Unable to read the barcode.',
        userMessage: 'Make sure the barcode is clearly visible and well-lit.',
        icon: Icons.qr_code_scanner_rounded,
        color: Colors.purple,
        canRetry: true,
        isUserFacingError: true,
      );
    }
    
    // Camera/image issues
    if (_isImageError(errorString) || category == imageError) {
      return ErrorInfo(
        category: imageError,
        title: 'Camera Access Needed',
        message: 'Unable to access your camera.',
        userMessage: 'Please allow camera access in Settings to scan products.',
        icon: Icons.camera_alt_rounded,
        color: Colors.indigo,
        canRetry: true,
        redirectRoute: null, // User should go to Settings app
        isUserFacingError: true,
      );
    }
    
    // Ad loading (not critical, don't block user)
    if (_isAdError(errorString) || category == adError) {
      // Silent fail - ads are not critical
      return ErrorInfo(
        category: adError,
        title: 'Ad Unavailable',
        message: 'Continuing without ad.',
        userMessage: 'You can continue using the app.',
        icon: Icons.ad_units_rounded,
        color: Colors.grey,
        canRetry: false,
        isUserFacingError: false, // Don't bother user with ad errors
      );
    }
    
    // Input validation
    if (_isValidationError(errorString) || category == validationError) {
      return ErrorInfo(
        category: validationError,
        title: 'Invalid Input',
        message: 'Please check your information and try again.',
        userMessage: 'Some fields may be empty or incorrectly filled.',
        icon: Icons.error_outline_rounded,
        color: Colors.orange,
        canRetry: false,
        isUserFacingError: true,
      );
    }
    
    // App initialization/startup
    if (_isInitializationError(errorString) || category == initializationError) {
      return ErrorInfo(
        category: initializationError,
        title: 'Startup Issue',
        message: 'The app needs to restart.',
        userMessage: 'Please close and reopen the app.',
        icon: Icons.refresh_rounded,
        color: Colors.blue,
        canRetry: true,
        isUserFacingError: true,
      );
    }
    
    // Navigation (page not found, routing issues)
    if (_isNavigationError(errorString) || category == navigationError) {
      return ErrorInfo(
        category: navigationError,
        title: 'Page Not Available',
        message: 'The requested page could not be opened.',
        userMessage: "Let's get you back to the home screen.",
        icon: Icons.home_rounded,
        color: Colors.teal,
        canRetry: false,
        redirectRoute: '/home',
        isUserFacingError: true,
      );
    }
    
    // Unknown/unexpected errors - keep it vague and friendly
    return ErrorInfo(
      category: unknownError,
      title: 'Something Went Wrong',
      message: 'An unexpected issue occurred.',
      userMessage: 'Please try again. If the problem continues, try restarting the app.',
      icon: Icons.error_outline_rounded,
      color: Colors.red.shade400,
      canRetry: true,
      isUserFacingError: true,
    );
  }

  // Error detection methods (unchanged but more robust)
  
  static bool _isNetworkError(String error) {
    return error.contains('socket') ||
           error.contains('timeout') ||
           error.contains('network') ||
           error.contains('connection') ||
           error.contains('internet') ||
           error.contains('unreachable') ||
           error.contains('failed host lookup') ||
           error.contains('no address associated') ||
           error.contains('http') && error.contains('exception');
  }

  static bool _isAuthError(String error) {
    return error.contains('unauthorized') ||
           error.contains('authentication') ||
           error.contains('invalid_grant') ||
           error.contains('token') ||
           error.contains('session') ||
           error.contains('expired') ||
           error.contains('401') ||
           error.contains('403');
  }

  static bool _isPremiumError(String error) {
    return error.contains('premium') ||
           error.contains('subscription') ||
           error.contains('upgrade') ||
           error.contains('limit reached') ||
           error.contains('scan limit');
  }

  static bool _isDatabaseError(String error) {
    return error.contains('database') ||
           error.contains('supabase') ||
           error.contains('postgrest') ||
           error.contains('query') ||
           error.contains('table') ||
           error.contains('fetch');
  }

  static bool _isScanError(String error) {
    return error.contains('barcode') ||
           error.contains('scan') ||
           error.contains('mlkit') ||
           error.contains('product not found') ||
           error.contains('no barcode found');
  }

  static bool _isImageError(String error) {
    return error.contains('camera') ||
           error.contains('image') ||
           error.contains('picker') ||
           error.contains('photo') ||
           error.contains('permission denied') ||
           error.contains('access denied');
  }

  static bool _isAdError(String error) {
    return error.contains('ad') ||
           error.contains('admob') ||
           error.contains('interstitial') ||
           error.contains('rewarded');
  }

  static bool _isValidationError(String error) {
    return error.contains('validation') ||
           error.contains('invalid') ||
           error.contains('empty') ||
           error.contains('required field') ||
           error.contains('format');
  }

  static bool _isInitializationError(String error) {
    return error.contains('initialization') ||
           error.contains('initialize') ||
           error.contains('startup') ||
           error.contains('init failed') ||
           error.contains('bootstrap');
  }

  static bool _isNavigationError(String error) {
    return error.contains('navigation') ||
           error.contains('route') ||
           error.contains('navigator') ||
           error.contains('page not found') ||
           error.contains('could not find');
  }

  /// Show error dialog - iPad optimized, user-friendly
  static void _showErrorDialog({
    required BuildContext context,
    required ErrorInfo errorInfo,
    String? customMessage,
    VoidCallback? onRetry,
    VoidCallback? onCancel,
  }) {
    if (!context.mounted) return;

    // Don't show dialog for non-user-facing errors (like ads)
    if (!errorInfo.isUserFacingError) {
      if (kDebugMode) {
        debugPrint('Silent error: ${errorInfo.category}');
      }
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: errorInfo.canRetry, // Allow dismiss if retry available
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: errorInfo.color.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  errorInfo.icon,
                  color: errorInfo.color,
                  size: 40,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                errorInfo.title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                customMessage ?? errorInfo.message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  height: 1.4,
                ),
              ),
              if (errorInfo.userMessage != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.lightbulb_outline_rounded,
                        color: errorInfo.color,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          errorInfo.userMessage!,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          actions: [
            // Cancel/Dismiss button
            if (errorInfo.canRetry || onCancel != null)
              TextButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  onCancel?.call();
                },
                child: Text(
                  'Cancel',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 16,
                  ),
                ),
              ),
            
            // Primary action button
            if (errorInfo.canRetry && onRetry != null)
              ElevatedButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  onRetry();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: errorInfo.color,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Try Again',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              )
            else if (errorInfo.redirectRoute != null)
              ElevatedButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  Navigator.pushNamed(context, errorInfo.redirectRoute!);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: errorInfo.color,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  errorInfo.redirectRoute == '/login' ? 'Log In' :
                  errorInfo.redirectRoute == '/purchase' ? 'Upgrade' :
                  errorInfo.redirectRoute == '/home' ? 'Go Home' : 'Continue',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              )
            else
              ElevatedButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: errorInfo.color,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'OK',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  /// Show error snack bar - simple, non-intrusive
  static void _showErrorSnackBar({
    required BuildContext context,
    required ErrorInfo errorInfo,
    String? customMessage,
  }) {
    if (!context.mounted || !errorInfo.isUserFacingError) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              errorInfo.icon,
              color: Colors.white,
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                customMessage ?? errorInfo.message,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: errorInfo.color,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  /// Fallback error for when error handler itself fails
  static void _showFallbackError(BuildContext context) {
    if (!context.mounted) return;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Oops!'),
        content: const Text('Something unexpected happened. Please try again.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// Log error for debugging (dev only, never shown to users)
  static Future<void> _logError(ErrorInfo errorInfo, dynamic originalError) async {
    try {
      // Console logging for development
      if (kDebugMode) {
        logger.e(
          'Error [${errorInfo.category}]: ${errorInfo.title}',
          error: originalError,
          stackTrace: StackTrace.current,
        );
      }

      // Store locally for debugging (last 50 errors)
      final prefs = await SharedPreferences.getInstance();
      final errorLog = {
        'timestamp': DateTime.now().toIso8601String(),
        'category': errorInfo.category,
        'title': errorInfo.title,
        'error': originalError.toString().substring(0, 200), // Limit size
      };

      final logs = prefs.getStringList('error_logs') ?? [];
      logs.add(json.encode(errorLog));
      
      if (logs.length > 50) {
        logs.removeRange(0, logs.length - 50);
      }
      
      await prefs.setStringList('error_logs', logs);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Failed to log error: $e');
      }
      // Fail silently - don't compound errors
    }
  }

  // Convenience methods for common error scenarios
  
  static Future<void> handleNetworkError(
    BuildContext context, 
    dynamic error, 
    {VoidCallback? onRetry}
  ) async {
    await handleError(
      context: context,
      error: error,
      category: networkError,
      onRetry: onRetry,
    );
  }

  static Future<void> handleAuthError(BuildContext context, dynamic error) async {
    await handleError(
      context: context,
      error: error,
      category: authError,
    );
  }

  static Future<void> handlePremiumError(BuildContext context, dynamic error) async {
    await handleError(
      context: context,
      error: error,
      category: premiumError,
    );
  }

  static Future<void> handleScanError(
    BuildContext context, 
    dynamic error, 
    {VoidCallback? onRetry}
  ) async {
    await handleError(
      context: context,
      error: error,
      category: scanError,
      onRetry: onRetry,
    );
  }

  static Future<void> handleInitializationError(
    BuildContext context, 
    dynamic error, 
    {VoidCallback? onRetry}
  ) async {
    await handleError(
      context: context,
      error: error,
      category: initializationError,
      onRetry: onRetry,
    );
  }

  static Future<void> handleNavigationError(
    BuildContext context, 
    dynamic error, 
    {VoidCallback? onRetry}
  ) async {
    await handleError(
      context: context,
      error: error,
      category: navigationError,
      onRetry: onRetry,
    );
  }

  /// Simple error message (non-blocking)
  static void showSimpleError(BuildContext context, String message) {
    if (!context.mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red.shade400,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  /// Success message (positive feedback)
  static void showSuccess(BuildContext context, String message) {
    if (!context.mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.white, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(fontSize: 15),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.green.shade600,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  /// Get error logs (for debugging/support)
  static Future<List<Map<String, dynamic>>> getErrorLogs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final logs = prefs.getStringList('error_logs') ?? [];
      return logs.map((log) => json.decode(log) as Map<String, dynamic>).toList();
    } catch (e) {
      return [];
    }
  }

  /// Clear error logs
  static Future<void> clearErrorLogs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('error_logs');
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Failed to clear logs: $e');
      }
    }
  }
}

/// Error information class - Apple-compliant
class ErrorInfo {
  final String category;
  final String title;
  final String message;
  final String? userMessage; // Additional helpful context
  final IconData icon;
  final Color color;
  final bool canRetry;
  final String? redirectRoute;
  final bool isUserFacingError; // Should we show this to the user?

  ErrorInfo({
    required this.category,
    required this.title,
    required this.message,
    this.userMessage,
    required this.icon,
    required this.color,
    this.canRetry = true,
    this.redirectRoute,
    this.isUserFacingError = true,
  });
}