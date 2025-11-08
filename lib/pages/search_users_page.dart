// lib/pages/search_users_page.dart - UPDATED: Enhanced search with debug logging
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import '../services/database_service.dart';
import 'user_profile_page.dart';
import '../widgets/app_drawer.dart';

class SearchUsersPage extends StatefulWidget {
  final String? initialQuery; // optional

  const SearchUsersPage({Key? key, this.initialQuery}) : super(key: key);

  @override
  _SearchUsersPageState createState() => _SearchUsersPageState();
}

class _SearchUsersPageState extends State<SearchUsersPage> {
  late TextEditingController _searchController;
  final Logger _logger = Logger();

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.initialQuery ?? '');

    // automatically run search if initialQuery exists
    if (widget.initialQuery != null && widget.initialQuery!.isNotEmpty) {
      _searchUsers();
    }
  }

  List<Map<String, dynamic>> _searchResults = [];
  Map<String, Map<String, dynamic>> _friendshipStatuses = {};
  bool _isLoading = false;
  bool _hasSearched = false;
  String? _errorMessage;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _runDebugTest() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await DatabaseService.debugTestUserSearch();
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Debug test completed! Check your console logs.'),
          backgroundColor: Colors.blue,
          duration: Duration(seconds: 3),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Debug test error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _searchUsers() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter a search term';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _hasSearched = true;
      _errorMessage = null;
    });

    try {
      _logger.d('🔎 Starting user search from UI...');
      final results = await DatabaseService.searchUsers(query);
      _logger.i('📱 UI received ${results.length} results');
      
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
        
        if (results.isEmpty) {
          _errorMessage = 'No users found matching "$query"';
        }
      });
    } catch (e) {
      _logger.e('❌ UI search error: $e');
      setState(() {
        _isLoading = false;
        _errorMessage = 'Error searching users: $e';
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error searching users: $e'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 4),
        ),
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

  String _buildUserDisplayName(Map<String, dynamic> user) {
    final firstName = user['first_name'];
    final lastName = user['last_name'];
    final username = user['username'];
    
    // Build full name if available
    if (firstName != null && lastName != null) {
      return '$firstName $lastName';
    } else if (firstName != null) {
      return firstName;
    } else if (lastName != null) {
      return lastName;
    } else if (username != null) {
      return username;
    } else {
      return 'No name';
    }
  }

  String _buildUserSubtitle(Map<String, dynamic> user) {
    final username = user['username'];
    final email = user['email'];
    final firstName = user['first_name'];
    final lastName = user['last_name'];
    
    // Show username if name is being used as title
    if ((firstName != null || lastName != null) && username != null) {
      return '@$username';
    } else if (email != null) {
      return email;
    } else {
      return '';
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
                  _buildUserDisplayName(user)[0].toUpperCase(),
                  style: TextStyle(fontWeight: FontWeight.bold),
                )
              : null,
        ),
        title: Text(
          _buildUserDisplayName(user),
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          _buildUserSubtitle(user),
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
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        actions: [
          // Debug button
          IconButton(
            icon: Icon(Icons.bug_report),
            tooltip: 'Run Debug Test',
            onPressed: _runDebugTest,
          ),
        ],
      ),
      drawer: AppDrawer(currentPage: 'find_friends'),
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
                      hintText: 'Search by name, username, or email...',
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

          // Error message banner (if exists)
          if (_errorMessage != null)
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(12),
              margin: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade300),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.orange.shade700),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: TextStyle(color: Colors.orange.shade900),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, size: 20),
                    onPressed: () {
                      setState(() {
                        _errorMessage = null;
                      });
                    },
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
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: 40),
                              child: Text(
                                'Find friends by their first name, last name, username, or email',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                            ),
                            SizedBox(height: 4),
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: 40),
                              child: Text(
                                'Even works with typos!',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.green.shade400,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                            SizedBox(height: 24),
                            // Debug hint
                            ElevatedButton.icon(
                              onPressed: _runDebugTest,
                              icon: Icon(Icons.bug_report),
                              label: Text('Run Debug Test'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.grey.shade700,
                                foregroundColor: Colors.white,
                              ),
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Check console logs after running',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade400,
                                fontStyle: FontStyle.italic,
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
                                SizedBox(height: 16),
                                ElevatedButton.icon(
                                  onPressed: _runDebugTest,
                                  icon: Icon(Icons.bug_report, size: 18),
                                  label: Text('Debug: Check Database'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.orange,
                                    foregroundColor: Colors.white,
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