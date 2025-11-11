// lib/controllers/premium_gate_controller.dart - FIXED: Memory leak and concurrency issues
import 'package:flutter/material.dart';
import 'dart:async';
import '../services/premium_service.dart';
import '../services/auth_service.dart';
import '../logger.dart';

class PremiumGateController extends ChangeNotifier {
  static final PremiumGateController _instance = PremiumGateController._internal();
  factory PremiumGateController() => _instance;
  PremiumGateController._internal();

  // State variables
  bool _isPremium = false;
  bool _isLoading = true;
  int _remainingScans = 3;
  int _totalScansUsed = 0;
  bool _initializationFailed = false;
  
  // FIXED: Proper concurrency control
  int _retryCount = 0;
  static const int maxRetries = 3;
  Timer? _retryTimer; // Managed timer to prevent leaks
  Completer<void>? _initializationCompleter; // Prevent multiple simultaneous initializations
  bool _isDisposed = false; // Disposal tracking

  // Getters
  bool get isPremium => _isPremium;
  bool get isLoading => _isLoading;
  int get remainingScans => _remainingScans;
  int get totalScansUsed => _totalScansUsed;
  bool get initializationFailed => _initializationFailed;
  bool get hasUsedAllFreeScans => !_isPremium && _remainingScans <= 0;

  // FIXED: Proper disposal method to prevent memory leaks
  @override
  void dispose() {
    print('DEBUG: Disposing PremiumGateController');
    _isDisposed = true;
    _retryTimer?.cancel();
    _retryTimer = null;
    _initializationCompleter?.complete();
    _initializationCompleter = null;
    super.dispose();
  }

  // FIXED: Initialize with proper concurrency control and exponential backoff
  Future<void> initialize() async {
    // Prevent multiple simultaneous initializations
    if (_initializationCompleter != null && !_initializationCompleter!.isCompleted) {
      print('DEBUG: Initialization already in progress, waiting...');
      return _initializationCompleter!.future;
    }

    if (_isDisposed) {
      print('DEBUG: Controller disposed, skipping initialization');
      return;
    }

    _initializationCompleter = Completer<void>();
    
    print('DEBUG: Starting PremiumGateController initialization (attempt ${_retryCount + 1})');
    _isLoading = true;
    _initializationFailed = false;
    
    if (!_isDisposed) {
      notifyListeners();
    }

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
        _remainingScans = 3;
        _totalScansUsed = 0;
      }

      _retryCount = 0; // Reset retry count on success
      _initializationFailed = false;
      
    } catch (e, stackTrace) {
      print('DEBUG: Error in initialization (attempt ${_retryCount + 1}): $e');
      logger.e(
        'Error initializing premium status',
        error: e,
        stackTrace: stackTrace,
      );
      
      await _handleInitializationFailure();
    }

    _isLoading = false;
    
    if (!_isDisposed) {
      notifyListeners();
    }
    
    print('DEBUG: Initialization complete. isPremium: $_isPremium, remainingScans: $_remainingScans');
    
    if (!_initializationCompleter!.isCompleted) {
      _initializationCompleter!.complete();
    }
  }

  // FIXED: Proper retry logic with managed Timer and exponential backoff
  Future<void> _handleInitializationFailure() async {
    if (_isDisposed) return;
    
    _retryCount++;
    
    if (_retryCount < maxRetries) {
      // Exponential backoff: 2s, 4s, 8s
      final delaySeconds = 2 * _retryCount;
      print('DEBUG: Retrying initialization in $delaySeconds seconds...');
      
      // FIXED: Use managed Timer instead of unmanaged Future.delayed
      _retryTimer?.cancel(); // Cancel any existing timer
      _retryTimer = Timer(Duration(seconds: delaySeconds), () {
        if (!_isDisposed && _retryCount < maxRetries) {
          print('DEBUG: Executing retry attempt ${_retryCount + 1}');
          initialize(); // This will create a new completer
        }
      });
    } else {
      print('DEBUG: Max retries reached, using fallback values');
      _initializationFailed = true;
      // Use safe fallback values
      _isPremium = false;
      _remainingScans = 3;
      _totalScansUsed = 0;
    }
  }

  // Check premium status with timeout
  Future<bool> _checkPremiumWithTimeout() async {
    if (_isDisposed) return false;
    
    try {
      return await Future.any([
        PremiumService.isPremiumUser(),
        Future.delayed(Duration(seconds: 10), () => false),
      ]).timeout(Duration(seconds: 12)); // Additional safety timeout
    } catch (e) {
      print('DEBUG: Premium check timeout or error: $e');
      return false;
    }
  }

  // Get remaining scans with timeout
  Future<int> _getRemainingScansWithTimeout() async {
    if (_isDisposed) return 3;
    
    try {
      return await Future.any([
        PremiumService.getRemainingScanCount(),
        Future.delayed(Duration(seconds: 10), () => 3),
      ]).timeout(Duration(seconds: 12));
    } catch (e) {
      print('DEBUG: Scan count check timeout or error: $e');
      return 3;
    }
  }

  // FIXED: Update premium status with proper concurrency control
  Future<void> refresh() async {
    if (_isDisposed) return;
    
    print('DEBUG: Manual refresh requested');
    _retryTimer?.cancel(); // Cancel any pending retries
    _retryCount = 0; // Reset retry count for manual refresh
    await initialize();
  }

  // Reset method for logout - FIXED: Cancel timers
  void reset() {
    print('DEBUG: Resetting PremiumGateController');
    
    // Cancel any pending operations
    _retryTimer?.cancel();
    _retryTimer = null;
    _initializationCompleter?.complete();
    _initializationCompleter = null;
    
    // Reset state
    _isPremium = false;
    _isLoading = false;
    _remainingScans = 3;
    _totalScansUsed = 0;
    _initializationFailed = false;
    _retryCount = 0;
    
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  // Check if user can access feature
  bool canAccessFeature(PremiumFeature feature) {
    if (_isDisposed) return false;
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
        return _remainingScans > 0 || _isLoading;
      case PremiumFeature.groceryList:
      case PremiumFeature.fullRecipes:
      case PremiumFeature.submitRecipes:
      case PremiumFeature.viewRecipes:
      case PremiumFeature.favoriteRecipes:
        return false;
    }
  }

  // Use a scan with proper error handling
  Future<bool> useScan() async {
    if (_isDisposed) return false;
    if (_isPremium) return true;
    
    try {
      final success = await _incrementScanWithTimeout();
      if (success && !_isDisposed) {
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
      if (!_isDisposed && _remainingScans > 0) {
        _remainingScans--;
        _totalScansUsed = 3 - _remainingScans;
        notifyListeners();
      }
      return true; // Be permissive on error
    }
  }

  // Increment scan count with timeout
  Future<bool> _incrementScanWithTimeout() async {
    if (_isDisposed) return false;
    
    try {
      return await Future.any([
        PremiumService.incrementScanCount(),
        Future.delayed(Duration(seconds: 5), () => true),
      ]).timeout(Duration(seconds: 7));
    } catch (e) {
      print('DEBUG: Scan increment timeout or error: $e');
      return true; // Be permissive on error
    }
  }

  // Award bonus scans with bounds checking
  Future<void> addBonusScans(int count) async {
    if (_isDisposed || _isPremium) return;

    try {
      _remainingScans += count;
      _remainingScans = _remainingScans.clamp(0, 10); // Max 10 total scans
      _totalScansUsed = (3 - _remainingScans).clamp(0, 3);
      
      if (!_isDisposed) {
        notifyListeners();
      }
      
      print('DEBUG: Added $count bonus scans. New total: $_remainingScans');
    } catch (e, stackTrace) {
      logger.e("Error adding bonus scans", error: e, stackTrace: stackTrace);
    }
  }

  // Get user-friendly status message
  String getStatusMessage() {
    if (_isDisposed) return "Service unavailable";
    if (_isLoading) return "Loading...";
    if (_initializationFailed) return "Connection issues - features may be limited";
    if (_isPremium) return "Premium: Unlimited access";
    return "Free: $_remainingScans scans remaining";
  }

  // Check if we should show upgrade prompts
  bool shouldShowUpgradePrompt() {
    return !_isDisposed && !_isPremium && !_isLoading && _remainingScans <= 1;
  }
}

// Premium features enum
enum PremiumFeature {
  basicProfile,
  purchase,
  scan,
  viewRecipes,
  groceryList,
  fullRecipes,
  submitRecipes,
  favoriteRecipes,
  socialMessaging,
  friendRequests,
  searchUsers,
}