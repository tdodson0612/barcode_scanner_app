// lib/services/messaging_service.dart
// Handles all direct messaging features (send, read, list, caching)

import 'dart:convert';
import '../config/app_config.dart';

import 'auth_service.dart';                 // currentUserId + auth
import 'friends_service.dart';              // getFriends()
import 'database_service_core.dart';        // workerQuery + cache helpers


class MessagingService {

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
            await DatabaseServiceCore.cacheData(lastKey, DateTime.now().toIso8601String());
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
      await DatabaseServiceCore.cacheData(lastKey, DateTime.now().toIso8601String());

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
          'is_read': false,
          'created_at': DateTime.now().toIso8601String(),
        },
      );

      // Clear cache for that chat
      await DatabaseServiceCore.clearCache('cache_messages_${uid}_$receiverId');
      await DatabaseServiceCore.clearCache('cache_last_message_time_${uid}_$receiverId');
    } catch (e) {
      throw Exception('Failed to send message: $e');
    }
  }

  // ==============================================
  // UNREAD MESSAGE COUNT
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
          'is_read': false,
        },
      );

      return (response as List).length;
    } catch (e) {
      return 0;
    }
  }

  // ==============================================
  // MARK SINGLE MESSAGE READ
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
    } catch (_) {}
  }

  // ==============================================
  // MARK ALL MESSAGES FROM USER AS READ
  // ==============================================
  static Future<void> markMessagesAsReadFrom(String senderId) async {
    if (AuthService.currentUserId == null) return;

    try {
      final uid = AuthService.currentUserId!;

      final messages = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'messages',
        columns: ['id'],
        filters: {
          'receiver': uid,
          'sender': senderId,
          'is_read': false,
        },
      );

      for (var msg in messages as List) {
        await DatabaseServiceCore.workerQuery(
          action: 'update',
          table: 'messages',
          filters: {'id': msg['id']},
          data: {'is_read': true},
        );
      }
    } catch (_) {}
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
      
      // FRIENDS come from FriendsService now
      final friends = await FriendsService.getFriends();

      // ALL messages
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

        for (var msg in allMessages as List) {
          if ((msg['sender'] == uid && msg['receiver'] == fid) ||
              (msg['sender'] == fid && msg['receiver'] == uid)) {
            lastMessage = msg;
            break;
          }
        }

        chats.add({
          'friend': f,
          'lastMessage': lastMessage,
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
}
