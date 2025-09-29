// lib/pages/user_profile_page.dart - FIXED: Enhanced with ErrorHandlingService integration
import 'package:flutter/material.dart';
import '../services/database_service.dart';
import '../services/error_handling_service.dart';
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

      // Get user profile and friendship status concurrently
      final results = await Future.wait([
        DatabaseService.getUserProfile(widget.userId),
        DatabaseService.checkFriendshipStatus(widget.userId),
      ]);

      if (mounted) {
        setState(() {
          userProfile = results[0];        // already Map<String, dynamic>?
          friendshipStatus = results[1];   // already Map<String, dynamic>
          isLoading = false;
        });
      }

    } catch (e) {
      if (mounted) {
        setState(() => isLoading = false);

        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          category: ErrorHandlingService.databaseError,
          showSnackBar: true,
          customMessage: 'Unable to load user profile',
          onRetry: _loadUserProfile,
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

      // Refresh friendship status
      final status = await DatabaseService.checkFriendshipStatus(widget.userId);

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

      // Refresh friendship status
      final status = await DatabaseService.checkFriendshipStatus(widget.userId);

      if (mounted) {
        setState(() {
          friendshipStatus = status;
          isActionLoading = false;
        });

        ErrorHandlingService.showSuccess(
            context, 'Friend request accepted! You are now friends.');
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

    // Show confirmation dialog
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

      // Refresh friendship status
      final status = await DatabaseService.checkFriendshipStatus(widget.userId);

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

  void _openChat() {
    try {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatPage(
            friendId: widget.userId,
            friendName: userProfile?['username'] ??
                userProfile?['email'] ??
                'Unknown',
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
          // User sent the request
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
          // User received the request
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
                await _loadUserProfile();
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
                  onRefresh: _loadUserProfile,
                  child: SingleChildScrollView(
                    physics: AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        // Profile Header Card
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
                              // Avatar
                              CircleAvatar(
                                radius: 50,
                                backgroundColor: Colors.grey.shade200,
                                backgroundImage:
                                    userProfile!['avatar_url'] != null
                                        ? NetworkImage(
                                            userProfile!['avatar_url'])
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

                              // Display Name
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

                              // Action Button
                              _buildActionButton(),
                            ],
                          ),
                        ),

                        const SizedBox(height: 24),

                        // Connection Status Card
                        if (friendshipStatus != null)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.info_outline,
                                    color: Colors.blueGrey),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'Current status: ${friendshipStatus!['status']}',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.black87,
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
}
