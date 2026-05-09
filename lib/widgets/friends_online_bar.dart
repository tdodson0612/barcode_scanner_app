// lib/widgets/friends_online_bar.dart
// Horizontal scrollable row showing which friends are currently online.
// Polls every 2 minutes to stay in sync with the presence heartbeat interval.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:liver_wise/services/presence_service.dart';

class FriendsOnlineBar extends StatefulWidget {
  const FriendsOnlineBar({super.key});

  @override
  State<FriendsOnlineBar> createState() => _FriendsOnlineBarState();
}

class _FriendsOnlineBarState extends State<FriendsOnlineBar> {
  List<Map<String, dynamic>> _onlineFriends = [];
  bool _isLoading = true;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _load();
    _refreshTimer = Timer.periodic(const Duration(minutes: 2), (_) => _load());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final friends = await PresenceService.getOnlineFriends();
      if (mounted) {
        setState(() {
          _onlineFriends = friends;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha((0.95 * 255).toInt()),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──────────────────────────────────────────────
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Colors.green,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'Friends Online',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(width: 6),
              if (!_isLoading)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: _onlineFriends.isEmpty
                        ? Colors.grey.shade200
                        : Colors.green.shade100,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${_onlineFriends.length}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: _onlineFriends.isEmpty
                          ? Colors.grey.shade600
                          : Colors.green.shade800,
                    ),
                  ),
                ),
            ],
          ),

          const SizedBox(height: 12),

          // ── Body ────────────────────────────────────────────────
          if (_isLoading)
            _buildSkeletonRow()
          else if (_onlineFriends.isEmpty)
            Text(
              'None of your friends are online right now.',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade500,
              ),
            )
          else
            SizedBox(
              height: 72,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _onlineFriends.length,
                separatorBuilder: (_, __) => const SizedBox(width: 16),
                itemBuilder: (context, index) {
                  final friend = _onlineFriends[index];
                  return _FriendAvatar(
                    username: friend['username'] ?? 'User',
                    avatarUrl: friend['avatar_url'],
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSkeletonRow() {
    return SizedBox(
      height: 72,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: 4,
        separatorBuilder: (_, __) => const SizedBox(width: 16),
        itemBuilder: (_, __) => const _SkeletonAvatar(),
      ),
    );
  }
}

// ── Individual friend avatar with green online dot ───────────────────────────
class _FriendAvatar extends StatelessWidget {
  final String username;
  final String? avatarUrl;

  const _FriendAvatar({required this.username, this.avatarUrl});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: Colors.green.shade100,
              backgroundImage: avatarUrl != null && avatarUrl!.isNotEmpty
                  ? NetworkImage(avatarUrl!)
                  : null,
              child: (avatarUrl == null || avatarUrl!.isEmpty)
                  ? Text(
                      username.isNotEmpty ? username[0].toUpperCase() : '?',
                      style: TextStyle(
                        color: Colors.green.shade800,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    )
                  : null,
            ),
            // Green online dot
            Positioned(
              bottom: 0,
              right: 0,
              child: Container(
                width: 13,
                height: 13,
                decoration: BoxDecoration(
                  color: Colors.green,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: 52,
          child: Text(
            username,
            style: const TextStyle(fontSize: 11, color: Colors.black87),
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}

// ── Shimmer-style skeleton placeholder ───────────────────────────────────────
class _SkeletonAvatar extends StatelessWidget {
  const _SkeletonAvatar();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: 40,
          height: 10,
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(5),
          ),
        ),
      ],
    );
  }
}