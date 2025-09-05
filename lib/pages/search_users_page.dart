// lib/pages/search_users_page.dart
import 'package:flutter/material.dart';
import '../services/database_service.dart';
import 'user_profile_page.dart';

class SearchUsersPage extends StatefulWidget {
  const SearchUsersPage({Key? key}) : super(key: key);

  @override
  _SearchUsersPageState createState() => _SearchUsersPageState();
}

class _SearchUsersPageState extends State<SearchUsersPage> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  Map<String, Map<String, dynamic>> _friendshipStatuses = {};
  bool _isLoading = false;
  bool _hasSearched = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _searchUsers() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _isLoading = true;
      _hasSearched = true;
    });

    try {
      final results = await DatabaseService.searchUsers(query);
      
      // Get friendship status for each user
      final statusMap = <String, Map<String, dynamic>>{};
      for (final user in results) {
        final status = await DatabaseService.checkFriendshipStatus(user['id']);
        statusMap[user['id']] = status;
      }

      setState(() {
        _searchResults = results;
        _friendshipStatuses = statusMap;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error searching users: $e')),
      );
    }
  }

  Future<void> _sendFriendRequest(String userId) async {
    try {
      await DatabaseService.sendFriendRequest(userId);
      
      // Update the local status
      setState(() {
        _friendshipStatuses[userId] = {
          'status': 'pending',
          'isOutgoing': true,
          'canSendRequest': false,
        };
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Friend request sent!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  Future<void> _cancelFriendRequest(String userId) async {
    try {
      await DatabaseService.cancelFriendRequest(userId);
      
      // Update the local status
      setState(() {
        _friendshipStatuses[userId] = {
          'status': 'none',
          'canSendRequest': true,
        };
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Friend request cancelled'),
          backgroundColor: Colors.orange,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  Widget _buildFriendshipButton(Map<String, dynamic> user) {
    final userId = user['id'];
    final status = _friendshipStatuses[userId];

    if (status == null) {
      return SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    switch (status['status']) {
      case 'accepted':
        return Container(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.green,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check, color: Colors.white, size: 16),
              SizedBox(width: 4),
              Text(
                'Friends',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        );

      case 'pending':
        if (status['isOutgoing'] == true) {
          return ElevatedButton(
            onPressed: () => _cancelFriendRequest(userId),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            ),
            child: Text('Cancel', style: TextStyle(fontSize: 12)),
          );
        } else {
          return Container(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.blue,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'Request Received',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          );
        }

      case 'none':
      default:
        return ElevatedButton.icon(
          onPressed: () => _sendFriendRequest(userId),
          icon: Icon(Icons.person_add, size: 16),
          label: Text('Add', style: TextStyle(fontSize: 12)),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          ),
        );
    }
  }

  Widget _buildUserTile(Map<String, dynamic> user) {
    return Card(
      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundImage: user['avatar_url'] != null
              ? NetworkImage(user['avatar_url'])
              : null,
          child: user['avatar_url'] == null
              ? Text(
                  (user['username'] ?? user['email'] ?? 'U')[0].toUpperCase(),
                  style: TextStyle(fontWeight: FontWeight.bold),
                )
              : null,
        ),
        title: Text(
          user['username'] ?? 'No username',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          user['email'] ?? '',
          style: TextStyle(color: Colors.grey.shade600),
        ),
        trailing: _buildFriendshipButton(user),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => UserProfilePage(userId: user['id']),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Find Friends'),
        backgroundColor: Colors.white,
        elevation: 1,
      ),
      body: Column(
        children: [
          // Search Bar
          Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(
                bottom: BorderSide(color: Colors.grey.shade300),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search by username or email...',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(25),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                    ),
                    onSubmitted: (_) => _searchUsers(),
                  ),
                ),
                SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _isLoading ? null : _searchUsers,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    shape: CircleBorder(),
                    padding: EdgeInsets.all(12),
                  ),
                  child: _isLoading
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : Icon(Icons.search),
                ),
              ],
            ),
          ),

          // Search Results
          Expanded(
            child: _isLoading
                ? Center(child: CircularProgressIndicator())
                : !_hasSearched
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.search,
                              size: 64,
                              color: Colors.grey.shade400,
                            ),
                            SizedBox(height: 16),
                            Text(
                              'Search for Friends',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Enter a username or email to find friends',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ],
                        ),
                      )
                    : _searchResults.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.person_search,
                                  size: 64,
                                  color: Colors.grey.shade400,
                                ),
                                SizedBox(height: 16),
                                Text(
                                  'No users found',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                                SizedBox(height: 8),
                                Text(
                                  'Try a different search term',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey.shade500,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            itemCount: _searchResults.length,
                            itemBuilder: (context, index) {
                              return _buildUserTile(_searchResults[index]);
                            },
                          ),
          ),
        ],
      ),
    );
  }
}