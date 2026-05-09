// lib/services/presence_service.dart
// Tracks online status by writing a heartbeat timestamp to user_profiles
// and reading friends' last_seen_at to determine who is "online".

import 'dart:async';
import 'package:liver_wise/services/auth_service.dart';
import 'package:liver_wise/services/database_service_core.dart';
import 'package:liver_wise/services/friends_service.dart';

class PresenceService {
  static const Duration _onlineThreshold = Duration(minutes: 3);
  static const Duration _heartbeatInterval = Duration(minutes: 2);

  static Timer? _heartbeatTimer;

  // ── Start sending heartbeats (call once on app foreground) ──────────────
  static void startHeartbeat() {
    _sendHeartbeat(); // immediate first beat
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) => _sendHeartbeat());
  }

  // ── Stop heartbeats (call on app background / logout) ───────────────────
  static void stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  // ── Write current user's last_seen_at to their profile ──────────────────
  static Future<void> _sendHeartbeat() async {
    final userId = AuthService.currentUserId;
    if (userId == null) return;

    try {
      await DatabaseServiceCore.workerQuery(
        action: 'update',
        table: 'user_profiles',
        filters: {'id': userId},
        data: {
          'last_seen_at': DateTime.now().toUtc().toIso8601String(),
        },
      );
    } catch (_) {
      // Silently fail — presence is non-critical
    }
  }

  // ── Get online friends ───────────────────────────────────────────────────
  // Returns friends whose last_seen_at is within _onlineThreshold.
  static Future<List<Map<String, dynamic>>> getOnlineFriends() async {
    final userId = AuthService.currentUserId;
    if (userId == null) return [];

    try {
      // Reuse existing FriendsService which already handles the OR-filter
      // limitation by fetching all rows and filtering Dart-side.
      final friends = await FriendsService.getFriends();

      if (friends.isEmpty) return [];

      // For each friend, fetch their last_seen_at from user_profiles.
      // We need this field which getFriends() doesn't currently return,
      // so we pull it individually. In practice friend lists are small.
      final List<Map<String, dynamic>> onlineFriends = [];
      final cutoff = DateTime.now().toUtc().subtract(_onlineThreshold);

      for (final friend in friends) {
        final friendId = friend['id'];
        if (friendId == null) continue;

        try {
          final rows = await DatabaseServiceCore.workerQuery(
            action: 'select',
            table: 'user_profiles',
            columns: ['id', 'username', 'avatar_url', 'last_seen_at'],
            filters: {'id': friendId},
            limit: 1,
          );

          if (rows == null || (rows as List).isEmpty) continue;

          final profile = rows[0] as Map<String, dynamic>;
          final lastSeenRaw = profile['last_seen_at'];

          if (lastSeenRaw == null) continue;

          final lastSeen = DateTime.tryParse(lastSeenRaw.toString());
          if (lastSeen == null) continue;

          if (lastSeen.isAfter(cutoff)) {
            onlineFriends.add({
              'id': profile['id'],
              'username': profile['username'] ?? 'User',
              'avatar_url': profile['avatar_url'],
            });
          }
        } catch (_) {
          continue;
        }
      }

      return onlineFriends;
    } catch (_) {
      return [];
    }
  }
}