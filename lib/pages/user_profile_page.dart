// lib/pages/user_profile_page.dart - OPTIMIZED: Aggressive caching for profiles and friendship status
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../services/database_service.dart';
import '../services/error_handling_service.dart';
import 'chat_page.dart';

class UserProfilePage extends StatefulWidget {
  final String userId;

  const UserProfilePage({super.key, required this.userId});

  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage> {
  Map<String, dynamic>? userProfile;
  Map<String, dynamic>? friendshipStatus;
  bool isLoading = true;
  bool isActionLoading = false;

  // Cache keys and durations
  static const Duration _profileCacheDuration = Duration(minutes: 10); // Profiles don't change often
  static const Duration _friendshipCacheDuration = Duration(seconds: 30); // Friendship changes more frequently
  
  String _getProfileCacheKey() => 'user_profile_${widget.userId}';
  String _getFriendshipCacheKey() => 'friendship_status_${widget.userId}';

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }

  Future<void> _loadUserProfile({bool forceRefresh = false}) async {
    try {
      setState(() => isLoading = true);
      
      final prefs = await SharedPreferences.getInstance();
      
      // Try loading from cache first (unless force refresh)
      if (!forceRefresh) {
        final cachedProfile = _getCachedProfile(prefs);
        final cachedFriendship = _getCachedFriendship(prefs);
        
        if (cachedProfile != null && cachedFriendship != null) {
          // Both cached, use them immediately
          if (mounted) {
            setState(() {
              userProfile = cachedProfile;
              friendshipStatus = cachedFriendship;
              isLoading = false;
            });
          }
          return;
        } else if (cachedProfile != null) {
          // Profile cached, show it while fetching friendship
          if (mounted) {
            setState(() {
              userProfile = cachedProfile;
            });
          }
        }
      }
      
      // Fetch fresh data
      final results = await Future.wait([
        DatabaseService.getUserProfile(widget.userId),
        DatabaseService.checkFriendshipStatus(widget.userId),
      ]);
      
      // Cache the results
      final profile = results[0] as Map<String, dynamic>?;
      final friendship = results[1] as Map<String, dynamic>?;
      if (profile != null) {
        await _cacheProfile(prefs, profile);
      }
      if (friendship != null) {
        await _cacheFriendship(prefs, friendship);
      }
      
      if (mounted) {
        setState(() {
          userProfile = profile;
          friendshipStatus = friendship;
          isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => isLoading = false);
        
        // Try to show cached data even if stale
        final prefs = await SharedPreferences.getInstance();
        final staleProfile = _getCachedProfile(prefs, ignoreExpiry: true);
        final staleFriendship = _getCachedFriendship(prefs, ignoreExpiry: true);
        
        if (staleProfile != null && staleFriendship != null) {
          setState(() {
            userProfile = staleProfile;
            friendshipStatus = staleFriendship;
          });
        }
        
        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          category: ErrorHandlingService.databaseError,
          showSnackBar: true,
          customMessage: 'Unable to load user profile',
          onRetry: () => _loadUserProfile(forceRefresh: true),
        );
      }
    }
  }

  Map<String, dynamic>? _getCachedProfile(SharedPreferences prefs, {bool ignoreExpiry = false}) {
    try {
      final cached = prefs.getString(_getProfileCacheKey());
      if (cached == null) return null;
      
      final data = json.decode(cached);
      final timestamp = data['_cached_at'] as int?;
      
      if (timestamp == null) return null;
      
      if (!ignoreExpiry) {
        final age = DateTime.now().millisecondsSinceEpoch - timestamp;
        if (age > _profileCacheDuration.inMilliseconds) return null;
      }
      
      return Map<String, dynamic>.from(data['data']);
    } catch (e) {
      return null;
    }
  }

  Map<String, dynamic>? _getCachedFriendship(SharedPreferences prefs, {bool ignoreExpiry = false}) {
    try {
      final cached = prefs.getString(_getFriendshipCacheKey());
      if (cached == null) return null;
      
      final data = json.decode(cached);
      final timestamp = data['_cached_at'] as int?;
      
      if (timestamp == null) return null;
      
      if (!ignoreExpiry) {
        final age = DateTime.now().millisecondsSinceEpoch - timestamp;
        if (age > _friendshipCacheDuration.inMilliseconds) return null;
      }
      
      return Map<String, dynamic>.from(data['data']);
    } catch (e) {
      return null;
    }
  }

  Future<void> _cacheProfile(SharedPreferences prefs, Map<String, dynamic> profile) async {
    try {
      final cacheData = {
        'data': profile,
        '_cached_at': DateTime.now().millisecondsSinceEpoch,
      };
      await prefs.setString(_getProfileCacheKey(), json.encode(cacheData));
    } catch (e) {
      print('Error caching profile: $e');
    }
  }

  Future<void> _cacheFriendship(SharedPreferences prefs, Map<String, dynamic> friendship) async {
    try {
      final cacheData = {
        'data': friendship,
        '_cached_at': DateTime.now().millisecondsSinceEpoch,
      };
      await prefs.setString(_getFriendshipCacheKey(), json.encode(cacheData));
    } catch (e) {
      print('Error caching friendship: $e');
    }
  }

  Future<void> _invalidateFriendshipCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_getFriendshipCacheKey());
    } catch (e) {
      print('Error invalidating cache: $e');
    }
  }

  /// Public static method to invalidate cache for a specific user
  static Future<void> invalidateUserCache(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('user_profile_$userId');
      await prefs.remove('friendship_status_$userId');
    } catch (e) {
      print('Error invalidating user cache: $e');
    }
  }

  Future<void> _sendFriendRequest() async {
    if (isActionLoading) return;
    
    try {
      setState(() => isActionLoading = true);
      
      await DatabaseService.sendFriendRequest(widget.userId);
      
      // Invalidate cache before fetching fresh data
      await _invalidateFriendshipCache();
      
      final status = await DatabaseService.checkFriendshipStatus(widget.userId);
      final prefs = await SharedPreferences.getInstance();
      await _cacheFriendship(prefs, status);
      
      if (mounted) {
        setState(() {
          friendshipStatus = status;
          isActionLoading = false;
        });
        
        ErrorHandlingService.showSuccess(context, 'Friend request sent!');
      }
    } catch (e) {
      if (mounted) {
        setState(() => isActionLoading = false);
        
        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          category: ErrorHandlingService.databaseError,
          customMessage: 'Unable to send friend request',
          onRetry: _sendFriendRequest,
        );
      }
    }
  }

  Future<void> _cancelFriendRequest() async {
    if (isActionLoading) return;
    
    try {
      setState(() => isActionLoading = true);
      
      await DatabaseService.cancelFriendRequest(widget.userId);
      await _invalidateFriendshipCache();
      
      final status = await DatabaseService.checkFriendshipStatus(widget.userId);
      final prefs = await SharedPreferences.getInstance();
      await _cacheFriendship(prefs, status);
      
      if (mounted) {
        setState(() {
          friendshipStatus = status;
          isActionLoading = false;
        });
        
        ErrorHandlingService.showSuccess(context, 'Friend request cancelled');
      }
    } catch (e) {
      if (mounted) {
        setState(() => isActionLoading = false);
        
        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          category: ErrorHandlingService.databaseError,
          customMessage: 'Unable to cancel friend request',
          onRetry: _cancelFriendRequest,
        );
      }
    }
  }

  Future<void> _acceptFriendRequest() async {
    if (isActionLoading || friendshipStatus?['requestId'] == null) return;
    
    try {
      setState(() => isActionLoading = true);
      
      await DatabaseService.acceptFriendRequest(friendshipStatus!['requestId']);
      await _invalidateFriendshipCache();
      
      final status = await DatabaseService.checkFriendshipStatus(widget.userId);
      final prefs = await SharedPreferences.getInstance();
      await _cacheFriendship(prefs, status);
      
      if (mounted) {
        setState(() {
          friendshipStatus = status;
          isActionLoading = false;
        });
        
        ErrorHandlingService.showSuccess(context, 'Friend request accepted! You are now friends.');
      }
    } catch (e) {
      if (mounted) {
        setState(() => isActionLoading = false);
        
        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          category: ErrorHandlingService.databaseError,
          customMessage: 'Unable to accept friend request',
          onRetry: _acceptFriendRequest,
        );
      }
    }
  }

  Future<void> _declineFriendRequest() async {
    if (isActionLoading || friendshipStatus?['requestId'] == null) return;
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Decline Friend Request'),
        content: Text('Are you sure you want to decline this friend request?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text('Decline', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    
    try {
      setState(() => isActionLoading = true);
      
      await DatabaseService.declineFriendRequest(friendshipStatus!['requestId']);
      await _invalidateFriendshipCache();
      
      final status = await DatabaseService.checkFriendshipStatus(widget.userId);
      final prefs = await SharedPreferences.getInstance();
      await _cacheFriendship(prefs, status);
      
      if (mounted) {
        setState(() {
          friendshipStatus = status;
          isActionLoading = false;
        });
        
        ErrorHandlingService.showSuccess(context, 'Friend request declined');
      }
    } catch (e) {
      if (mounted) {
        setState(() => isActionLoading = false);
        
        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          category: ErrorHandlingService.databaseError,
          customMessage: 'Unable to decline friend request',
          onRetry: _declineFriendRequest,
        );
      }
    }
  }

  Future<void> _unfriend() async {
    if (isActionLoading) return;
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove Friend'),
        content: Text(
          'Are you sure you want to unfriend ${_getDisplayName()}? You can always send them a friend request again later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text('Unfriend', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    
    try {
      setState(() => isActionLoading = true);
      
      await DatabaseService.removeFriend(widget.userId);
      await _invalidateFriendshipCache();
      
      final status = await DatabaseService.checkFriendshipStatus(widget.userId);
      final prefs = await SharedPreferences.getInstance();
      await _cacheFriendship(prefs, status);
      
      if (mounted) {
        setState(() {
          friendshipStatus = status;
          isActionLoading = false;
        });
        
        ErrorHandlingService.showSuccess(
          context,
          'You are no longer friends with ${_getDisplayName()}',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => isActionLoading = false);
        
        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          category: ErrorHandlingService.databaseError,
          customMessage: 'Unable to remove friend',
          onRetry: _unfriend,
        );
      }
    }
  }

  void _openChat() {
    try {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatPage(
            friendId: widget.userId,
            friendName: userProfile?['username'] ?? userProfile?['email'] ?? 'Unknown',
            friendAvatar: userProfile?['avatar_url'],
          ),
        ),
      );
    } catch (e) {
      ErrorHandlingService.handleError(
        context: context,
        error: e,
        category: ErrorHandlingService.navigationError,
        showSnackBar: true,
        customMessage: 'Unable to open chat',
      );
    }
  }

  Widget _buildActionButton() {
    if (friendshipStatus == null) {
      return SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    if (isActionLoading) {
      return SizedBox(
        height: 40,
        child: ElevatedButton(
          onPressed: null,
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
          ),
        ),
      );
    }

    final status = friendshipStatus!['status'];
    final isOutgoing = friendshipStatus!['isOutgoing'] ?? false;

    switch (status) {
      case 'accepted':
        return Column(
          children: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _openChat,
                icon: const Icon(Icons.message),
                label: const Text('Send Message'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _unfriend,
                icon: const Icon(Icons.person_remove, size: 18),
                label: const Text('Unfriend'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: BorderSide(color: Colors.red),
                  padding: EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            SizedBox(height: 8),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle, color: Colors.green, size: 16),
                  SizedBox(width: 4),
                  Text(
                    'Friends',
                    style: TextStyle(
                      color: Colors.green.shade700,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );

      case 'pending':
        if (isOutgoing) {
          return Column(
            children: [
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _cancelFriendRequest,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text('Cancel Friend Request'),
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Friend request sent',
                style: TextStyle(
                  color: Colors.orange.shade600,
                  fontSize: 12,
                ),
              ),
            ],
          );
        } else {
          return Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _acceptFriendRequest,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text('Accept'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _declineFriendRequest,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text('Decline'),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 8),
              Text(
                'Friend request received',
                style: TextStyle(
                  color: Colors.blue.shade600,
                  fontSize: 12,
                ),
              ),
            ],
          );
        }

      case 'none':
      default:
        if (friendshipStatus!['canSendRequest'] == true) {
          return SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _sendFriendRequest,
              icon: const Icon(Icons.person_add),
              label: const Text('Send Friend Request'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          );
        } else {
          return const SizedBox.shrink();
        }
    }
  }

  String _getDisplayName() {
    if (userProfile == null) return 'Unknown User';
    
    final firstName = userProfile!['first_name'];
    final lastName = userProfile!['last_name'];
    final username = userProfile!['username'];
    
    if (firstName != null && lastName != null) {
      return '$firstName $lastName';
    } else if (username != null) {
      return username;
    } else {
      return userProfile!['email'] ?? 'Unknown User';
    }
  }

  String _getSubtitle() {
    if (userProfile == null) return '';
    
    final username = userProfile!['username'];
    final email = userProfile!['email'];
    
    if (username != null && email != null) {
      return '@$username • $email';
    } else if (username != null) {
      return '@$username';
    } else if (email != null) {
      return email;
    } else {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('User Profile'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: () async {
              try {
                await _loadUserProfile(forceRefresh: true);
                if (mounted) {
                  ErrorHandlingService.showSuccess(context, 'Profile refreshed');
                }
              } catch (e) {
                if (mounted) {
                  await ErrorHandlingService.handleError(
                    context: context,
                    error: e,
                    category: ErrorHandlingService.databaseError,
                    showSnackBar: true,
                    customMessage: 'Failed to refresh profile',
                  );
                }
              }
            },
            icon: Icon(Icons.refresh),
            tooltip: 'Refresh profile',
          ),
        ],
      ),
      body: isLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text(
                    'Loading profile...',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ],
              ),
            )
          : userProfile == null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.person_off,
                        size: 64,
                        color: Colors.grey.shade400,
                      ),
                      SizedBox(height: 16),
                      Text(
                        'Profile not found',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'This user may have been deleted or is no longer available.',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade500,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text('Go Back'),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () => _loadUserProfile(forceRefresh: true),
                  child: SingleChildScrollView(
                    physics: AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.grey.shade200,
                                blurRadius: 10,
                                offset: const Offset(0, 5),
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              CircleAvatar(
                                radius: 50,
                                backgroundColor: Colors.grey.shade200,
                                backgroundImage: userProfile!['avatar_url'] != null
                                    ? NetworkImage(userProfile!['avatar_url'])
                                    : null,
                                child: userProfile!['avatar_url'] == null
                                    ? Text(
                                        _getDisplayName()[0].toUpperCase(),
                                        style: const TextStyle(
                                          fontSize: 36,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.grey,
                                        ),
                                      )
                                    : null,
                              ),
                              const SizedBox(height: 16),
                              
                              Text(
                                _getDisplayName(),
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              
                              if (_getSubtitle().isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(
                                  _getSubtitle(),
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey.shade600,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                              
                              const SizedBox(height: 24),
                              
                              _buildActionButton(),
                            ],
                          ),
                        ),
                        
                        const SizedBox(height: 24),
                        
                        if (friendshipStatus != null)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.grey.shade200,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.info_outline,
                                  size: 20,
                                  color: Colors.blue.shade600,
                                ),
                                SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    _getStatusDescription(),
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
    );
  }

  String _getStatusDescription() {
    if (friendshipStatus == null) return 'Loading connection status...';
    
    final status = friendshipStatus!['status'];
    final isOutgoing = friendshipStatus!['isOutgoing'] ?? false;
    
    switch (status) {
      case 'accepted':
        return 'You are friends with this user. You can send messages anytime!';
      case 'pending':
        if (isOutgoing) {
          return 'You sent a friend request. Waiting for them to respond.';
        } else {
          return 'This user sent you a friend request. Accept or decline above.';
        }
      case 'none':
      default:
        return 'You are not connected with this user. Send a friend request to connect!';
    }
  }

  @override
  void dispose() {
    super.dispose();
  }
}