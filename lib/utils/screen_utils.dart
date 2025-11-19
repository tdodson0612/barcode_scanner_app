// lib/utils/screen_utils.dart - FIXED: Added dart:math import
import 'package:flutter/material.dart';
import 'dart:math'; // ✅ ADDED: Required for sqrt() function

class ScreenUtils {
  /// Check if device is a tablet based on screen diagonal
  static bool isTablet(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final diagonal = sqrt(size.width * size.width + size.height * size.height);
    return diagonal > 1100; // 7 inches or more
  }
  
  /// Check if device is iPad or large tablet (simpler check)
  static bool isIPad(BuildContext context) {
    return MediaQuery.of(context).size.width > 600;
  }
  
  /// Get appropriate background image based on device type
  static String getBackgroundImage(BuildContext context, {required String type}) {
    final isTablet = ScreenUtils.isIPad(context);
    
    switch (type) {
      case 'home':
        return isTablet 
          ? 'assets/backgrounds/ipad_background.png'
          : 'assets/backgrounds/home_background.png';
      case 'login':
        return isTablet 
          ? 'assets/backgrounds/ipad_background.png'
          : 'assets/backgrounds/login_background.png';
      case 'splash':
        return isTablet 
          ? 'assets/backgrounds/ipad_background.png'
          : 'assets/backgrounds/splash_screen.png';
      default:
        return 'assets/backgrounds/home_background.png';
    }
  }
  
  /// Get responsive padding based on device size
  static double getResponsivePadding(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width > 600) {
      return 32.0; // iPad/Tablet
    } else if (width > 375) {
      return 24.0; // Large phones
    } else {
      return 16.0; // Small phones
    }
  }
  
  /// Get responsive font size multiplier
  static double getFontSizeMultiplier(BuildContext context) {
    return isIPad(context) ? 1.2 : 1.0;
  }
  
  /// Get responsive button height
  static double getButtonHeight(BuildContext context) {
    return isIPad(context) ? 56.0 : 50.0;
  }
  
  /// Get responsive icon size
  static double getIconSize(BuildContext context, {double baseSize = 24.0}) {
    return isIPad(context) ? baseSize * 1.3 : baseSize;
  }
}