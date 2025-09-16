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
  int _remainingScans = 0;
  int _totalScansUsed = 0;

  bool get isPremium => _isPremium;
  bool get isLoading => _isLoading;
  int get remainingScans => _remainingScans;
  int get totalScansUsed => _totalScansUsed;

  // Initialize premium status
  Future<void> initialize() async {
    print('DEBUG: Starting PremiumGateController initialization');
    _isLoading = true;
    notifyListeners();

    try {
      if (AuthService.isLoggedIn) {
        print('DEBUG: User is logged in, checking premium status');
        _isPremium = await PremiumService.isPremiumUser();
        print('DEBUG: Premium status result: $_isPremium');
        _remainingScans = await PremiumService.getRemainingScanCount();
        _totalScansUsed = 3 - _remainingScans;
      } else {
        print('DEBUG: User is NOT logged in');
        _isPremium = false;
        _remainingScans = 0;
        _totalScansUsed = 0;
      }
    } catch (e, stackTrace) {
      print('DEBUG: Error in initialization: $e');
      logger.e(
        'Error initializing premium status',
        error: e,
        stackTrace: stackTrace,
      );
      _isPremium = false;
      _remainingScans = 0;
      _totalScansUsed = 0;
    }

    _isLoading = false;
    notifyListeners();
    print('DEBUG: Initialization complete. isPremium: $_isPremium');
  }

  // Update premium status (call after purchase or login)
  Future<void> refresh() async {
    await initialize();
  }

  // Add a reset method for logout
  void reset() {
    print('DEBUG: Resetting PremiumGateController');
    _isPremium = false;
    _isLoading = false;
    _remainingScans = 0;
    _totalScansUsed = 0;
    notifyListeners();
  }

  // RESTRICTIVE: Check if user can access any feature
  bool canAccessFeature(PremiumFeature feature) {
    if (!AuthService.isLoggedIn) return false;
    if (_isPremium) return true;

    // Free users can ONLY access basic profile, purchase page, and social features
    switch (feature) {
      case PremiumFeature.basicProfile:
      case PremiumFeature.purchase:
      case PremiumFeature.socialMessaging:    // NEW: Always available
      case PremiumFeature.friendRequests:     // NEW: Always available
      case PremiumFeature.searchUsers:        // NEW: Always available
        return true;
      case PremiumFeature.scan:
        return _remainingScans > 0;
      case PremiumFeature.groceryList:
      case PremiumFeature.fullRecipes:
      case PremiumFeature.submitRecipes:
      case PremiumFeature.viewRecipes:
      case PremiumFeature.favoriteRecipes:
        return false; // COMPLETELY BLOCKED for free users
    }
  }

  // Use a scan (for free users)
  Future<bool> useScan() async {
    if (_isPremium) return true;
    
    final success = await PremiumService.incrementScanCount();
    if (success) {
      _remainingScans = await PremiumService.getRemainingScanCount();
      _totalScansUsed = 3 - _remainingScans;
      notifyListeners();
    }
    return success;
  }

  // Check if user has used all free scans
  bool get hasUsedAllFreeScans => !_isPremium && _remainingScans <= 0;

  // Award bonus scans (from rewarded ads)
  Future<void> addBonusScans(int count) async {
    if (_isPremium) {
      // Premium users don't need bonus scans
      return;
    }

    try {
      _remainingScans += count;

      // Make sure it never goes above the free limit (optional rule)
      if (_remainingScans > 3) {
        _remainingScans = 3;
      }

      _totalScansUsed = 3 - _remainingScans;
      notifyListeners();
    } catch (e, stackTrace) {
      logger.e("Error adding bonus scans", error: e, stackTrace: stackTrace);
    }
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