// lib/pages/chat_page.dart - FIXED: Proper message ordering and timezone display
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/database_service.dart';
import '../services/auth_service.dart';
import '../services/error_handling_service.dart';

class ChatPage extends StatefulWidget {
  final String friendId;
  final String friendName;
  final String? friendAvatar;

  const ChatPage({
    super.key,
    required this.friendId,
    required this.friendName,
    this.friendAvatar,
  });

  @override
  _ChatPageState createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  bool _isLoading = true;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _loadMessages();
    // Mark all messages from this friend as read
    DatabaseService.markMessagesAsReadFrom(widget.friendId);
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    try {
      setState(() => _isLoading = true);
      final messages = await DatabaseService.getMessages(widget.friendId);
      
      if (mounted) {
        // Sort messages by timestamp in ascending order (oldest to newest)
        messages.sort((a, b) {
          try {
            final timeA = DateTime.parse(a['created_at'] ?? '');
            final timeB = DateTime.parse(b['created_at'] ?? '');
            return timeA.compareTo(timeB); // Ascending order
          } catch (e) {
            return 0;
          }
        });
        
        setState(() {
          _messages = messages;
          _isLoading = false;
        });
        
        // Scroll to bottom after loading messages
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        
        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          category: ErrorHandlingService.databaseError,
          showSnackBar: true,
          customMessage: 'Unable to load messages',
          onRetry: _loadMessages,
        );
      }
    }
  }

  Future<void> _sendMessage() async {
    final content = _messageController.text.trim();
    if (content.isEmpty || _isSending) return;

    // Create temporary message for optimistic UI update
    final tempMessage = {
      'id': 'temp_${DateTime.now().millisecondsSinceEpoch}',
      'sender': AuthService.currentUserId,
      'receiver': widget.friendId,
      'content': content,
      'created_at': DateTime.now().toIso8601String(),
      'is_temp': true,
    };

    setState(() {
      _isSending = true;
      _messages.add(tempMessage); // Add to end (bottom)
    });

    _messageController.clear();
    _scrollToBottom();

    try {
      await DatabaseService.sendMessage(widget.friendId, content);
      
      if (mounted) {
        // Reload messages to get the actual message with proper ID
        await _loadMessages();
      }
    } catch (e) {
      if (mounted) {
        // Remove the optimistic message on error
        setState(() {
          _messages.removeWhere((msg) => msg['is_temp'] == true);
        });
        
        // Restore the message text to the input field
        _messageController.text = content;
        
        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          category: ErrorHandlingService.databaseError,
          customMessage: 'Failed to send message',
          onRetry: _sendMessage,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String _formatMessageTime(String timestamp) {
    try {
      // Parse the UTC timestamp from the database
      final utcDateTime = DateTime.parse(timestamp);
      
      // Convert to local timezone
      final localDateTime = utcDateTime.toLocal();
      
      final now = DateTime.now();
      final difference = now.difference(localDateTime);

      // If message is from today, show time only
      if (difference.inDays == 0 && localDateTime.day == now.day) {
        return DateFormat('h:mm a').format(localDateTime);
      }
      // If message is from yesterday
      else if (difference.inDays == 1 || 
               (localDateTime.day == now.day - 1 && localDateTime.month == now.month)) {
        return 'Yesterday ${DateFormat('h:mm a').format(localDateTime)}';
      }
      // If message is from this week (last 7 days)
      else if (difference.inDays < 7) {
        return DateFormat('EEE h:mm a').format(localDateTime); // "Mon 5:30 PM"
      }
      // If message is from this year
      else if (localDateTime.year == now.year) {
        return DateFormat('MMM d, h:mm a').format(localDateTime); // "Jan 15, 5:30 PM"
      }
      // Older messages include year
      else {
        return DateFormat('MMM d, y').format(localDateTime); // "Jan 15, 2024"
      }
    } catch (e) {
      print('Error formatting time: $e');
      return '';
    }
  }

  Widget _buildMessageBubble(Map<String, dynamic> message) {
    final isMe = message['sender'] == AuthService.currentUserId;
    final isTemp = message['is_temp'] == true;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.symmetric(vertical: 4, horizontal: 16),
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: isMe ? Colors.blue : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(20).copyWith(
            bottomRight: isMe ? Radius.circular(4) : Radius.circular(20),
            bottomLeft: isMe ? Radius.circular(20) : Radius.circular(4),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message['content'] ?? '',
              style: TextStyle(
                color: isMe ? Colors.white : Colors.black,
                fontSize: 16,
              ),
            ),
            SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _formatMessageTime(message['created_at'] ?? ''),
                  style: TextStyle(
                    color: isMe ? Colors.white70 : Colors.grey.shade600,
                    fontSize: 12,
                  ),
                ),
                if (isMe && isTemp) ...[
                  SizedBox(width: 4),
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: Colors.grey.shade300),
        ),
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _messageController,
                decoration: InputDecoration(
                  hintText: 'Type a message...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(25),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                ),
                maxLines: null,
                textCapitalization: TextCapitalization.sentences,
                onSubmitted: (_) => _sendMessage(),
                enabled: !_isSending,
              ),
            ),
            SizedBox(width: 8),
            Container(
              decoration: BoxDecoration(
                color: _isSending ? Colors.grey : Colors.blue,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                onPressed: _isSending ? null : _sendMessage,
                icon: _isSending
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : Icon(Icons.send, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundImage: widget.friendAvatar != null
                  ? NetworkImage(widget.friendAvatar!)
                  : null,
              child: widget.friendAvatar == null
                  ? Text(
                      widget.friendName.isNotEmpty
                          ? widget.friendName[0].toUpperCase()
                          : 'U',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    )
                  : null,
            ),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                widget.friendName,
                style: TextStyle(fontSize: 18),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 1,
        actions: [
          IconButton(
            onPressed: () async {
              try {
                await _loadMessages();
                if (mounted) {
                  ErrorHandlingService.showSuccess(context, 'Messages refreshed');
                }
              } catch (e) {
                if (mounted) {
                  await ErrorHandlingService.handleError(
                    context: context,
                    error: e,
                    category: ErrorHandlingService.databaseError,
                    showSnackBar: true,
                    customMessage: 'Failed to refresh messages',
                  );
                }
              }
            },
            icon: Icon(Icons.refresh),
            tooltip: 'Refresh messages',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text(
                          'Loading messages...',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  )
                : _messages.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.chat_bubble_outline,
                              size: 64,
                              color: Colors.grey.shade400,
                            ),
                            SizedBox(height: 16),
                            Text(
                              'No messages yet',
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.grey.shade600,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Send a message to start the conversation!',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey.shade500,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadMessages,
                        child: ListView.builder(
                          controller: _scrollController,
                          itemCount: _messages.length,
                          itemBuilder: (context, index) {
                            return _buildMessageBubble(_messages[index]);
                          },
                        ),
                      ),
          ),
          _buildMessageInput(),
        ],
      ),
    );
  }
}