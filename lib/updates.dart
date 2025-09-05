// ==================================================
// UPDATED DATABASE SERVICE - ADD THESE SOCIAL METHODS
// ==================================================

// Add these methods to your existing database_service.dart:

  // Helper method to ensure user is authenticated
  static void ensureUserAuthenticated() {
    if (!isUserLoggedIn) {
      throw Exception('User not authenticated');
    }
  }

  // ==================================================
  // SOCIAL FEATURES - FRIENDS & MESSAGING
  // ==================================================

  /// Fetch friends list (accepted friend requests)
  static Future<List<Map<String, dynamic>>> getFriends() async {
    ensureUserAuthenticated();
    
    try {
      final response = await _supabase
          .from('friend_requests')
          .select('sender:user_profiles!friend_requests_sender_fkey(id, email, username, avatar_url), receiver:user_profiles!friend_requests_receiver_fkey(id, email, username, avatar_url)')
          .or('sender.eq.$currentUserId,receiver.eq.$currentUserId')
          .eq('status', 'accepted');

      final friends = <Map<String, dynamic>>[];
      for (var row in response) {
        final friend = row['sender']['id'] == currentUserId 
            ? row['receiver'] 
            : row['sender'];
        friends.add(friend);
      }
      return friends;
    } catch (e) {
      print('Error fetching friends: $e');
      return [];
    }
  }

  /// Get pending friend requests (received)
  static Future<List<Map<String, dynamic>>> getFriendRequests() async {
    ensureUserAuthenticated();
    
    try {
      final response = await _supabase
          .from('friend_requests')
          .select('id, sender:user_profiles!friend_requests_sender_fkey(id, email, username, avatar_url)')
          .eq('receiver', currentUserId!)
          .eq('status', 'pending');

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error fetching friend requests: $e');
      return [];
    }
  }

  /// Send friend request
  static Future<String?> sendFriendRequest(String receiverId) async {
    ensureUserAuthenticated();
    
    try {
      // Check if request already exists
      final existing = await _supabase
          .from('friend_requests')
          .select('id, status')
          .or('and(sender.eq.$currentUserId,receiver.eq.$receiverId),and(sender.eq.$receiverId,receiver.eq.$currentUserId)')
          .maybeSingle();

      if (existing != null) {
        if (existing['status'] == 'accepted') {
          throw Exception('Already friends');
        } else if (existing['status'] == 'pending') {
          throw Exception('Friend request already sent');
        }
      }

      final response = await _supabase
          .from('friend_requests')
          .insert({
            'sender': currentUserId!,
            'receiver': receiverId,
            'status': 'pending',
          })
          .select()
          .single();

      return response['id'];
    } catch (e) {
      print('Error sending friend request: $e');
      rethrow;
    }
  }

  /// Accept friend request
  static Future<void> acceptFriendRequest(String requestId) async {
    ensureUserAuthenticated();
    
    try {
      await _supabase
          .from('friend_requests')
          .update({'status': 'accepted'})
          .eq('id', requestId);
    } catch (e) {
      print('Error accepting friend request: $e');
      rethrow;
    }
  }

  /// Decline/Cancel friend request (deletes completely)
  static Future<void> declineFriendRequest(String requestId) async {
    ensureUserAuthenticated();
    
    try {
      await _supabase
          .from('friend_requests')
          .delete()
          .eq('id', requestId);
    } catch (e) {
      print('Error declining friend request: $e');
      rethrow;
    }
  }

  /// Cancel outgoing friend request
  static Future<void> cancelFriendRequest(String receiverId) async {
    ensureUserAuthenticated();
    
    try {
      await _supabase
          .from('friend_requests')
          .delete()
          .eq('sender', currentUserId!)
          .eq('receiver', receiverId);
    } catch (e) {
      print('Error canceling friend request: $e');
      rethrow;
    }
  }

  /// Check friendship status
  static Future<Map<String, dynamic>> checkFriendshipStatus(String userId) async {
    ensureUserAuthenticated();
    
    try {
      final response = await _supabase
          .from('friend_requests')
          .select('id, status, sender, receiver')
          .or('and(sender.eq.$currentUserId,receiver.eq.$userId),and(sender.eq.$userId,receiver.eq.$currentUserId)')
          .maybeSingle();

      if (response == null) {
        return {'status': 'none', 'requestId': null, 'canSendRequest': true};
      }

      final isOutgoing = response['sender'] == currentUserId;
      final status = response['status'];

      return {
        'status': status,
        'requestId': response['id'],
        'isOutgoing': isOutgoing,
        'canSendRequest': false,
      };
    } catch (e) {
      print('Error checking friendship status: $e');
      return {'status': 'none', 'requestId': null, 'canSendRequest': true};
    }
  }

  /// Get messages between two users
  static Future<List<Map<String, dynamic>>> getMessages(String friendId) async {
    ensureUserAuthenticated();
    
    try {
      final response = await _supabase
          .from('messages')
          .select('*')
          .or('and(sender.eq.$currentUserId,receiver.eq.$friendId),and(sender.eq.$friendId,receiver.eq.$currentUserId)')
          .order('created_at');

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error fetching messages: $e');
      return [];
    }
  }

  /// Send message
  static Future<void> sendMessage(String receiverId, String content) async {
    ensureUserAuthenticated();
    
    try {
      await _supabase.from('messages').insert({
        'sender': currentUserId!,
        'receiver': receiverId,
        'content': content,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      print('Error sending message: $e');
      rethrow;
    }
  }

  /// Get chat list (recent conversations)
  static Future<List<Map<String, dynamic>>> getChatList() async {
    ensureUserAuthenticated();
    
    try {
      // Get latest message with each friend
      final friends = await getFriends();
      final chats = <Map<String, dynamic>>[];

      for (final friend in friends) {
        final messages = await _supabase
            .from('messages')
            .select('*')
            .or('and(sender.eq.$currentUserId,receiver.eq.${friend['id']}),and(sender.eq.${friend['id']},receiver.eq.$currentUserId)')
            .order('created_at', ascending: false)
            .limit(1);

        if (messages.isNotEmpty) {
          chats.add({
            'friend': friend,
            'lastMessage': messages.first,
          });
        } else {
          chats.add({
            'friend': friend,
            'lastMessage': null,
          });
        }
      }

      // Sort by last message time
      chats.sort((a, b) {
        final aTime = a['lastMessage']?['created_at'];
        final bTime = b['lastMessage']?['created_at'];
        if (aTime == null && bTime == null) return 0;
        if (aTime == null) return 1;
        if (bTime == null) return -1;
        return bTime.compareTo(aTime);
      });

      return chats;
    } catch (e) {
      print('Error fetching chat list: $e');
      return [];
    }
  }

  /// Search users (for adding friends)
  static Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    ensureUserAuthenticated();
    
    try {
      final response = await _supabase
          .from('user_profiles')
          .select('id, email, username, avatar_url')
          .or('email.ilike.%$query%,username.ilike.%$query%')
          .neq('id', currentUserId!)
          .limit(20);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error searching users: $e');
      return [];
    }
  }

// ==================================================
// MAIN.DART ROUTES - ADD THESE TO YOUR EXISTING ROUTES
// ==================================================

// 1. Add these imports to the top of your main.dart:
import 'pages/search_users_page.dart';
import 'pages/chat_page.dart';
import 'pages/user_profile_page.dart';

// 2. Add these routes to your existing routes map in main.dart:
'/search-users': (context) => AuthWrapper(child: SearchUsersPage()),
// Note: chat_page and user_profile_page don't need routes since they're navigated to directly

// ==================================================
// PROFILE SCREEN - ADD FRIENDS SECTION
// ==================================================

// Add this method to your existing ProfileScreen class:

Widget _buildFriendsListSection() {
  return PremiumGate(
    feature: PremiumFeature.socialMessaging, // Always available
    featureName: 'Friends List',
    child: _sectionContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(
                    'Friends',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(width: 8),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.green,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'FREE',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              TextButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => SearchUsersPage()),
                  );
                },
                child: Text('Find Friends'),
              ),
            ],
          ),
          SizedBox(height: 12),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: DatabaseService.getFriends(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError) {
                return Text('Error: ${snapshot.error}');
              }

              final friends = snapshot.data ?? [];
              
              if (friends.isEmpty) {
                return Container(
                  padding: EdgeInsets.all(20),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(Icons.people, size: 48, color: Colors.grey),
                        SizedBox(height: 12),
                        Text(
                          'No friends yet',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Search for friends to connect and chat!',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 14,
                          ),
                        ),
                        SizedBox(height: 12),
                        ElevatedButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => SearchUsersPage()),
                            );
                          },
                          icon: Icon(Icons.search),
                          label: Text('Find Friends'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return SizedBox(
                height: 200,
                child: ListView.builder(
                  itemCount: friends.length,
                  itemBuilder: (context, index) {
                    final friend = friends[index];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundImage: friend['avatar_url'] != null
                            ? NetworkImage(friend['avatar_url'])
                            : null,
                        child: friend['avatar_url'] == null
                            ? Text(friend['username']?[0]?.toUpperCase() ?? 'U')
                            : null,
                      ),
                      title: Text(friend['username'] ?? friend['email'] ?? 'Unknown'),
                      trailing: IconButton(
                        icon: Icon(Icons.message, color: Colors.green),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ChatPage(
                                friendId: friend['id'],
                                friendName: friend['username'] ?? friend['email'] ?? 'Unknown',
                                friendAvatar: friend['avatar_url'],
                              ),
                            ),
                          );
                        },
                      ),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => UserProfilePage(userId: friend['id']),
                          ),
                        );
                      },
                    );
                  },
                ),
              );
            },
          ),
        ],
      ),
    ),
  );
}

// Then ADD this to your ProfileScreen build method after the premium status section:
const SizedBox(height: 20),
_buildFriendsListSection(),

// ==================================================
// CREATE THESE NEW FILES
// ==================================================

// You still need to create these three page files:
// 1. lib/pages/search_users_page.dart
// 2. lib/pages/user_profile_page.dart  
// 3. lib/pages/chat_page.dart (already provided separately)

// ==================================================
// DATABASE SCHEMA SQL (RUN IN SUPABASE)
// ==================================================

/*
Run this SQL in your Supabase SQL Editor to set up the social features:

-- Add username and avatar fields to existing user_profiles table
ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS username TEXT;
ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS avatar_url TEXT;

-- Update existing users to have a default username based on email
UPDATE user_profiles 
SET username = split_part(email, '@', 1) 
WHERE username IS NULL AND email IS NOT NULL;

-- Create index on username for faster searches
CREATE INDEX IF NOT EXISTS idx_user_profiles_username ON user_profiles(username);
CREATE INDEX IF NOT EXISTS idx_user_profiles_email ON user_profiles(email);

-- Friend requests table
CREATE TABLE IF NOT EXISTS friend_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  sender UUID REFERENCES user_profiles(id) ON DELETE CASCADE,
  receiver UUID REFERENCES user_profiles(id) ON DELETE CASCADE,
  status TEXT CHECK (status IN ('pending', 'accepted')) DEFAULT 'pending',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(sender, receiver)
);

-- Messages table
CREATE TABLE IF NOT EXISTS messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  sender UUID REFERENCES user_profiles(id) ON DELETE CASCADE,
  receiver UUID REFERENCES user_profiles(id) ON DELETE CASCADE,
  content TEXT NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Indexes for better performance
CREATE INDEX IF NOT EXISTS idx_friend_requests_receiver ON friend_requests(receiver);
CREATE INDEX IF NOT EXISTS idx_friend_requests_sender ON friend_requests(sender);
CREATE INDEX IF NOT EXISTS idx_friend_requests_status ON friend_requests(status);
CREATE INDEX IF NOT EXISTS idx_messages_sender_receiver ON messages(sender, receiver);
CREATE INDEX IF NOT EXISTS idx_messages_created_at ON messages(created_at DESC);

-- Row Level Security (RLS) policies
ALTER TABLE friend_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;

-- Friend requests policies
CREATE POLICY "Users can view their own friend requests" ON friend_requests
  FOR SELECT USING (auth.uid() = sender OR auth.uid() = receiver);

CREATE POLICY "Users can send friend requests" ON friend_requests
  FOR INSERT WITH CHECK (auth.uid() = sender);

CREATE POLICY "Users can update their received requests" ON friend_requests
  FOR UPDATE USING (auth.uid() = receiver);

CREATE POLICY "Users can delete their sent/received requests" ON friend_requests
  FOR DELETE USING (auth.uid() = sender OR auth.uid() = receiver);

-- Messages policies
CREATE POLICY "Users can view their own messages" ON messages
  FOR SELECT USING (auth.uid() = sender OR auth.uid() = receiver);

CREATE POLICY "Users can send messages" ON messages
  FOR INSERT WITH CHECK (auth.uid() = sender);

CREATE POLICY "Users can delete their own messages" ON messages
  FOR DELETE USING (auth.uid() = sender);

-- Update trigger for friend_requests
CREATE OR REPLACE FUNCTION update_friend_requests_updated_at()
RETURNS TRIGGER AS $
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$ language 'plpgsql';

CREATE TRIGGER update_friend_requests_updated_at 
    BEFORE UPDATE ON friend_requests 
    FOR EACH ROW EXECUTE FUNCTION update_friend_requests_updated_at();
*/

// ==================================================
// WHAT YOU STILL NEED TO DO:
// ==================================================

/*
1. Add all the database methods above to your database_service.dart
2. Add the imports to your main.dart
3. Add the /search-users route to your main.dart routes
4. Add the _buildFriendsListSection() method to your ProfileScreen
5. Add the friends section to your ProfileScreen build method
6. Run the SQL schema in Supabase
7. Create the missing page files:
   - search_users_page.dart
   - user_profile_page.dart
   - chat_page.dart (already provided)
*/