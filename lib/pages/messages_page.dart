// lib/pages/messages_page.dart - UPDATED: With Logger
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import '../services/database_service.dart';
import '../widgets/app_drawer.dart';
import 'chat_page.dart';
import 'search_users_page.dart';

class MessagesPage extends StatefulWidget {
  const MessagesPage({super.key});

  @override
  _MessagesPageState createState() => _MessagesPageState();
}

class _MessagesPageState extends State<MessagesPage> with SingleTickerProviderStateMixin {
  final Logger _logger = Logger();
  late TabController _tabController;
  List<Map<String, dynamic>> _chats = [];
  List<Map<String, dynamic>> _friendRequests = [];
  bool _isLoadingChats = true;
  bool _isLoadingRequests = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    await Future.wait([
      _loadChats(),
      _loadFriendRequests(),
    ]);
  }

  Future<void> _loadChats() async {
    setState(() => _isLoadingChats = true);
    try {
      _logger.d('📨 Loading chat list...');
      final chats = await DatabaseService.getChatList();
      _logger.i('✅ Loaded ${chats.length} chats');
      
      setState(() {
        _chats = chats;
        _isLoadingChats = false;
      });
    } catch (e) {
      _logger.e('❌ Error loading chats: $e');
      setState(() => _isLoadingChats = false);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Unable to load messages'),
            backgroundColor: Colors.red,
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: _loadChats,
            ),
          ),
        );
      }
    }
  }

  Future<void> _loadFriendRequests() async {
    setState(() => _isLoadingRequests = true);
    try {
      _logger.d('👥 Loading friend requests...');
      final requests = await DatabaseService.getFriendRequests();
      _logger.i('✅ Loaded ${requests.length} friend requests');
      
      setState(() {
        _friendRequests = requests;
        _isLoadingRequests = false;
      });
    } catch (e) {
      _logger.e('❌ Error loading friend requests: $e');
      setState(() => _isLoadingRequests = false);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Unable to load friend requests'),
            backgroundColor: Colors.red,
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: _loadFriendRequests,
            ),
          ),
        );
      }
    }
  }

  Future<void> _acceptFriendRequest(String requestId) async {
    try {
      _logger.d('✅ Accepting friend request: $requestId');
      await DatabaseService.acceptFriendRequest(requestId);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Friend request accepted!'),
          backgroundColor: Colors.green,
        ),
      );
      _loadData(); // Refresh both tabs
    } catch (e) {
      _logger.e('❌ Error accepting request: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error accepting request: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _declineFriendRequest(String requestId) async {
    try {
      _logger.d('❌ Declining friend request: $requestId');
      await DatabaseService.declineFriendRequest(requestId);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Friend request declined'),
          backgroundColor: Colors.orange,
        ),
      );
      _loadFriendRequests(); // Refresh requests tab
    } catch (e) {
      _logger.e('❌ Error declining request: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error declining request: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Messages'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: [
            Tab(
              text: 'Chats',
              icon: Icon(Icons.chat),
            ),
            Tab(
              text: 'Requests',
              icon: Stack(
                children: [
                  Icon(Icons.person_add),
                  if (_friendRequests.isNotEmpty)
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        padding: EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        constraints: BoxConstraints(
                          minWidth: 16,
                          minHeight: 16,
                        ),
                        child: Text(
                          '${_friendRequests.length}',
                          style: TextStyle(
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
            icon: Icon(Icons.person_search),
            onPressed: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => SearchUsersPage()),
              );
              if (result == true) {
                _loadFriendRequests(); // Refresh if friend request was sent
              }
            },
            tooltip: 'Find Friends',
          ),
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: 'Refresh',
          ),
        ],
      ),
      drawer: AppDrawer(currentPage: 'messages'),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildChatsTab(),
          _buildRequestsTab(),
        ],
      ),
    );
  }

  Widget _buildChatsTab() {
    if (_isLoadingChats) {
      return Center(child: CircularProgressIndicator());
    }

    if (_chats.isEmpty) {
      return _buildEmptyChatsState();
    }

    return RefreshIndicator(
      onRefresh: _loadChats,
      child: ListView.builder(
        itemCount: _chats.length,
        itemBuilder: (context, index) {
          final chat = _chats[index];
          final friend = chat['friend'];
          final lastMessage = chat['lastMessage'];
          
          return Card(
            margin: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: ListTile(
              leading: CircleAvatar(
                backgroundImage: friend['avatar_url'] != null
                    ? NetworkImage(friend['avatar_url'])
                    : null,
                child: friend['avatar_url'] == null
                    ? Text(
                        (friend['username'] ?? friend['email'] ?? 'U')[0].toUpperCase(),
                        style: TextStyle(fontWeight: FontWeight.bold),
                      )
                    : null,
              ),
              title: Text(
                friend['username'] ?? friend['email'] ?? 'Unknown User',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: lastMessage != null
                  ? Text(
                      lastMessage['content'] ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.grey[600]),
                    )
                  : Text(
                      'No messages yet',
                      style: TextStyle(
                        color: Colors.grey[500],
                        fontStyle: FontStyle.italic,
                      ),
                    ),
              trailing: lastMessage != null
                  ? Text(
                      _formatMessageTime(lastMessage['created_at']),
                      style: TextStyle(
                        color: Colors.grey[500],
                        fontSize: 12,
                      ),
                    )
                  : Icon(Icons.chat_bubble_outline, color: Colors.grey[400]),
              onTap: () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChatPage(
                      friendId: friend['id'],
                      friendName: friend['username'] ?? friend['email'] ?? 'Unknown',
                      friendAvatar: friend['avatar_url'],
                    ),
                  ),
                );
                if (result == true) {
                  _loadChats(); // Refresh chats if message was sent
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
      return Center(child: CircularProgressIndicator());
    }

    if (_friendRequests.isEmpty) {
      return _buildEmptyRequestsState();
    }

    return RefreshIndicator(
      onRefresh: _loadFriendRequests,
      child: ListView.builder(
        itemCount: _friendRequests.length,
        itemBuilder: (context, index) {
          final request = _friendRequests[index];
          final sender = request['sender'];
          
          return Card(
            margin: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: ListTile(
              leading: CircleAvatar(
                backgroundImage: sender['avatar_url'] != null
                    ? NetworkImage(sender['avatar_url'])
                    : null,
                child: sender['avatar_url'] == null
                    ? Text(
                        (sender['username'] ?? sender['email'] ?? 'U')[0].toUpperCase(),
                        style: TextStyle(fontWeight: FontWeight.bold),
                      )
                    : null,
              ),
              title: Text(
                sender['username'] ?? sender['email'] ?? 'Unknown User',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text('Wants to be friends'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(Icons.check, color: Colors.green),
                    onPressed: () => _acceptFriendRequest(request['id']),
                    tooltip: 'Accept',
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: Colors.red),
                    onPressed: () => _declineFriendRequest(request['id']),
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

  Widget _buildEmptyChatsState() {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 80,
              color: Colors.grey[400],
            ),
            SizedBox(height: 24),
            Text(
              'No conversations yet',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: Colors.grey[600],
              ),
            ),
            SizedBox(height: 12),
            Text(
              'Add friends and start chatting!\nAll messaging features are completely free.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[500],
                height: 1.4,
              ),
            ),
            SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: () async {
                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => SearchUsersPage()),
                    );
                    if (result == true) {
                      _loadData();
                    }
                  },
                  icon: Icon(Icons.person_search),
                  label: Text('Find Friends'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                ),
                SizedBox(width: 12),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.green,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
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
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.person_add_outlined,
              size: 80,
              color: Colors.grey[400],
            ),
            SizedBox(height: 24),
            Text(
              'No friend requests',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: Colors.grey[600],
              ),
            ),
            SizedBox(height: 12),
            Text(
              'When someone sends you a friend request,\nit will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[500],
                height: 1.4,
              ),
            ),
            SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => SearchUsersPage()),
                );
                if (result == true) {
                  _loadFriendRequests();
                }
              },
              icon: Icon(Icons.person_search),
              label: Text('Find Friends to Connect'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatMessageTime(String? timestamp) {
    if (timestamp == null) return '';
    
    try {
      final messageTime = DateTime.parse(timestamp);
      final now = DateTime.now();
      final difference = now.difference(messageTime);
      
      if (difference.inDays > 0) {
        return '${difference.inDays}d';
      } else if (difference.inHours > 0) {
        return '${difference.inHours}h';
      } else if (difference.inMinutes > 0) {
        return '${difference.inMinutes}m';
      } else {
        return 'now';
      }
    } catch (e) {
      return '';
    }
  }
}