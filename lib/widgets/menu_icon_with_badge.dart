// lib/widgets/menu_icon_with_badge.dart
// ✅ FIXED: Added public refresh() method for forced updates

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
      
      AppConfig.debugPrint('🔄 Unread message cache invalidated');
      
      // Trigger immediate refresh if widget is mounted
      globalKey.currentState?._loadUnreadCount(forceRefresh: true);
    } catch (e) {
      AppConfig.debugPrint('⚠️ Error invalidating cache: $e');
    }
  }
}

class _MenuIconWithBadgeState extends State<MenuIconWithBadge> with WidgetsBindingObserver {
  int _unreadCount = 0;
  bool _isLoading = false;
  
  // ✅ REDUCED: Very short cache for more responsive updates
  static const Duration _cacheDuration = Duration(seconds: 5);

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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      AppConfig.debugPrint('📱 App resumed, refreshing unread badge...');
      _loadUnreadCount(forceRefresh: true);
    }
  }

  // ✅ PUBLIC: Can be called from anywhere to force refresh
  Future<void> refresh() async {
    AppConfig.debugPrint('🔄 Manual refresh requested');
    await _loadUnreadCount(forceRefresh: true);
  }

  Future<void> _loadUnreadCount({bool forceRefresh = false}) async {
    if (_isLoading && !forceRefresh) {
      AppConfig.debugPrint('⏭️ Already loading unread count, skipping...');
      return;
    }

    _isLoading = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      
      // ✅ Try cache first (unless forced)
      if (!forceRefresh) {
        final cachedCount = prefs.getInt(MenuIconWithBadge._cacheKey);
        final cachedTime = prefs.getInt(MenuIconWithBadge._cacheTimeKey);
        
        if (cachedCount != null && cachedTime != null) {
          final cacheAge = DateTime.now().millisecondsSinceEpoch - cachedTime;
          final isCacheValid = cacheAge < _cacheDuration.inMilliseconds;
          
          if (isCacheValid) {
            if (mounted) {
              setState(() => _unreadCount = cachedCount);
            }
            AppConfig.debugPrint('✅ Using cached unread count: $cachedCount');
            _isLoading = false;
            return;
          } else {
            AppConfig.debugPrint('⏰ Cache expired, fetching fresh count...');
          }
        }
      } else {
        AppConfig.debugPrint('🔄 Force refresh - bypassing cache');
      }
      
      // ✅ CRITICAL: Always fetch fresh from database on force refresh
      final count = await MessagingService.getUnreadMessageCount();
      
      // Save to cache
      await prefs.setInt(MenuIconWithBadge._cacheKey, count);
      await prefs.setInt(MenuIconWithBadge._cacheTimeKey, DateTime.now().millisecondsSinceEpoch);
      
      if (mounted) {
        setState(() => _unreadCount = count);
      }
      
      AppConfig.debugPrint('✅ Fresh unread count loaded: $count');
      
    } catch (e) {
      AppConfig.debugPrint('⚠️ Error loading unread count: $e');
      
      // On error, try to use cached value even if stale
      try {
        final prefs = await SharedPreferences.getInstance();
        final cachedCount = prefs.getInt(MenuIconWithBadge._cacheKey);
        if (cachedCount != null && mounted) {
          setState(() => _unreadCount = cachedCount);
          AppConfig.debugPrint('⚠️ Using stale cache due to error: $cachedCount');
        }
      } catch (_) {
        AppConfig.debugPrint('❌ Could not load cached count either');
      }
    } finally {
      _isLoading = false;
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