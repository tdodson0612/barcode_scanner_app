// lib/widgets/menu_icon_with_badge.dart - OPTIMIZED: Local caching to reduce database egress
import 'package:flutter/material.dart';
import 'package:liver_wise/services/messaging_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/database_service_core.dart';

class MenuIconWithBadge extends StatefulWidget {
  const MenuIconWithBadge({super.key});

  @override
  State<MenuIconWithBadge> createState() => _MenuIconWithBadgeState();
}

class _MenuIconWithBadgeState extends State<MenuIconWithBadge> {
  int _unreadCount = 0;
  static const String _cacheKey = 'cached_unread_count';
  static const String _cacheTimeKey = 'cached_unread_count_time';
  static const Duration _cacheDuration = Duration(seconds: 30);

  @override
  void initState() {
    super.initState();
    _loadUnreadCount();
  }

  Future<void> _loadUnreadCount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Try to load from cache first
      final cachedCount = prefs.getInt(_cacheKey);
      final cachedTime = prefs.getInt(_cacheTimeKey);
      
      if (cachedCount != null && cachedTime != null) {
        final cacheAge = DateTime.now().millisecondsSinceEpoch - cachedTime;
        final isCacheValid = cacheAge < _cacheDuration.inMilliseconds;
        
        if (isCacheValid) {
          // Use cached value
          if (mounted) {
            setState(() => _unreadCount = cachedCount);
          }
          return;
        }
      }
      
      // Cache is stale or doesn't exist, fetch from database
      final count = await MessagingService.getUnreadMessageCount();
      
      // Save to cache
      await prefs.setInt(_cacheKey, count);
      await prefs.setInt(_cacheTimeKey, DateTime.now().millisecondsSinceEpoch);
      
      if (mounted) {
        setState(() => _unreadCount = count);
      }
    } catch (e) {
      print('Error loading unread count: $e');
      
      // On error, try to use cached value even if stale
      final prefs = await SharedPreferences.getInstance();
      final cachedCount = prefs.getInt(_cacheKey);
      if (cachedCount != null && mounted) {
        setState(() => _unreadCount = cachedCount);
      }
    }
  }

  /// Call this method when user opens messages or when you know count has changed
  static Future<void> invalidateCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cacheKey);
    await prefs.remove(_cacheTimeKey);
  }

  /// Manual refresh method - can be called from parent widgets
  Future<void> refresh() async {
    await invalidateCache();
    await _loadUnreadCount();
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