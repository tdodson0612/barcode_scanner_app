// lib/services/error_handling_service.dart - FIXED: Added missing methods and constants
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:io';
import '../logger.dart';

/// Centralized error handling service for the entire app
class ErrorHandlingService {
  static final ErrorHandlingService _instance = ErrorHandlingService._internal();
  factory ErrorHandlingService() => _instance;
  ErrorHandlingService._internal();

  // Error categories - FIXED: Added missing constants
  static const String networkError = 'NETWORK_ERROR';
  static const String authError = 'AUTH_ERROR';
  static const String premiumError = 'PREMIUM_ERROR';
  static const String databaseError = 'DATABASE_ERROR';
  static const String scanError = 'SCAN_ERROR';
  static const String imageError = 'IMAGE_ERROR';
  static const String adError = 'AD_ERROR';
  static const String validationError = 'VALIDATION_ERROR';
  static const String initializationError = 'INITIALIZATION_ERROR'; // ADDED
  static const String navigationError = 'NAVIGATION_ERROR'; // ADDED
  static const String unknownError = 'UNKNOWN_ERROR';

  /// Handle error and show appropriate UI response
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
      
      // Log the error
      await _logError(errorInfo, error);
      
      if (!context.mounted) return;

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
      // Fallback error handling
      debugPrint('Error in error handling: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Something went wrong. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Categorize error and create user-friendly message - FIXED: Added missing error types
  static ErrorInfo _categorizeError(dynamic error, String? category) {
    final errorString = error.toString().toLowerCase();
    
    // Network-related errors
    if (_isNetworkError(errorString) || category == networkError) {
      return ErrorInfo(
        category: networkError,
        title: 'Connection Problem',
        message: 'Please check your internet connection and try again.',
        icon: Icons.wifi_off,
        color: Colors.orange,
        canRetry: true,
      );
    }
    
    // Authentication errors
    if (_isAuthError(errorString) || category == authError) {
      return ErrorInfo(
        category: authError,
        title: 'Authentication Required',
        message: 'Please log in to continue using this feature.',
        icon: Icons.lock,
        color: Colors.blue,
        canRetry: false,
        redirectRoute: '/login',
      );
    }
    
    // Premium/subscription errors
    if (_isPremiumError(errorString) || category == premiumError) {
      return ErrorInfo(
        category: premiumError,
        title: 'Premium Feature',
        message: 'This feature requires a premium subscription.',
        icon: Icons.star,
        color: Colors.amber,
        canRetry: false,
        redirectRoute: '/purchase',
      );
    }
    
    // Database errors
    if (_isDatabaseError(errorString) || category == databaseError) {
      return ErrorInfo(
        category: databaseError,
        title: 'Data Sync Issue',
        message: 'Unable to sync your data. Please try again in a moment.',
        icon: Icons.cloud_off,
        color: Colors.red,
        canRetry: true,
      );
    }
    
    // Scanning errors
    if (_isScanError(errorString) || category == scanError) {
      return ErrorInfo(
        category: scanError,
        title: 'Scan Failed',
        message: 'Unable to scan the product. Make sure the barcode is visible and try again.',
        icon: Icons.qr_code_scanner,
        color: Colors.purple,
        canRetry: true,
      );
    }
    
    // Image/camera errors
    if (_isImageError(errorString) || category == imageError) {
      return ErrorInfo(
        category: imageError,
        title: 'Camera Issue',
        message: 'Unable to access the camera. Please check permissions and try again.',
        icon: Icons.camera_alt,
        color: Colors.indigo,
        canRetry: true,
      );
    }
    
    // Ad loading errors
    if (_isAdError(errorString) || category == adError) {
      return ErrorInfo(
        category: adError,
        title: 'Ad Not Available',
        message: 'Unable to load ad at this time. You can still continue.',
        icon: Icons.ad_units,
        color: Colors.grey,
        canRetry: false,
      );
    }
    
    // Validation errors
    if (_isValidationError(errorString) || category == validationError) {
      return ErrorInfo(
        category: validationError,
        title: 'Invalid Input',
        message: 'Please check your input and try again.',
        icon: Icons.error_outline,
        color: Colors.orange,
        canRetry: false,
      );
    }
    
    // ADDED: Initialization errors
    if (_isInitializationError(errorString) || category == initializationError) {
      return ErrorInfo(
        category: initializationError,
        title: 'Startup Issue',
        message: 'Failed to initialize the app properly. Please restart the app.',
        icon: Icons.refresh,
        color: Colors.blue,
        canRetry: true,
      );
    }
    
    // ADDED: Navigation errors
    if (_isNavigationError(errorString) || category == navigationError) {
      return ErrorInfo(
        category: navigationError,
        title: 'Navigation Error',
        message: 'Unable to navigate to the requested page.',
        icon: Icons.navigation,
        color: Colors.teal,
        canRetry: true,
      );
    }
    
    // Default unknown error
    return ErrorInfo(
      category: unknownError,
      title: 'Something Went Wrong',
      message: 'An unexpected error occurred. Please try again.',
      icon: Icons.error,
      color: Colors.red,
      canRetry: true,
    );
  }

  /// Check if error is network-related
  static bool _isNetworkError(String error) {
    return error.contains('socketexception') ||
           error.contains('timeout') ||
           error.contains('network') ||
           error.contains('connection') ||
           error.contains('internet') ||
           error.contains('unreachable') ||
           error.contains('dns') ||
           error.contains('http');
  }

  /// Check if error is authentication-related
  static bool _isAuthError(String error) {
    return error.contains('unauthorized') ||
           error.contains('authentication') ||
           error.contains('login') ||
           error.contains('token') ||
           error.contains('session') ||
           error.contains('sign in') ||
           error.contains('401') ||
           error.contains('403');
  }

  /// Check if error is premium-related
  static bool _isPremiumError(String error) {
    return error.contains('premium') ||
           error.contains('subscription') ||
           error.contains('upgrade') ||
           error.contains('payment') ||
           error.contains('purchase') ||
           error.contains('limit');
  }

  /// Check if error is database-related
  static bool _isDatabaseError(String error) {
    return error.contains('database') ||
           error.contains('supabase') ||
           error.contains('sql') ||
           error.contains('query') ||
           error.contains('table') ||
           error.contains('record');
  }

  /// Check if error is scan-related
  static bool _isScanError(String error) {
    return error.contains('barcode') ||
           error.contains('scan') ||
           error.contains('mlkit') ||
           error.contains('product not found') ||
           error.contains('no barcode');
  }

  /// Check if error is image/camera-related
  static bool _isImageError(String error) {
    return error.contains('camera') ||
           error.contains('image') ||
           error.contains('picker') ||
           error.contains('photo') ||
           error.contains('permission') ||
           error.contains('gallery');
  }

  /// Check if error is ad-related
  static bool _isAdError(String error) {
    return error.contains('ad') ||
           error.contains('admob') ||
           error.contains('interstitial') ||
           error.contains('rewarded');
  }

  /// Check if error is validation-related
  static bool _isValidationError(String error) {
    return error.contains('validation') ||
           error.contains('invalid') ||
           error.contains('empty') ||
           error.contains('required') ||
           error.contains('format');
  }

  /// ADDED: Check if error is initialization-related
  static bool _isInitializationError(String error) {
    return error.contains('initialization') ||
           error.contains('startup') ||
           error.contains('init') ||
           error.contains('bootstrap') ||
           error.contains('launch') ||
           error.contains('setup');
  }

  /// ADDED: Check if error is navigation-related
  static bool _isNavigationError(String error) {
    return error.contains('navigation') ||
           error.contains('route') ||
           error.contains('navigator') ||
           error.contains('page not found') ||
           error.contains('redirect') ||
           error.contains('pushnamed');
  }

  /// Show error dialog
  static void _showErrorDialog({
    required BuildContext context,
    required ErrorInfo errorInfo,
    String? customMessage,
    VoidCallback? onRetry,
    VoidCallback? onCancel,
  }) {
    if (!context.mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(
                errorInfo.icon,
                color: errorInfo.color,
                size: 28,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  errorInfo.title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                customMessage ?? errorInfo.message,
                style: const TextStyle(fontSize: 16),
              ),
              if (errorInfo.category == networkError) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.orange, size: 20),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Make sure you have a stable internet connection.',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          actions: [
            if (onCancel != null || !errorInfo.canRetry)
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  if (onCancel != null) {
                    onCancel();
                  } else if (errorInfo.redirectRoute != null) {
                    Navigator.pushNamed(context, errorInfo.redirectRoute!);
                  }
                },
                child: Text(
                  errorInfo.redirectRoute != null 
                      ? (errorInfo.redirectRoute == '/login' ? 'Login' : 'Upgrade')
                      : 'Cancel',
                ),
              ),
            if (errorInfo.canRetry)
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  if (onRetry != null) {
                    onRetry();
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: errorInfo.color,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Try Again'),
              ),
          ],
        );
      },
    );
  }

  /// Show error snack bar
  static void _showErrorSnackBar({
    required BuildContext context,
    required ErrorInfo errorInfo,
    String? customMessage,
  }) {
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              errorInfo.icon,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                customMessage ?? errorInfo.message,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
        backgroundColor: errorInfo.color,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  /// Log error for debugging and analytics
  static Future<void> _logError(ErrorInfo errorInfo, dynamic originalError) async {
    try {
      // Log to console
      logger.e(
        'Error [${errorInfo.category}]: ${errorInfo.title}',
        error: originalError,
        stackTrace: StackTrace.current,
      );

      // Store error locally for debugging
      final prefs = await SharedPreferences.getInstance();
      final errorLog = {
        'timestamp': DateTime.now().toIso8601String(),
        'category': errorInfo.category,
        'title': errorInfo.title,
        'message': errorInfo.message,
        'originalError': originalError.toString(),
      };

      final existingLogs = prefs.getStringList('error_logs') ?? [];
      existingLogs.add(json.encode(errorLog));
      
      // Keep only last 50 errors
      if (existingLogs.length > 50) {
        existingLogs.removeRange(0, existingLogs.length - 50);
      }
      
      await prefs.setStringList('error_logs', existingLogs);
    } catch (e) {
      debugPrint('Failed to log error: $e');
    }
  }

  /// Get stored error logs (for debugging)
  static Future<List<Map<String, dynamic>>> getErrorLogs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final logs = prefs.getStringList('error_logs') ?? [];
      return logs.map((log) => json.decode(log) as Map<String, dynamic>).toList();
    } catch (e) {
      debugPrint('Failed to get error logs: $e');
      return [];
    }
  }

  /// Clear error logs
  static Future<void> clearErrorLogs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('error_logs');
    } catch (e) {
      debugPrint('Failed to clear error logs: $e');
    }
  }

  /// Quick error handling methods for common scenarios
  
  /// Handle network errors
  static Future<void> handleNetworkError(BuildContext context, dynamic error, {VoidCallback? onRetry}) async {
    await handleError(
      context: context,
      error: error,
      category: networkError,
      onRetry: onRetry,
    );
  }

  /// Handle authentication errors
  static Future<void> handleAuthError(BuildContext context, dynamic error) async {
    await handleError(
      context: context,
      error: error,
      category: authError,
    );
  }

  /// Handle premium errors
  static Future<void> handlePremiumError(BuildContext context, dynamic error) async {
    await handleError(
      context: context,
      error: error,
      category: premiumError,
    );
  }

  /// Handle scan errors
  static Future<void> handleScanError(BuildContext context, dynamic error, {VoidCallback? onRetry}) async {
    await handleError(
      context: context,
      error: error,
      category: scanError,
      onRetry: onRetry,
    );
  }

  /// ADDED: Handle initialization errors
  static Future<void> handleInitializationError(BuildContext context, dynamic error, {VoidCallback? onRetry}) async {
    await handleError(
      context: context,
      error: error,
      category: initializationError,
      onRetry: onRetry,
    );
  }

  /// ADDED: Handle navigation errors
  static Future<void> handleNavigationError(BuildContext context, dynamic error, {VoidCallback? onRetry}) async {
    await handleError(
      context: context,
      error: error,
      category: navigationError,
      onRetry: onRetry,
    );
  }

  /// Show simple snack bar error
  static void showSimpleError(BuildContext context, String message) {
    if (!context.mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Show success message
  static void showSuccess(BuildContext context, String message) {
    if (!context.mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

/// Error information class
class ErrorInfo {
  final String category;
  final String title;
  final String message;
  final IconData icon;
  final Color color;
  final bool canRetry;
  final String? redirectRoute;

  ErrorInfo({
    required this.category,
    required this.title,
    required this.message,
    required this.icon,
    required this.color,
    this.canRetry = true,
    this.redirectRoute,
  });
}