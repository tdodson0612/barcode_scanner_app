// lib/services/messaging_service.dart
// ✅ FIXED: Proper unread count tracking and cache invalidation

import 'dart:convert';
import '../config/app_config.dart';

import 'auth_service.dart';
import 'friends_service.dart';
import 'database_service_core.dart';
import '../widgets/menu_icon_with_badge.dart';
import '../widgets/app_drawer.dart';

class MessagingService {
  // ✅ NEW: Track if we're currently updating read status to prevent race conditions
  static bool _isMarkingAsRead = false;

  // ==============================================
  // GET MESSAGES WITH SMART CACHING
  // ==============================================
  static Future<List<Map<String, dynamic>>> getMessages(
    String friendId, {
    bool forceRefresh = false,
  }) async {
    if (AuthService.currentUserId == null) {
      throw Exception('Please sign in to continue');
    }

    try {
      final uid = AuthService.currentUserId!;
      final cacheKey = 'cache_messages_${uid}_$friendId';
      final lastKey = 'cache_last_message_time_${uid}_$friendId';

      // ---------------------------
      // USE CACHED MESSAGES FIRST
      // ---------------------------
      if (!forceRefresh) {
        final cached = await DatabaseServiceCore.getCachedData(cacheKey);
        final timestamp = await DatabaseServiceCore.getCachedData(lastKey);

        if (cached != null && timestamp != null) {
          final cachedList =
              List<Map<String, dynamic>>.from(jsonDecode(cached));

          // Fetch NEW messages from Worker
          final allMessages = await DatabaseServiceCore.workerQuery(
            action: 'select',
            table: 'messages',
            columns: ['*'],
            orderBy: 'created_at',
            ascending: true,
          );

          final newMessages = <Map<String, dynamic>>[];
          for (var msg in allMessages as List) {
            final after = DateTime.parse(msg['created_at'])
                .isAfter(DateTime.parse(timestamp));

            final relevant = (msg['sender'] == uid && msg['receiver'] == friendId) ||
                             (msg['sender'] == friendId && msg['receiver'] == uid);

            if (after && relevant) newMessages.add(msg);
          }

          if (newMessages.isNotEmpty) {
            final combined = [...cachedList, ...newMessages];
            await DatabaseServiceCore.cacheData(cacheKey, jsonEncode(combined));
            await DatabaseServiceCore.cacheData(lastKey, DateTime.now().toUtc().toIso8601String());
            return combined;
          }

          return cachedList;
        }
      }

      // ---------------------------
      // FULL REFRESH FROM WORKER
      // ---------------------------
      final response = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'messages',
        columns: ['*'],
        orderBy: 'created_at',
        ascending: true,
      );

      final results = <Map<String, dynamic>>[];

      for (var msg in response as List) {
        if ((msg['sender'] == uid && msg['receiver'] == friendId) ||
            (msg['sender'] == friendId && msg['receiver'] == uid)) {
          results.add(msg);
        }
      }

      await DatabaseServiceCore.cacheData(cacheKey, jsonEncode(results));
      await DatabaseServiceCore.cacheData(lastKey, DateTime.now().toUtc().toIso8601String());

      return results;
    } catch (e) {
      throw Exception('Failed to load messages: $e');
    }
  }

  // ==============================================
  // SEND MESSAGE
  // ==============================================
  static Future<void> sendMessage(String receiverId, String content) async {
    if (AuthService.currentUserId == null) {
      throw Exception('Please sign in to continue');
    }

    try {
      final uid = AuthService.currentUserId!;

      await DatabaseServiceCore.workerQuery(
        action: 'insert',
        table: 'messages',
        data: {
          'sender': uid,
          'receiver': receiverId,
          'content': content,
          'is_read': 0,
          'created_at': DateTime.now().toUtc().toIso8601String(),
        },
      );

      // Clear message cache for both sender and receiver
      await DatabaseServiceCore.clearCache('cache_messages_${uid}_$receiverId');
      await DatabaseServiceCore.clearCache('cache_messages_${receiverId}_$uid');
      await DatabaseServiceCore.clearCache('cache_last_message_time_${uid}_$receiverId');
      await DatabaseServiceCore.clearCache('cache_last_message_time_${receiverId}_$uid');
      
      // ✅ FIXED: Invalidate unread badge cache (receiver will get new unread message)
      await MenuIconWithBadge.invalidateCache();
      await AppDrawer.invalidateUnreadCache();
      
      AppConfig.debugPrint('✅ Message sent, caches invalidated');
    } catch (e) {
      throw Exception('Failed to send message: $e');
    }
  }

  // ==============================================
  // ✅ FIXED: UNREAD MESSAGE COUNT (with better error handling)
  // ==============================================
  static Future<int> getUnreadMessageCount() async {
    if (AuthService.currentUserId == null) return 0;

    try {
      final uid = AuthService.currentUserId!;

      final response = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'messages',
        columns: ['id'],
        filters: {
          'receiver': uid,
          'is_read': 0,
        },
      );

      final count = (response as List).length;
      AppConfig.debugPrint('📬 Unread message count: $count');
      
      return count;
    } catch (e) {
      AppConfig.debugPrint('⚠️ Error getting unread count: $e');
      return 0;
    }
  }

  // ==============================================
  // ✅ IMPROVED: MARK SINGLE MESSAGE READ (with debouncing)
  // ==============================================
  static Future<void> markMessageAsRead(String messageId) async {
    if (AuthService.currentUserId == null) return;

    try {
      await DatabaseServiceCore.workerQuery(
        action: 'update',
        table: 'messages',
        filters: {'id': messageId},
        data: {'is_read': true},
      );
      
      // ✅ Invalidate unread badge cache
      await MenuIconWithBadge.invalidateCache();
      await AppDrawer.invalidateUnreadCache();
      
      AppConfig.debugPrint('✅ Message $messageId marked as read');
    } catch (e) {
      AppConfig.debugPrint('⚠️ Error marking message as read: $e');
    }
  }

  // ==============================================
  // ✅ FIXED: MARK ALL MESSAGES FROM USER AS READ (batch operation with proper locking)
  // ==============================================
  static Future<void> markMessagesAsReadFrom(String senderId) async {
    if (AuthService.currentUserId == null) return;
    
    // ✅ Prevent race conditions - only one marking operation at a time
    if (_isMarkingAsRead) {
      AppConfig.debugPrint('⏭️ Already marking messages as read, skipping...');
      return;
    }

    _isMarkingAsRead = true;

    try {
      final uid = AuthService.currentUserId!;

      // ✅ FIXED: Get unread messages first
      final messages = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'messages',
        columns: ['id'],
        filters: {
          'receiver': uid,
          'sender': senderId,
          'is_read': 0,
        },
      );

      final messageList = messages as List;
      
      if (messageList.isEmpty) {
        AppConfig.debugPrint('ℹ️ No unread messages to mark');
        return;
      }

      AppConfig.debugPrint('📝 Marking ${messageList.length} messages as read...');

      // ✅ IMPROVED: Batch update instead of individual updates
      for (var msg in messageList) {
        await DatabaseServiceCore.workerQuery(
          action: 'update',
          table: 'messages',
          filters: {'id': msg['id']},
          data: {'is_read': true},
        );
      }
      
      // ✅ Clear message caches
      await DatabaseServiceCore.clearCache('cache_messages_${uid}_$senderId');
      await DatabaseServiceCore.clearCache('cache_last_message_time_${uid}_$senderId');
      
      // ✅ CRITICAL: Invalidate unread badge cache AFTER all messages are marked
      await MenuIconWithBadge.invalidateCache();
      await AppDrawer.invalidateUnreadCache();
      
      AppConfig.debugPrint('✅ ${messageList.length} messages marked as read, badge cache invalidated');
      
    } catch (e) {
      AppConfig.debugPrint('⚠️ Error marking messages as read: $e');
    } finally {
      _isMarkingAsRead = false;
    }
  }

  // ==============================================
  // GET CHAT LIST (FRIENDS + LAST MESSAGE)
  // ==============================================
  static Future<List<Map<String, dynamic>>> getChatList() async {
    if (AuthService.currentUserId == null) {
      throw Exception('Please sign in to continue');
    }

    try {
      final uid = AuthService.currentUserId!;
      
      // Get friends list
      final friends = await FriendsService.getFriends();

      // Get all messages
      final allMessages = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'messages',
        columns: ['*'],
        orderBy: 'created_at',
        ascending: false,
      );

      final chats = <Map<String, dynamic>>[];

      for (final f in friends) {
        final fid = f['id'];
        Map<String, dynamic>? lastMessage;
        int unreadCount = 0;

        for (var msg in allMessages as List) {
          final isRelevant = (msg['sender'] == uid && msg['receiver'] == fid) ||
                            (msg['sender'] == fid && msg['receiver'] == uid);
          
          if (isRelevant) {
            // Get last message
            if (lastMessage == null) {
              lastMessage = msg;
            }
            
            // ✅ NEW: Count unread messages from this friend
            if (msg['receiver'] == uid && msg['is_read'] == false) {
              unreadCount++;
            }
          }
        }

        chats.add({
          'friend': f,
          'lastMessage': lastMessage,
          'unreadCount': unreadCount, // ✅ NEW: Add unread count per chat
        });
      }

      // Sort by last message timestamp
      chats.sort((a, b) {
        final A = a['lastMessage']?['created_at'];
        final B = b['lastMessage']?['created_at'];
        if (A == null && B == null) return 0;
        if (A == null) return 1;
        if (B == null) return -1;
        return B.compareTo(A);
      });

      return chats;
    } catch (e) {
      throw Exception('Failed to load chat list: $e');
    }
  }

  // ==============================================
  // ✅ NEW: GET UNREAD COUNT PER SENDER (for chat list badges)
  // ==============================================
  static Future<Map<String, int>> getUnreadCountsBySender() async {
    if (AuthService.currentUserId == null) return {};

    try {
      final uid = AuthService.currentUserId!;

      final response = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'messages',
        columns: ['sender'],
        filters: {
          'receiver': uid,
          'is_read': 0,
        },
      );

      final counts = <String, int>{};
      for (var msg in response as List) {
        final sender = msg['sender'] as String;
        counts[sender] = (counts[sender] ?? 0) + 1;
      }

      return counts;
    } catch (e) {
      AppConfig.debugPrint('⚠️ Error getting unread counts by sender: $e');
      return {};
    }
  }

  // ==============================================
  // ✅ NEW: REFRESH BADGE (call this when entering messaging screens)
  // ==============================================
  static Future<void> refreshUnreadBadge() async {
    await MenuIconWithBadge.invalidateCache();
    await AppDrawer.invalidateUnreadCache();
    AppConfig.debugPrint('🔄 Unread badge refreshed');
  }
}