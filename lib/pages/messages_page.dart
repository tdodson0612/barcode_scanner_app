// lib/pages/messages_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:liver_wise/services/friends_service.dart';
import 'package:liver_wise/services/messaging_service.dart';
import 'package:liver_wise/services/sound_service.dart';
import 'package:logger/logger.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../widgets/app_drawer.dart';
import '../widgets/menu_icon_with_badge.dart';
import 'chat_page.dart';
import 'search_users_page.dart';

class MessagesPage extends StatefulWidget {
  const MessagesPage({super.key});

  @override
  _MessagesPageState createState() => _MessagesPageState();
}

class _MessagesPageState extends State<MessagesPage>
    with SingleTickerProviderStateMixin {
  final Logger _logger = Logger();
  late TabController _tabController;
  List<Map<String, dynamic>> _chats = [];
  List<Map<String, dynamic>> _friendRequests = [];
  bool _isLoadingChats = true;
  bool _isLoadingRequests = true;

  // Track previous unread total so we only chime on genuinely new messages
  int _previousUnreadTotal = 0;

  static const platform = MethodChannel('com.liverwise/badge');
  static const Duration _chatsCacheDuration = Duration(minutes: 1);
  static const Duration _requestsCacheDuration = Duration(minutes: 2);

  Future<void> _clearIOSBadge() async {
    try {
      await platform.invokeMethod('clearBadge');
      print('✅ iOS badge cleared from messages page');
    } catch (e) {
      print('⚠️ Error clearing iOS badge: $e');
    }
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _clearIOSBadge();
      await MessagingService.refreshUnreadBadge();
    });
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ── Cache helpers ─────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>?> _getCachedChats() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString('user_chats');
      if (cached == null) return null;
      final data = json.decode(cached);
      final timestamp = data['_cached_at'] as int?;
      if (timestamp == null) return null;
      final age = DateTime.now().millisecondsSinceEpoch - timestamp;
      if (age > _chatsCacheDuration.inMilliseconds) return null;
      final chats = (data['chats'] as List)
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      _logger.d('📦 Using cached chats (${chats.length} found)');
      return chats;
    } catch (e) {
      _logger.e('Error loading cached chats: $e');
      return null;
    }
  }

  Future<void> _cacheChats(List<Map<String, dynamic>> chats) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheData = {
        'chats': chats,
        '_cached_at': DateTime.now().millisecondsSinceEpoch,
      };
      await prefs.setString('user_chats', json.encode(cacheData));
      _logger.d('💾 Cached ${chats.length} chats');
    } catch (e) {
      _logger.e('Error caching chats: $e');
    }
  }

  Future<void> _invalidateChatsCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('user_chats');
      _logger.d('🗑️ Invalidated chats cache');
    } catch (e) {
      _logger.e('Error invalidating chats cache: $e');
    }
  }

  Future<List<Map<String, dynamic>>?> _getCachedFriendRequests() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString('friend_requests');
      if (cached == null) return null;
      final data = json.decode(cached);
      final timestamp = data['_cached_at'] as int?;
      if (timestamp == null) return null;
      final age = DateTime.now().millisecondsSinceEpoch - timestamp;
      if (age > _requestsCacheDuration.inMilliseconds) return null;
      final requests = (data['requests'] as List)
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      _logger.d('📦 Using cached friend requests (${requests.length} found)');
      return requests;
    } catch (e) {
      _logger.e('Error loading cached requests: $e');
      return null;
    }
  }

  Future<void> _cacheFriendRequests(
      List<Map<String, dynamic>> requests) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheData = {
        'requests': requests,
        '_cached_at': DateTime.now().millisecondsSinceEpoch,
      };
      await prefs.setString('friend_requests', json.encode(cacheData));
      _logger.d('💾 Cached ${requests.length} friend requests');
    } catch (e) {
      _logger.e('Error caching friend requests: $e');
    }
  }

  Future<void> _invalidateRequestsCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('friend_requests');
      _logger.d('🗑️ Invalidated friend requests cache');
    } catch (e) {
      _logger.e('Error invalidating requests cache: $e');
    }
  }

  static Future<void> invalidateChatsCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('user_chats');
    } catch (e) {
      print('Error invalidating chats cache: $e');
    }
  }

  // ── Load ──────────────────────────────────────────────────────────────────

  Future<void> _loadData({bool forceRefresh = false}) async {
    await Future.wait([
      _loadChats(forceRefresh: forceRefresh),
      _loadFriendRequests(forceRefresh: forceRefresh),
    ]);
  }

  Future<void> _loadChats({bool forceRefresh = false}) async {
    setState(() => _isLoadingChats = true);

    try {
      _logger.d('📨 Loading chat list...');

      if (!forceRefresh) {
        final cachedChats = await _getCachedChats();
        if (cachedChats != null) {
          if (mounted) {
            setState(() {
              _chats = cachedChats;
              _isLoadingChats = false;
            });
          }
          return;
        }
      }

      final chats = await MessagingService.getChatList();

      chats.sort((a, b) {
        try {
          final timeA = a['lastMessage']?['created_at'];
          final timeB = b['lastMessage']?['created_at'];
          if (timeA == null && timeB == null) return 0;
          if (timeA == null) return 1;
          if (timeB == null) return -1;
          final dateA = DateTime.parse(timeA);
          final dateB = DateTime.parse(timeB);
          return dateB.compareTo(dateA);
        } catch (e) {
          return 0;
        }
      });

      await _cacheChats(chats);

      // 🔔 Play chime if unread total has increased since last load
      final newUnreadTotal = chats.fold<int>(
          0, (sum, c) => sum + ((c['unreadCount'] ?? 0) as int));
      if (newUnreadTotal > _previousUnreadTotal) {
        await SoundService.playMessageChime();
      }
      _previousUnreadTotal = newUnreadTotal;

      _logger.i('✅ Loaded ${chats.length} chats');

      if (mounted) {
        setState(() {
          _chats = chats;
          _isLoadingChats = false;
        });
      }
    } catch (e) {
      _logger.e('❌ Error loading chats: $e');

      if (!forceRefresh) {
        final staleChats = await _getCachedChats();
        if (staleChats != null && mounted) {
          setState(() {
            _chats = staleChats;
            _isLoadingChats = false;
          });
          return;
        }
      }

      if (mounted) {
        setState(() => _isLoadingChats = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Unable to load messages'),
            backgroundColor: Colors.red,
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: () => _loadChats(forceRefresh: true),
            ),
          ),
        );
      }
    }
  }

  Future<void> _loadFriendRequests({bool forceRefresh = false}) async {
    setState(() => _isLoadingRequests = true);

    try {
      _logger.d('👥 Loading friend requests...');

      if (!forceRefresh) {
        final cachedRequests = await _getCachedFriendRequests();
        if (cachedRequests != null) {
          if (mounted) {
            setState(() {
              _friendRequests = cachedRequests;
              _isLoadingRequests = false;
            });
          }
          return;
        }
      }

      final requests = await FriendsService.getFriendRequests();
      await _cacheFriendRequests(requests);

      _logger.i('✅ Loaded ${requests.length} friend requests');

      if (mounted) {
        setState(() {
          _friendRequests = requests;
          _isLoadingRequests = false;
        });
      }
    } catch (e) {
      _logger.e('❌ Error loading friend requests: $e');

      if (!forceRefresh) {
        final staleRequests = await _getCachedFriendRequests();
        if (staleRequests != null && mounted) {
          setState(() {
            _friendRequests = staleRequests;
            _isLoadingRequests = false;
          });
          return;
        }
      }

      if (mounted) {
        setState(() => _isLoadingRequests = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Unable to load friend requests'),
            backgroundColor: Colors.red,
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: () => _loadFriendRequests(forceRefresh: true),
            ),
          ),
        );
      }
    }
  }

  // ── Friend request actions ────────────────────────────────────────────────

  Future<void> _acceptFriendRequest(String requestId) async {
    try {
      _logger.d('✅ Accepting friend request: $requestId');
      await FriendsService.acceptFriendRequest(requestId);
      await _invalidateRequestsCache();
      await _invalidateChatsCache();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Friend request accepted!'),
            backgroundColor: Colors.green,
          ),
        );
      }
      _loadData(forceRefresh: true);
    } catch (e) {
      _logger.e('❌ Error accepting request: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error accepting request: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _declineFriendRequest(String requestId) async {
    try {
      _logger.d('❌ Declining friend request: $requestId');
      await FriendsService.declineFriendRequest(requestId);
      await _invalidateRequestsCache();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Friend request declined'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      _loadFriendRequests(forceRefresh: true);
    } catch (e) {
      _logger.e('❌ Error declining request: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error declining request: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Messages'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: [
            const Tab(text: 'Chats', icon: Icon(Icons.chat)),
            Tab(
              text: 'Requests',
              icon: Stack(
                children: [
                  const Icon(Icons.person_add),
                  if (_friendRequests.isNotEmpty)
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        constraints: const BoxConstraints(
                            minWidth: 16, minHeight: 16),
                        child: Text(
                          '${_friendRequests.length}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_search),
            tooltip: 'Find Friends',
            onPressed: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SearchUsersPage()),
              );
              if (result == true) {
                await _invalidateRequestsCache();
                _loadFriendRequests(forceRefresh: true);
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () => _loadData(forceRefresh: true),
          ),
        ],
      ),
      drawer: const AppDrawer(currentPage: 'messages'),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildChatsTab(),
          _buildRequestsTab(),
        ],
      ),
    );
  }

  // ── Tabs ──────────────────────────────────────────────────────────────────

  Widget _buildChatsTab() {
    if (_isLoadingChats) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_chats.isEmpty) return _buildEmptyChatsState();

    return RefreshIndicator(
      onRefresh: () => _loadChats(forceRefresh: true),
      child: ListView.builder(
        itemCount: _chats.length,
        itemBuilder: (context, index) {
          final chat = _chats[index];
          final friend = chat['friend'];
          final lastMessage = chat['lastMessage'];
          final unreadCount = chat['unreadCount'] ?? 0;

          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: ListTile(
              leading: Stack(
                children: [
                  CircleAvatar(
                    backgroundImage: friend['avatar_url'] != null
                        ? NetworkImage(friend['avatar_url'])
                        : null,
                    child: friend['avatar_url'] == null
                        ? Text(
                            (friend['username'] ??
                                    friend['email'] ??
                                    'U')[0]
                                .toUpperCase(),
                            style: const TextStyle(
                                fontWeight: FontWeight.bold),
                          )
                        : null,
                  ),
                  if (unreadCount > 0)
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                          border:
                              Border.all(color: Colors.white, width: 2),
                        ),
                        constraints: const BoxConstraints(
                            minWidth: 18, minHeight: 18),
                        child: Text(
                          unreadCount > 9 ? '9+' : '$unreadCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
              title: Text(
                friend['username'] ?? friend['email'] ?? 'Unknown User',
                style: TextStyle(
                  fontWeight: unreadCount > 0
                      ? FontWeight.bold
                      : FontWeight.w600,
                ),
              ),
              subtitle: lastMessage != null
                  ? Text(
                      lastMessage['content'] ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: unreadCount > 0
                            ? Colors.black
                            : Colors.grey[600],
                        fontWeight: unreadCount > 0
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    )
                  : Text(
                      'No messages yet',
                      style: TextStyle(
                        color: Colors.grey[500],
                        fontStyle: FontStyle.italic,
                      ),
                    ),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (lastMessage != null)
                    Text(
                      _formatMessageTime(lastMessage['created_at']),
                      style: TextStyle(
                        color: unreadCount > 0
                            ? Colors.blue
                            : Colors.grey[500],
                        fontSize: 12,
                        fontWeight: unreadCount > 0
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  if (unreadCount > 0)
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        unreadCount > 9 ? '9+' : '$unreadCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
              onTap: () async {
                // ✅ CRITICAL: Invalidate badge BEFORE opening chat
                await MenuIconWithBadge.invalidateCache();

                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChatPage(
                      friendId: friend['id'],
                      friendName: friend['username'] ??
                          friend['email'] ??
                          'Unknown',
                      friendAvatar: friend['avatar_url'],
                    ),
                  ),
                );

                // ✅ CRITICAL: Refresh badge AFTER returning from chat
                await MessagingService.refreshUnreadBadge();

                if (result == true) {
                  await _invalidateChatsCache();
                  _loadChats(forceRefresh: true);
                }
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildRequestsTab() {
    if (_isLoadingRequests) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_friendRequests.isEmpty) return _buildEmptyRequestsState();

    return RefreshIndicator(
      onRefresh: () => _loadFriendRequests(forceRefresh: true),
      child: ListView.builder(
        itemCount: _friendRequests.length,
        itemBuilder: (context, index) {
          final request = _friendRequests[index];
          final sender = request['sender'];

          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: ListTile(
              leading: CircleAvatar(
                backgroundImage: sender['avatar_url'] != null
                    ? NetworkImage(sender['avatar_url'])
                    : null,
                child: sender['avatar_url'] == null
                    ? Text(
                        (sender['username'] ??
                                sender['email'] ??
                                'U')[0]
                            .toUpperCase(),
                        style: const TextStyle(
                            fontWeight: FontWeight.bold),
                      )
                    : null,
              ),
              title: Text(
                sender['username'] ??
                    sender['email'] ??
                    'Unknown User',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: const Text('Wants to be friends'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.check, color: Colors.green),
                    onPressed: () =>
                        _acceptFriendRequest(request['id']),
                    tooltip: 'Accept',
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.red),
                    onPressed: () =>
                        _declineFriendRequest(request['id']),
                    tooltip: 'Decline',
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Empty states ──────────────────────────────────────────────────────────

  Widget _buildEmptyChatsState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.chat_bubble_outline,
                size: 80, color: Colors.grey[400]),
            const SizedBox(height: 24),
            Text(
              'No conversations yet',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Add friends and start chatting!\nAll messaging features are completely free.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[500],
                height: 1.4,
              ),
            ),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: () async {
                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const SearchUsersPage()),
                    );
                    if (result == true) {
                      await _invalidateRequestsCache();
                      _loadData(forceRefresh: true);
                    }
                  },
                  icon: const Icon(Icons.person_search),
                  label: const Text('Find Friends'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.green,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'FREE',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyRequestsState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_add_outlined,
                size: 80, color: Colors.grey[400]),
            const SizedBox(height: 24),
            Text(
              'No friend requests',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'When someone sends you a friend request,\nit will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[500],
                height: 1.4,
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const SearchUsersPage()),
                );
                if (result == true) {
                  await _invalidateRequestsCache();
                  _loadFriendRequests(forceRefresh: true);
                }
              },
              icon: const Icon(Icons.person_search),
              label: const Text('Find Friends to Connect'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Time formatting ───────────────────────────────────────────────────────

  String _formatMessageTime(String? timestamp) {
    if (timestamp == null) return '';
    try {
      final utcDateTime = DateTime.parse(timestamp);
      final localDateTime = utcDateTime.toLocal();
      final now = DateTime.now();
      final difference = now.difference(localDateTime);

      if (difference.inDays == 0 && localDateTime.day == now.day) {
        return DateFormat('h:mm a').format(localDateTime);
      } else if (difference.inDays == 1 ||
          (localDateTime.day == now.day - 1 &&
              localDateTime.month == now.month)) {
        return 'Yesterday';
      } else if (difference.inDays < 7) {
        return DateFormat('EEE').format(localDateTime);
      } else if (localDateTime.year == now.year) {
        return DateFormat('MMM d').format(localDateTime);
      } else {
        return DateFormat('MMM d, y').format(localDateTime);
      }
    } catch (e) {
      return '';
    }
  }
}