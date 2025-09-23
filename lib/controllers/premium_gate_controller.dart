// lib/controllers/premium_gate_controller.dart
import 'package:flutter/material.dart';
import '../services/premium_service.dart';
import '../services/auth_service.dart';
import '../logger.dart';

class PremiumGateController extends ChangeNotifier {
  static final PremiumGateController _instance = PremiumGateController._internal();
  factory PremiumGateController() => _instance;
  PremiumGateController._internal();

  bool _isPremium = false;
  bool _isLoading = true;
  int _remainingScans = 3; // START WITH 3 SCANS FOR NEW USERS
  int _totalScansUsed = 0;
  bool _initializationFailed = false;
  int _retryCount = 0;
  static const int maxRetries = 3;

  bool get isPremium => _isPremium;
  bool get isLoading => _isLoading;
  int get remainingScans => _remainingScans;
  int get totalScansUsed => _totalScansUsed;
  bool get initializationFailed => _initializationFailed;

  // Initialize premium status with retry logic
  Future<void> initialize() async {
    print('DEBUG: Starting PremiumGateController initialization (attempt ${_retryCount + 1})');
    _isLoading = true;
    _initializationFailed = false;
    notifyListeners();

    try {
      if (AuthService.isLoggedIn) {
        print('DEBUG: User is logged in, checking premium status');
        
        // Use timeout to prevent hanging
        _isPremium = await _checkPremiumWithTimeout();
        print('DEBUG: Premium status result: $_isPremium');
        
        if (_isPremium) {
          // Premium users get unlimited scans
          _remainingScans = -1;
          _totalScansUsed = 0;
        } else {
          // Get remaining scans for free users
          _remainingScans = await _getRemainingScansWithTimeout();
          _totalScansUsed = 3 - _remainingScans;
        }
      } else {
        print('DEBUG: User is NOT logged in - using defaults');
        _isPremium = false;
        _remainingScans = 3; // Give free users 3 scans by default
        _totalScansUsed = 0;
      }

      _retryCount = 0; // Reset retry count on success
    } catch (e, stackTrace) {
      print('DEBUG: Error in initialization (attempt ${_retryCount + 1}): $e');
      logger.e(
        'Error initializing premium status',
        error: e,
        stackTrace: stackTrace,
      );
      
      // Handle initialization failure with fallback values
      await _handleInitializationFailure();
    }

    _isLoading = false;
    notifyListeners();
    print('DEBUG: Initialization complete. isPremium: $_isPremium, remainingScans: $_remainingScans');
  }

  // Check premium status with timeout
  Future<bool> _checkPremiumWithTimeout() async {
    return await Future.any([
      PremiumService.isPremiumUser(),
      Future.delayed(Duration(seconds: 10), () => false), // 10 second timeout
    ]);
  }

  // Get remaining scans with timeout
  Future<int> _getRemainingScansWithTimeout() async {
    return await Future.any([
      PremiumService.getRemainingScanCount(),
      Future.delayed(Duration(seconds: 10), () => 3), // Default to 3 scans on timeout
    ]);
  }

  // Handle initialization failure with retry logic
  Future<void> _handleInitializationFailure() async {
    _retryCount++;
    
    if (_retryCount < maxRetries) {
      print('DEBUG: Retrying initialization in 2 seconds...');
      // Retry after delay
      Future.delayed(Duration(seconds: 2), () {
        if (_retryCount < maxRetries) {
          initialize(); // Retry
        }
      });
    } else {
      print('DEBUG: Max retries reached, using fallback values');
      _initializationFailed = true;
      // Use safe fallback values
      _isPremium = false;
      _remainingScans = 3; // Give users the benefit of the doubt
      _totalScansUsed = 0;
    }
  }

  // Update premium status (call after purchase or login)
  Future<void> refresh() async {
    _retryCount = 0; // Reset retry count for manual refresh
    await initialize();
  }

  // Add a reset method for logout
  void reset() {
    print('DEBUG: Resetting PremiumGateController');
    _isPremium = false;
    _isLoading = false;
    _remainingScans = 3; // Reset to default free scans
    _totalScansUsed = 0;
    _initializationFailed = false;
    _retryCount = 0;
    notifyListeners();
  }

  // FIXED: Check if user can access any feature
  bool canAccessFeature(PremiumFeature feature) {
    if (!AuthService.isLoggedIn) return false;
    
    // If initialization failed, be permissive to avoid blocking users
    if (_initializationFailed) {
      switch (feature) {
        case PremiumFeature.scan:
          return true; // Allow scans when initialization failed
        default:
          return false;
      }
    }
    
    if (_isPremium) return true;

    // Free users can access these features
    switch (feature) {
      case PremiumFeature.basicProfile:
      case PremiumFeature.purchase:
      case PremiumFeature.socialMessaging:
      case PremiumFeature.friendRequests:
      case PremiumFeature.searchUsers:
        return true;
      case PremiumFeature.scan:
        // FIXED: Allow scans if remaining > 0 OR if we haven't loaded yet
        return _remainingScans > 0 || _isLoading;
      case PremiumFeature.groceryList:
      case PremiumFeature.fullRecipes:
      case PremiumFeature.submitRecipes:
      case PremiumFeature.viewRecipes:
      case PremiumFeature.favoriteRecipes:
        return false; // COMPLETELY BLOCKED for free users
    }
  }

  // Use a scan (for free users) with retry logic
  Future<bool> useScan() async {
    if (_isPremium) return true;
    
    try {
      final success = await _incrementScanWithTimeout();
      if (success) {
        if (_remainingScans > 0) {
          _remainingScans--;
        }
        _totalScansUsed = 3 - _remainingScans;
        notifyListeners();
      }
      return success;
    } catch (e) {
      logger.e("Error using scan", error: e);
      // On error, still allow the scan locally but log the issue
      if (_remainingScans > 0) {
        _remainingScans--;
        _totalScansUsed = 3 - _remainingScans;
        notifyListeners();
      }
      return true; // Be permissive on error
    }
  }

  // Increment scan count with timeout
  Future<bool> _incrementScanWithTimeout() async {
    try {
      return await Future.any([
        PremiumService.incrementScanCount(),
        Future.delayed(Duration(seconds: 5), () => true), // Timeout fallback
      ]);
    } catch (e) {
      return true; // Be permissive on error
    }
  }

  // Check if user has used all free scans
  bool get hasUsedAllFreeScans => !_isPremium && _remainingScans <= 0;

  // Award bonus scans (from rewarded ads) with bounds checking
  Future<void> addBonusScans(int count) async {
    if (_isPremium) {
      // Premium users don't need bonus scans
      return;
    }

    try {
      _remainingScans += count;

      // Prevent negative values and excessive bonus scans
      _remainingScans = _remainingScans.clamp(0, 10); // Max 10 total scans

      _totalScansUsed = (3 - _remainingScans).clamp(0, 3);
      notifyListeners();
      
      print('DEBUG: Added $count bonus scans. New total: $_remainingScans');
    } catch (e, stackTrace) {
      logger.e("Error adding bonus scans", error: e, stackTrace: stackTrace);
    }
  }

  // Get user-friendly status message
  String getStatusMessage() {
    if (_isLoading) return "Loading...";
    if (_initializationFailed) return "Connection issues - features may be limited";
    if (_isPremium) return "Premium: Unlimited access";
    return "Free: $_remainingScans scans remaining";
  }

  // Check if we should show upgrade prompts
  bool shouldShowUpgradePrompt() {
    return !_isPremium && !_isLoading && _remainingScans <= 1;
  }
}

// Premium features enum (UPDATED with social features)
enum PremiumFeature {
  basicProfile,        // Name and profile picture only
  purchase,            // Purchase premium page
  scan,                // Product scanning (3 max for free)
  viewRecipes,         // View recipe suggestions after scan
  groceryList,         // Grocery list feature
  fullRecipes,         // Full recipe details with ingredients/directions
  submitRecipes,       // Submit own recipes
  favoriteRecipes,     // Save favorite recipes
  socialMessaging,     // NEW: Messaging friends (always free)
  friendRequests,      // NEW: Send/receive friend requests (always free)
  searchUsers,         // NEW: Search for other users (always free)
}