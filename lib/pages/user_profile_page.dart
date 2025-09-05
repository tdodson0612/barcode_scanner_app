import 'package:flutter/material.dart';
import '../services/database_service.dart';
import 'chat_page.dart';

class UserProfilePage extends StatefulWidget {
  final String userId;

  const UserProfilePage({Key? key, required this.userId}) : super(key: key);

  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage> {
  Map<String, dynamic>? userProfile;
  Map<String, dynamic>? friendshipStatus;
  bool isLoading = true;
  bool isActionLoading = false;

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }

  Future<void> _loadUserProfile() async {
    try {
      setState(() => isLoading = true);
      
      // Get user profile
      final profile = await DatabaseService.getUserProfile(widget.userId);
      
      // Get friendship status
      final status = await DatabaseService.checkFriendshipStatus(widget.userId);
      
      setState(() {
        userProfile = profile;
        friendshipStatus = status;
        isLoading = false;
      });
    } catch (e) {
      setState(() => isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading profile: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _sendFriendRequest() async {
    if (isActionLoading) return;
    
    try {
      setState(() => isActionLoading = true);
      
      await DatabaseService.sendFriendRequest(widget.userId);
      
      // Refresh friendship status
      final status = await DatabaseService.checkFriendshipStatus(widget.userId);
      setState(() {
        friendshipStatus = status;
        isActionLoading = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Friend request sent!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() => isActionLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _cancelFriendRequest() async {
    if (isActionLoading) return;
    
    try {
      setState(() => isActionLoading = true);
      
      await DatabaseService.cancelFriendRequest(widget.userId);
      
      // Refresh friendship status
      final status = await DatabaseService.checkFriendshipStatus(widget.userId);
      setState(() {
        friendshipStatus = status;
        isActionLoading = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Friend request cancelled'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      setState(() => isActionLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _acceptFriendRequest() async {
    if (isActionLoading || friendshipStatus?['requestId'] == null) return;
    
    try {
      setState(() => isActionLoading = true);
      
      await DatabaseService.acceptFriendRequest(friendshipStatus!['requestId']);
      
      // Refresh friendship status
      final status = await DatabaseService.checkFriendshipStatus(widget.userId);
      setState(() {
        friendshipStatus = status;
        isActionLoading = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Friend request accepted!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() => isActionLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _declineFriendRequest() async {
    if (isActionLoading || friendshipStatus?['requestId'] == null) return;
    
    try {
      setState(() => isActionLoading = true);
      
      await DatabaseService.declineFriendRequest(friendshipStatus!['requestId']);
      
      // Refresh friendship status
      final status = await DatabaseService.checkFriendshipStatus(widget.userId);
      setState(() {
        friendshipStatus = status;
        isActionLoading = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Friend request declined'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      setState(() => isActionLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildActionButton() {
    if (friendshipStatus == null || isActionLoading) {
      return const CircularProgressIndicator();
    }

    final status = friendshipStatus!['status'];
    final isOutgoing = friendshipStatus!['isOutgoing'] ?? false;

    switch (status) {
      case 'accepted':
        return ElevatedButton.icon(
          onPressed: () {
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
          },
          icon: const Icon(Icons.message),
          label: const Text('Message'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
          ),
        );

      case 'pending':
        if (isOutgoing) {
          // User sent the request
          return ElevatedButton(
            onPressed: _cancelFriendRequest,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
            child: const Text('Cancel Request'),
          );
        } else {
          // User received the request
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ElevatedButton(
                onPressed: _acceptFriendRequest,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Accept'),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _declineFriendRequest,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Decline'),
              ),
            ],
          );
        }

      case 'none':
      default:
        if (friendshipStatus!['canSendRequest'] == true) {
          return ElevatedButton.icon(
            onPressed: _sendFriendRequest,
            icon: const Icon(Icons.person_add),
            label: const Text('Add Friend'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
          );
        } else {
          return const SizedBox.shrink();
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : userProfile == null
              ? const Center(
                  child: Text(
                    'Profile not found',
                    style: TextStyle(fontSize: 18),
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      // Profile Header
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(15),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.grey.shade300,
                              blurRadius: 10,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            // Avatar
                            CircleAvatar(
                              radius: 50,
                              backgroundImage: userProfile!['avatar_url'] != null
                                  ? NetworkImage(userProfile!['avatar_url'])
                                  : null,
                              child: userProfile!['avatar_url'] == null
                                  ? Text(
                                      userProfile!['username']?[0]?.toUpperCase() ??
                                          userProfile!['email']?[0]?.toUpperCase() ??
                                          'U',
                                      style: const TextStyle(
                                        fontSize: 36,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    )
                                  : null,
                            ),
                            const SizedBox(height: 15),
                            
                            // Username
                            Text(
                              userProfile!['username'] ?? 'Unknown User',
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            
                            // Email
                            Text(
                              userProfile!['email'] ?? '',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            const SizedBox(height: 20),
                            
                            // Action Button
                            _buildActionButton(),
                          ],
                        ),
                      ),
                      
                      const SizedBox(height: 30),
                      
                      // Friendship Status Info (for debugging/info)
                      if (friendshipStatus != null)
                        Container(
                          padding: const EdgeInsets.all(15),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Connection Status',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(_getStatusText(friendshipStatus!['status'])),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'accepted':
        return 'You are friends';
      case 'pending':
        if (friendshipStatus!['isOutgoing'] == true) {
          return 'Friend request sent';
        } else {
          return 'Friend request received';
        }
      case 'none':
      default:
        return 'Not connected';
    }
  }
}