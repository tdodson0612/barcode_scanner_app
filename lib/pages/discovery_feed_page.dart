// lib/pages/discovery_feed_page.dart - Discovery Feed (New Home Page)
import 'package:flutter/material.dart';
import '../services/database_service.dart';
import '../services/error_handling_service.dart';
import '../widgets/app_drawer.dart';
import '../pages/recipe_detail_page.dart';
import '../pages/create_post_page.dart';
import '../pages/user_profile_page.dart';

class DiscoveryFeedPage extends StatefulWidget {
  const DiscoveryFeedPage({super.key});

  @override
  State<DiscoveryFeedPage> createState() => _DiscoveryFeedPageState();
}

class _DiscoveryFeedPageState extends State<DiscoveryFeedPage> {
  List<Map<String, dynamic>> _posts = [];
  bool _isLoading = false;
  bool _hasMore = true;
  int _offset = 0;
  final int _limit = 20;
  String _sortBy = 'recent'; // 'recent', 'trending', 'following'
  
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadPosts();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= 
        _scrollController.position.maxScrollExtent - 200) {
      if (!_isLoading && _hasMore) {
        _loadMorePosts();
      }
    }
  }

  Future<void> _loadPosts({bool refresh = false}) async {
    if (refresh) {
      setState(() {
        _offset = 0;
        _posts = [];
        _hasMore = true;
      });
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final posts = await DatabaseService.getFeedPosts(
        limit: _limit,
        offset: _offset,
        sortBy: _sortBy,
      );

      if (mounted) {
        setState(() {
          if (refresh) {
            _posts = posts;
          } else {
            _posts.addAll(posts);
          }
          _hasMore = posts.length == _limit;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        
        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          category: ErrorHandlingService.databaseError,
          customMessage: 'Unable to load feed',
          onRetry: () => _loadPosts(refresh: refresh),
        );
      }
    }
  }

  Future<void> _loadMorePosts() async {
    setState(() {
      _offset += _limit;
    });
    await _loadPosts();
  }

  Future<void> _toggleLike(Map<String, dynamic> post, int index) async {
    final postId = post['id'];
    final isLiked = await DatabaseService.hasUserLikedPost(postId);

    try {
      if (isLiked) {
        await DatabaseService.unlikePost(postId);
      } else {
        await DatabaseService.likePost(postId);
      }

      // Refresh like count
      final likeCount = await DatabaseService.getPostLikeCount(postId);
      final userLiked = await DatabaseService.hasUserLikedPost(postId);

      if (mounted) {
        setState(() {
          _posts[index]['like_count'] = likeCount;
          _posts[index]['user_liked'] = userLiked;
        });
      }
    } catch (e) {
      if (mounted) {
        ErrorHandlingService.showSimpleError(context, 'Failed to update like');
      }
    }
  }

  void _navigateToRecipe(Map<String, dynamic> recipe) {
    if (recipe == null) return;
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RecipeDetailPage(
          recipeName: recipe['recipe_name'] ?? 'Recipe',
          ingredients: recipe['ingredients'] ?? '',
          directions: recipe['directions'] ?? '',
          recipeId: recipe['id'],
        ),
      ),
    );
  }

  void _navigateToUserProfile(String userId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => UserProfilePage(userId: userId),
      ),
    );
  }

  void _navigateToCreatePost() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CreatePostPage(),
      ),
    );

    if (result == true) {
      _loadPosts(refresh: true);
    }
  }

  Widget _buildPostCard(Map<String, dynamic> post, int index) {
    final user = post['user'] ?? {};
    final recipe = post['recipe'] ?? {};
    final username = user['username'] ?? 'Unknown User';
    final recipeName = recipe['recipe_name'] ?? 'Recipe';
    final caption = post['caption'] ?? '';
    final imageUrl = post['image_url'] ?? '';
    
    return FutureBuilder<Map<String, int>>(
      future: _getPostStats(post['id']),
      builder: (context, snapshot) {
        final stats = snapshot.data ?? {'likes': 0, 'comments': 0};
        final isLiked = snapshot.data?['is_liked'] == 1;
        
        return Card(
          margin: EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: User info
              ListTile(
                leading: GestureDetector(
                  onTap: () => _navigateToUserProfile(user['id']),
                  child: CircleAvatar(
                    backgroundImage: user['avatar_url'] != null
                        ? NetworkImage(user['avatar_url'])
                        : null,
                    child: user['avatar_url'] == null
                        ? Text(username[0].toUpperCase())
                        : null,
                  ),
                ),
                title: GestureDetector(
                  onTap: () => _navigateToUserProfile(user['id']),
                  child: Text(
                    username,
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                subtitle: Text(
                  _formatTimeAgo(post['created_at']),
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),

              // Image
              if (imageUrl.isNotEmpty)
                GestureDetector(
                  onDoubleTap: () => _toggleLike(post, index),
                  child: Image.network(
                    imageUrl,
                    width: double.infinity,
                    height: 300,
                    fit: BoxFit.cover,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return Container(
                        height: 300,
                        child: Center(
                          child: CircularProgressIndicator(
                            value: loadingProgress.expectedTotalBytes != null
                                ? loadingProgress.cumulativeBytesLoaded /
                                    loadingProgress.expectedTotalBytes!
                                : null,
                          ),
                        ),
                      );
                    },
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        height: 300,
                        color: Colors.grey.shade200,
                        child: Center(
                          child: Icon(Icons.broken_image, size: 50),
                        ),
                      );
                    },
                  ),
                ),

              // Action buttons
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        isLiked ? Icons.favorite : Icons.favorite_border,
                        color: isLiked ? Colors.red : null,
                      ),
                      onPressed: () => _toggleLike(post, index),
                    ),
                    Text('${stats['likes']}'),
                    SizedBox(width: 16),
                    IconButton(
                      icon: Icon(Icons.comment_outlined),
                      onPressed: () => _navigateToRecipe(recipe),
                    ),
                    Text('${stats['comments']}'),
                    Spacer(),
                    IconButton(
                      icon: Icon(Icons.bookmark_border),
                      onPressed: () {
                        // TODO: Implement save post
                      },
                    ),
                  ],
                ),
              ),

              // Recipe tag
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: GestureDetector(
                  onTap: () => _navigateToRecipe(recipe),
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.green.shade300),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.restaurant_menu, size: 16, color: Colors.green),
                        SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            recipeName,
                            style: TextStyle(
                              color: Colors.green.shade800,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Caption
              if (caption.isNotEmpty)
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: RichText(
                    text: TextSpan(
                      style: TextStyle(color: Colors.black),
                      children: [
                        TextSpan(
                          text: '$username ',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        TextSpan(text: caption),
                      ],
                    ),
                  ),
                ),

              SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Future<Map<String, int>> _getPostStats(String postId) async {
    try {
      final likes = await DatabaseService.getPostLikeCount(postId);
      final isLiked = await DatabaseService.hasUserLikedPost(postId);
      // TODO: Get comment count when implemented
      return {
        'likes': likes,
        'comments': 0,
        'is_liked': isLiked ? 1 : 0,
      };
    } catch (e) {
      return {'likes': 0, 'comments': 0, 'is_liked': 0};
    }
  }

  String _formatTimeAgo(String? timestamp) {
    if (timestamp == null) return '';
    
    try {
      final dateTime = DateTime.parse(timestamp);
      final now = DateTime.now();
      final difference = now.difference(dateTime);

      if (difference.inDays > 7) {
        return '${dateTime.month}/${dateTime.day}/${dateTime.year}';
      } else if (difference.inDays > 0) {
        return '${difference.inDays}d ago';
      } else if (difference.inHours > 0) {
        return '${difference.inHours}h ago';
      } else if (difference.inMinutes > 0) {
        return '${difference.inMinutes}m ago';
      } else {
        return 'Just now';
      }
    } catch (e) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Discovery Feed'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        leading: Builder(
          builder: (context) => IconButton(
            icon: Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: Icon(Icons.filter_list),
            onSelected: (value) {
              setState(() {
                _sortBy = value;
              });
              _loadPosts(refresh: true);
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'recent',
                child: Text('Recent'),
              ),
              PopupMenuItem(
                value: 'trending',
                child: Text('Trending'),
              ),
            ],
          ),
        ],
      ),
      drawer: AppDrawer(currentPage: 'feed'),
      body: RefreshIndicator(
        onRefresh: () => _loadPosts(refresh: true),
        child: _posts.isEmpty && _isLoading
            ? Center(child: CircularProgressIndicator())
            : _posts.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.photo_library, size: 80, color: Colors.grey),
                        SizedBox(height: 16),
                        Text(
                          'No posts yet!',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Be the first to share your cooking',
                          style: TextStyle(color: Colors.grey),
                        ),
                        SizedBox(height: 24),
                        ElevatedButton.icon(
                          onPressed: _navigateToCreatePost,
                          icon: Icon(Icons.add_photo_alternate),
                          label: Text('Create Post'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: EdgeInsets.all(16),
                    itemCount: _posts.length + (_hasMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == _posts.length) {
                        return Center(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: CircularProgressIndicator(),
                          ),
                        );
                      }
                      return _buildPostCard(_posts[index], index);
                    },
                  ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _navigateToCreatePost,
        backgroundColor: Colors.green,
        child: Icon(Icons.add_photo_alternate, color: Colors.white),
      ),
    );
  }
}