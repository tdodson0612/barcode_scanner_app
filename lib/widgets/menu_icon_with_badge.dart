// lib/widgets/menu_icon_with_badge.dart
// ✅ FIXED: Reliable unread count with proper cache invalidation and refresh logic

import 'package:flutter/material.dart';
import 'package:liver_wise/services/messaging_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';

class MenuIconWithBadge extends StatefulWidget {
  const MenuIconWithBadge({super.key});

  @override
  State<MenuIconWithBadge> createState() => _MenuIconWithBadgeState();
  
  // Shared cache keys - used by both MenuIconWithBadge and AppDrawer
  static const String _cacheKey = 'cached_unread_count';
  static const String _cacheTimeKey = 'cached_unread_count_time';
  
  // Global key to access the state from anywhere
  static final GlobalKey<_MenuIconWithBadgeState> globalKey = GlobalKey<_MenuIconWithBadgeState>();
  
  /// ✅ IMPROVED: Invalidate cache and trigger refresh
  static Future<void> invalidateCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cacheKey);
      await prefs.remove(_cacheTimeKey);
      
      AppConfig.debugPrint('🔄 Unread message cache invalidated');
      
      // ✅ CRITICAL: Trigger immediate refresh on the widget if it's mounted
      globalKey.currentState?._loadUnreadCount(forceRefresh: true);
    } catch (e) {
      AppConfig.debugPrint('⚠️ Error invalidating cache: $e');
    }
  }
}

class _MenuIconWithBadgeState extends State<MenuIconWithBadge> with WidgetsBindingObserver {
  int _unreadCount = 0;
  bool _isLoading = false;
  
  // ✅ REDUCED: Shorter cache duration for more accurate counts
  static const Duration _cacheDuration = Duration(seconds: 15); // Was 30

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadUnreadCount();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // ✅ NEW: Refresh badge when app comes back to foreground
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      AppConfig.debugPrint('📱 App resumed, refreshing unread badge...');
      _loadUnreadCount(forceRefresh: true);
    }
  }

  // ✅ IMPROVED: Load unread count with optional force refresh
  Future<void> _loadUnreadCount({bool forceRefresh = false}) async {
    // Prevent multiple simultaneous loads
    if (_isLoading && !forceRefresh) {
      AppConfig.debugPrint('⏭️ Already loading unread count, skipping...');
      return;
    }

    _isLoading = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      
      // ✅ IMPROVED: Try to load from cache first (unless forced)
      if (!forceRefresh) {
        final cachedCount = prefs.getInt(MenuIconWithBadge._cacheKey);
        final cachedTime = prefs.getInt(MenuIconWithBadge._cacheTimeKey);
        
        if (cachedCount != null && cachedTime != null) {
          final cacheAge = DateTime.now().millisecondsSinceEpoch - cachedTime;
          final isCacheValid = cacheAge < _cacheDuration.inMilliseconds;
          
          if (isCacheValid) {
            // Use cached value
            if (mounted) {
              setState(() => _unreadCount = cachedCount);
            }
            AppConfig.debugPrint('✅ Using cached unread count: $cachedCount');
            _isLoading = false;
            return;
          } else {
            AppConfig.debugPrint('⏰ Cache expired (${cacheAge}ms old), fetching fresh count...');
          }
        }
      } else {
        AppConfig.debugPrint('🔄 Force refresh requested, bypassing cache...');
      }
      
      // ✅ Cache is stale or doesn't exist, fetch from database
      final count = await MessagingService.getUnreadMessageCount();
      
      // ✅ Save to cache with timestamp
      await prefs.setInt(MenuIconWithBadge._cacheKey, count);
      await prefs.setInt(MenuIconWithBadge._cacheTimeKey, DateTime.now().millisecondsSinceEpoch);
      
      if (mounted) {
        setState(() => _unreadCount = count);
      }
      
      AppConfig.debugPrint('✅ Fresh unread count loaded: $count');
      
    } catch (e) {
      AppConfig.debugPrint('⚠️ Error loading unread count: $e');
      
      // ✅ On error, try to use cached value even if stale
      try {
        final prefs = await SharedPreferences.getInstance();
        final cachedCount = prefs.getInt(MenuIconWithBadge._cacheKey);
        if (cachedCount != null && mounted) {
          setState(() => _unreadCount = cachedCount);
          AppConfig.debugPrint('⚠️ Using stale cache due to error: $cachedCount');
        }
      } catch (_) {
        // Fail silently
        AppConfig.debugPrint('❌ Could not load cached count either');
      }
    } finally {
      _isLoading = false;
    }
  }

  /// ✅ NEW: Manual refresh method - can be called from parent widgets
  Future<void> refresh() async {
    await MenuIconWithBadge.invalidateCache();
    await _loadUnreadCount(forceRefresh: true);
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