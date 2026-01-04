// lib/widgets/menu_icon_with_badge.dart
// ✅ FIXED: Guaranteed widget rebuild + better state management

import 'package:flutter/material.dart';
import 'package:liver_wise/services/messaging_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';

class MenuIconWithBadge extends StatefulWidget {
  const MenuIconWithBadge({super.key});

  @override
  State<MenuIconWithBadge> createState() => _MenuIconWithBadgeState();
  
  static const String _cacheKey = 'cached_unread_count';
  static const String _cacheTimeKey = 'cached_unread_count_time';
  
  static final GlobalKey<_MenuIconWithBadgeState> globalKey = GlobalKey<_MenuIconWithBadgeState>();
  
  static Future<void> invalidateCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cacheKey);
      await prefs.remove(_cacheTimeKey);
      
      print('🔄 MenuIcon cache invalidated');
      
      // ✅ CRITICAL: Force immediate refresh
      globalKey.currentState?._loadUnreadCount(forceRefresh: true);
    } catch (e) {
      print('⚠️ Error invalidating MenuIcon cache: $e');
    }
  }
}

class _MenuIconWithBadgeState extends State<MenuIconWithBadge> with WidgetsBindingObserver {
  int _unreadCount = 0;
  bool _isLoading = false;
  
  static const Duration _cacheDuration = Duration(seconds: 3);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    // ✅ CRITICAL: Load immediately on init
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadUnreadCount(forceRefresh: true);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      print('📱 App resumed, refreshing MenuIcon badge...');
      _loadUnreadCount(forceRefresh: true);
    }
  }

  // ✅ FIXED: Public refresh method that GUARANTEES rebuild
  Future<void> refresh() async {
    print('🔄 MenuIcon.refresh() called - forcing full reload');
    await _loadUnreadCount(forceRefresh: true);
  }

  Future<void> _loadUnreadCount({bool forceRefresh = false}) async {
    if (_isLoading && !forceRefresh) {
      print('⏭️ MenuIcon already loading, skipping...');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      
      // ✅ Only use cache if NOT force refreshing
      if (!forceRefresh) {
        final cachedCount = prefs.getInt(MenuIconWithBadge._cacheKey);
        final cachedTime = prefs.getInt(MenuIconWithBadge._cacheTimeKey);
        
        if (cachedCount != null && cachedTime != null) {
          final cacheAge = DateTime.now().millisecondsSinceEpoch - cachedTime;
          final isCacheValid = cacheAge < _cacheDuration.inMilliseconds;
          
          if (isCacheValid) {
            if (mounted) {
              setState(() {
                _unreadCount = cachedCount;
                _isLoading = false;
              });
            }
            print('✅ MenuIcon: Using cached count: $cachedCount');
            return;
          } else {
            print('⏰ MenuIcon: Cache expired (${(cacheAge / 1000).round()}s old)');
          }
        }
      } else {
        print('🔄 MenuIcon: Force refresh - bypassing cache');
      }
      
      // ✅ CRITICAL: Always fetch fresh from database
      print('📡 MenuIcon: Fetching fresh count from database...');
      final count = await MessagingService.getUnreadMessageCount();
      
      // Save to cache
      await prefs.setInt(MenuIconWithBadge._cacheKey, count);
      await prefs.setInt(MenuIconWithBadge._cacheTimeKey, DateTime.now().millisecondsSinceEpoch);
      
      if (mounted) {
        setState(() {
          _unreadCount = count;
          _isLoading = false;
        });
      }
      
      print('✅ MenuIcon: Fresh count loaded and displayed: $count');
      
    } catch (e) {
      print('⚠️ MenuIcon: Error loading unread count: $e');
      
      // On error, try to use cached value even if stale
      try {
        final prefs = await SharedPreferences.getInstance();
        final cachedCount = prefs.getInt(MenuIconWithBadge._cacheKey);
        if (cachedCount != null && mounted) {
          setState(() {
            _unreadCount = cachedCount;
            _isLoading = false;
          });
          print('⚠️ MenuIcon: Using stale cache due to error: $cachedCount');
        }
      } catch (_) {
        print('❌ MenuIcon: Could not load cached count either');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(Icons.menu),
        if (_unreadCount > 0)
          Positioned(
            right: -2,
            top: -2,
            child: Container(
              padding: EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              constraints: BoxConstraints(
                minWidth: 16,
                minHeight: 16,
              ),
              child: Text(
                _unreadCount > 9 ? '9+' : '$_unreadCount',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }
}