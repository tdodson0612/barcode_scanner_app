// lib/pages/recipe_detail_page.dart - OPTIMIZED: Cache comments, likes, favorite status + SHARE BUTTON
import 'package:flutter/material.dart';
import 'package:liver_wise/services/comments_service.dart';
import 'package:liver_wise/services/grocery_service.dart';
import 'package:liver_wise/services/submitted_recipes_service.dart';
import 'package:liver_wise/services/feed_posts_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../services/database_service_core.dart';
import '../services/error_handling_service.dart';
import '../services/auth_service.dart';
import '../pages/user_profile_page.dart';
import '../models/favorite_recipe.dart';

class RecipeDetailPage extends StatefulWidget {
  final String recipeName;
  final String? description;
  final String ingredients;
  final String directions;
  final int recipeId;

  const RecipeDetailPage({
    super.key,
    required this.recipeName,
    this.description,
    required this.ingredients,
    required this.directions,
    required this.recipeId,
  });

  @override
  State<RecipeDetailPage> createState() => _RecipeDetailPageState();
}

class _RecipeDetailPageState extends State<RecipeDetailPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _commentController = TextEditingController();
  
  List<Map<String, dynamic>> _comments = [];
  bool _isLoadingComments = false;
  bool _isSubmittingComment = false;
  String? _replyingToCommentId;
  String? _replyingToUsername;
  
  bool _isFavorite = false;
  bool _isLoadingFavorite = true;

  // Cache configuration
  static const Duration _commentsCacheDuration = Duration(minutes: 2);
  static const Duration _favoriteCacheDuration = Duration(minutes: 5);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadComments();
    _checkIfFavorite();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _commentController.dispose();
    super.dispose();
  }

  String _getCommentsCacheKey() => 'recipe_comments_${widget.recipeId}';
  String _getFavoriteCacheKey() => 'recipe_favorite_${widget.recipeName}';

  Future<List<Map<String, dynamic>>?> _getCachedComments() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_getCommentsCacheKey());
      
      if (cached == null) return null;
      
      final data = json.decode(cached);
      final timestamp = data['_cached_at'] as int?;
      
      if (timestamp == null) return null;
      
      final age = DateTime.now().millisecondsSinceEpoch - timestamp;
      if (age > _commentsCacheDuration.inMilliseconds) return null;
      
      final comments = (data['comments'] as List)
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      
      print('📦 Using cached comments (${comments.length} found)');
      return comments;
    } catch (e) {
      print('Error loading cached comments: $e');
      return null;
    }
  }

  Future<void> _cacheComments(List<Map<String, dynamic>> comments) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheData = {
        'comments': comments,
        '_cached_at': DateTime.now().millisecondsSinceEpoch,
      };
      await prefs.setString(_getCommentsCacheKey(), json.encode(cacheData));
      print('💾 Cached ${comments.length} comments');
    } catch (e) {
      print('Error caching comments: $e');
    }
  }

  Future<void> _invalidateCommentsCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_getCommentsCacheKey());
    } catch (e) {
      print('Error invalidating comments cache: $e');
    }
  }

  Future<bool?> _getCachedFavoriteStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_getFavoriteCacheKey());
      
      if (cached == null) return null;
      
      final data = json.decode(cached);
      final timestamp = data['_cached_at'] as int?;
      final isFavorite = data['is_favorite'] as bool?;
      
      if (timestamp == null || isFavorite == null) return null;
      
      final age = DateTime.now().millisecondsSinceEpoch - timestamp;
      if (age > _favoriteCacheDuration.inMilliseconds) return null;
      
      return isFavorite;
    } catch (e) {
      return null;
    }
  }

  Future<void> _cacheFavoriteStatus(bool isFavorite) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheData = {
        'is_favorite': isFavorite,
        '_cached_at': DateTime.now().millisecondsSinceEpoch,
      };
      await prefs.setString(_getFavoriteCacheKey(), json.encode(cacheData));
    } catch (e) {
      print('Error caching favorite status: $e');
    }
  }

  Future<void> _checkIfFavorite() async {
    try {
      // Try cache first
      final cached = await _getCachedFavoriteStatus();
      
      if (cached != null) {
        if (mounted) {
          setState(() {
            _isFavorite = cached;
            _isLoadingFavorite = false;
          });
        }
        return;
      }

      // Cache miss, check SharedPreferences (legacy storage)
      final prefs = await SharedPreferences.getInstance();
      final favoriteRecipesJson = prefs.getStringList('favorite_recipes_detailed') ?? [];
      
      final favorites = favoriteRecipesJson
          .map((jsonString) {
            try {
              return FavoriteRecipe.fromJson(json.decode(jsonString));
            } catch (e) {
              return null;
            }
          })
          .where((recipe) => recipe != null)
          .cast<FavoriteRecipe>()
          .toList();
      
      final isFavorite = favorites.any((fav) => fav.recipeName == widget.recipeName);
      
      // Cache the result
      await _cacheFavoriteStatus(isFavorite);
      
      if (mounted) {
        setState(() {
          _isFavorite = isFavorite;
          _isLoadingFavorite = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingFavorite = false;
        });
      }
    }
  }

  Future<void> _toggleFavorite() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final currentUserId = AuthService.currentUserId;
      
      if (currentUserId == null) {
        if (mounted) {
          ErrorHandlingService.showSimpleError(
            context,
            'Please log in to save recipes',
          );
        }
        return;
      }

      final favoriteRecipesJson = prefs.getStringList('favorite_recipes_detailed') ?? [];
      
      final favorites = favoriteRecipesJson
          .map((jsonString) {
            try {
              return FavoriteRecipe.fromJson(json.decode(jsonString));
            } catch (e) {
              return null;
            }
          })
          .where((recipe) => recipe != null)
          .cast<FavoriteRecipe>()
          .toList();
      
      final existingIndex = favorites.indexWhere((fav) => fav.recipeName == widget.recipeName);
      
      if (existingIndex >= 0) {
        // Remove from favorites
        favorites.removeAt(existingIndex);
        
        // Update cache
        await _cacheFavoriteStatus(false);
        
        if (mounted) {
          setState(() {
            _isFavorite = false;
          });
          
          ErrorHandlingService.showSuccess(
            context,
            'Removed "${widget.recipeName}" from favorites',
          );
        }
      } else {
        // Add to favorites
        final favoriteRecipe = FavoriteRecipe(
          userId: currentUserId,
          recipeName: widget.recipeName,
          description: widget.description,
          ingredients: widget.ingredients,
          directions: widget.directions,
          createdAt: DateTime.now(),
        );
        
        favorites.add(favoriteRecipe);
        
        // Update cache
        await _cacheFavoriteStatus(true);
        
        if (mounted) {
          setState(() {
            _isFavorite = true;
          });
          
          ErrorHandlingService.showSuccess(
            context,
            'Added "${widget.recipeName}" to favorites!',
          );
        }
      }
      
      // Save to SharedPreferences
      final updatedJson = favorites
          .map((recipe) => json.encode(recipe.toJson()))
          .toList();
      await prefs.setStringList('favorite_recipes_detailed', updatedJson);
      
    } catch (e) {
      if (mounted) {
        ErrorHandlingService.showSimpleError(
          context,
          'Error saving recipe',
        );
      }
    }
  }

  Future<void> _addToGroceryList() async {
    try {
      final result = await GroceryService.addRecipeToShoppingList(
        widget.recipeName,
        widget.ingredients,
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Added ${result['added']} items to grocery list${result['skipped'] > 0 ? ' (${result['skipped']} duplicates skipped)' : ''}',
            ),
            backgroundColor: Colors.green,
            action: SnackBarAction(
              label: 'View List',
              textColor: Colors.white,
              onPressed: () {
                Navigator.pushNamed(context, '/grocery-list');
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ErrorHandlingService.showSimpleError(
          context,
          'Error adding to grocery list',
        );
      }
    }
  }

  // 🔥 NEW: Share recipe to feed
  Future<void> _shareRecipeToFeed() async {
    try {
      await FeedPostsService.shareRecipeToFeed(
        recipeName: widget.recipeName,
        description: widget.description,
        ingredients: widget.ingredients,
        directions: widget.directions,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 12),
                Expanded(
                  child: Text('Recipe shared to your feed!'),
                ),
              ],
            ),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
            action: SnackBarAction(
              label: 'View Feed',
              textColor: Colors.white,
              onPressed: () {
                Navigator.pushNamed(context, '/home');
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ErrorHandlingService.showSimpleError(
          context,
          'Failed to share recipe',
        );
      }
    }
  }

  Future<void> _loadComments({bool forceRefresh = false}) async {
    setState(() {
      _isLoadingComments = true;
    });

    try {
      // Try cache first unless force refresh
      if (!forceRefresh) {
        final cachedComments = await _getCachedComments();
        
        if (cachedComments != null) {
          if (mounted) {
            setState(() {
              _comments = cachedComments;
              _isLoadingComments = false;
            });
          }
          return;
        }
      }

      // Cache miss or force refresh, fetch from database
      final comments = await CommentsService.getRecipeComments(widget.recipeId);
      
      // Cache the results
      await _cacheComments(comments);
      
      if (mounted) {
        setState(() {
          _comments = comments;
          _isLoadingComments = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingComments = false;
        });
        
        // Try to use cached data even if stale
        final staleComments = await _getCachedComments();
        if (staleComments != null && mounted) {
          setState(() {
            _comments = staleComments;
          });
        }
        
        ErrorHandlingService.showSimpleError(
          context,
          'Unable to load comments',
        );
      }
    }
  }

  Future<void> _submitComment() async {
    if (_commentController.text.trim().isEmpty) {
      return;
    }

    setState(() {
      _isSubmittingComment = true;
    });

    try {
      await CommentsService.addComment(
        recipeId: widget.recipeId,
        commentText: _commentController.text.trim(),
        parentCommentId: _replyingToCommentId,
      );

      _commentController.clear();
      setState(() {
        _replyingToCommentId = null;
        _replyingToUsername = null;
      });

      // Invalidate cache and reload
      await _invalidateCommentsCache();
      await _loadComments(forceRefresh: true);

      if (mounted) {
        ErrorHandlingService.showSuccess(context, 'Comment posted!');
      }
    } catch (e) {
      if (mounted) {
        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          category: ErrorHandlingService.databaseError,
          customMessage: 'Failed to post comment',
          onRetry: _submitComment,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmittingComment = false;
        });
      }
    }
  }

  Future<void> _toggleLikeComment(String commentId) async {
    try {
      final isLiked = await CommentsService.hasUserLikedPost(commentId);
      
      if (isLiked) {
        await CommentsService.unlikeComment(commentId);
      } else {
        await CommentsService.likeComment(commentId);
      }

      // Invalidate cache and reload
      await _invalidateCommentsCache();
      await _loadComments(forceRefresh: true);
    } catch (e) {
      if (mounted) {
        ErrorHandlingService.showSimpleError(
          context,
          'Failed to update like',
        );
      }
    }
  }

  void _replyToComment(String commentId, String username) {
    setState(() {
      _replyingToCommentId = commentId;
      _replyingToUsername = username;
    });
    FocusScope.of(context).requestFocus(FocusNode());
  }

  void _cancelReply() {
    setState(() {
      _replyingToCommentId = null;
      _replyingToUsername = null;
    });
  }

  Future<void> _deleteComment(String commentId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete Comment'),
        content: Text('Are you sure you want to delete this comment?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await CommentsService.deleteComment(commentId);
        
        // Invalidate cache and reload
        await _invalidateCommentsCache();
        await _loadComments(forceRefresh: true);
        
        if (mounted) {
          ErrorHandlingService.showSuccess(context, 'Comment deleted');
        }
      } catch (e) {
        if (mounted) {
          ErrorHandlingService.showSimpleError(
            context,
            'Failed to delete comment',
          );
        }
      }
    }
  }

  void _reportComment(String commentId) {
    showDialog(
      context: context,
      builder: (context) {
        String reason = '';
        return AlertDialog(
          title: Text('Report Comment'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Why are you reporting this comment?'),
              SizedBox(height: 16),
              TextField(
                onChanged: (value) => reason = value,
                decoration: InputDecoration(
                  hintText: 'Enter reason...',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                if (reason.trim().isEmpty) {
                  ErrorHandlingService.showSimpleError(
                    context,
                    'Please enter a reason',
                  );
                  return;
                }

                try {
                  await CommentsService.reportComment(commentId, reason);
                  Navigator.pop(context);
                  
                  if (mounted) {
                    ErrorHandlingService.showSuccess(
                      context,
                      'Comment reported. Thank you!',
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ErrorHandlingService.showSimpleError(
                      context,
                      'Failed to report comment',
                    );
                  }
                }
              },
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: Text('Report'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCommentItem(Map<String, dynamic> comment) {
    final user = comment['user'] ?? {};
    final username = user['username'] ?? 'Unknown';
    final commentText = comment['comment_text'] ?? '';
    final createdAt = comment['created_at'];
    final isCurrentUser = user['id'] == AuthService.currentUserId;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => UserProfilePage(userId: user['id']),
                ),
              );
            },
            child: CircleAvatar(
              radius: 16,
              backgroundImage: user['avatar_url'] != null
                  ? NetworkImage(user['avatar_url'])
                  : null,
              child: user['avatar_url'] == null
                  ? Text(username[0].toUpperCase())
                  : null,
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        username,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(commentText),
                    ],
                  ),
                ),
                SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      _formatTimeAgo(createdAt),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                    SizedBox(width: 16),
                    GestureDetector(
                      onTap: () => _toggleLikeComment(comment['id']),
                      child: Text(
                        'Like',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    SizedBox(width: 16),
                    GestureDetector(
                      onTap: () => _replyToComment(comment['id'], username),
                      child: Text(
                        'Reply',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Spacer(),
                    PopupMenuButton<String>(
                      icon: Icon(Icons.more_horiz, size: 16),
                      onSelected: (value) {
                        if (value == 'delete') {
                          _deleteComment(comment['id']);
                        } else if (value == 'report') {
                          _reportComment(comment['id']);
                        }
                      },
                      itemBuilder: (context) => [
                        if (isCurrentUser)
                          PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(Icons.delete, size: 16, color: Colors.red),
                                SizedBox(width: 8),
                                Text('Delete'),
                              ],
                            ),
                          ),
                        if (!isCurrentUser)
                          PopupMenuItem(
                            value: 'report',
                            child: Row(
                              children: [
                                Icon(Icons.flag, size: 16, color: Colors.red),
                                SizedBox(width: 8),
                                Text('Report'),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTimeAgo(String? timestamp) {
    if (timestamp == null) return '';
    
    try {
      final dateTime = DateTime.parse(timestamp);
      final now = DateTime.now();
      final difference = now.difference(dateTime);

      if (difference.inDays > 7) {
        return '${dateTime.month}/${dateTime.day}';
      } else if (difference.inDays > 0) {
        return '${difference.inDays}d';
      } else if (difference.inHours > 0) {
        return '${difference.inHours}h';
      } else if (difference.inMinutes > 0) {
        return '${difference.inMinutes}m';
      } else {
        return 'now';
      }
    } catch (e) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.recipeName),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        actions: [
          if (!_isLoadingFavorite)
            IconButton(
              icon: Icon(
                _isFavorite ? Icons.favorite : Icons.favorite_border,
                color: _isFavorite ? Colors.red : Colors.white,
              ),
              onPressed: _toggleFavorite,
              tooltip: _isFavorite ? 'Remove from favorites' : 'Add to favorites',
            ),
        ],
      ),
      body: Column(
        children: [
          TabBar(
            controller: _tabController,
            labelColor: Colors.green,
            unselectedLabelColor: Colors.grey,
            indicatorColor: Colors.green,
            tabs: [
              Tab(text: 'Recipe'),
              Tab(text: 'Comments (${_comments.length})'),
            ],
          ),

          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // Recipe tab
                SingleChildScrollView(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 🔥 UPDATED: Action buttons with Share
                      Container(
                        padding: EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: _toggleFavorite,
                                    icon: Icon(
                                      _isFavorite ? Icons.favorite : Icons.favorite_border,
                                    ),
                                    label: Text(
                                      _isFavorite ? 'Favorited' : 'Favorite',
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: _isFavorite ? Colors.red : Colors.grey.shade700,
                                      foregroundColor: Colors.white,
                                      padding: EdgeInsets.symmetric(vertical: 12),
                                    ),
                                  ),
                                ),
                                SizedBox(width: 12),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: _addToGroceryList,
                                    icon: Icon(Icons.add_shopping_cart),
                                    label: Text('Grocery List'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.green,
                                      foregroundColor: Colors.white,
                                      padding: EdgeInsets.symmetric(vertical: 12),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 12),
                            // 🔥 NEW: Share to Feed button
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: _shareRecipeToFeed,
                                icon: Icon(Icons.share),
                                label: Text('Share to Feed'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue,
                                  foregroundColor: Colors.white,
                                  padding: EdgeInsets.symmetric(vertical: 12),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      SizedBox(height: 24),

                      // 🔥 Description section (if exists)
                      if (widget.description != null && widget.description!.trim().isNotEmpty) ...[
                        Container(
                          padding: EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.blue.shade200,
                              width: 1,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.info_outline, 
                                    size: 20, 
                                    color: Colors.blue.shade700
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'About This Recipe',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue.shade700,
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 8),
                              Text(
                                widget.description!,
                                style: TextStyle(
                                  fontSize: 14,
                                  height: 1.5,
                                  color: Colors.black87,
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: 24),
                      ],
                      
                      Text(
                        'Ingredients',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(widget.ingredients),
                      SizedBox(height: 24),
                      Text(
                        'Directions',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(widget.directions),
                    ],
                  ),
                ),

                // Comments tab
                Column(
                  children: [
                    Expanded(
                      child: _isLoadingComments
                          ? Center(child: CircularProgressIndicator())
                          : _comments.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.comment, size: 60, color: Colors.grey),
                                      SizedBox(height: 16),
                                      Text(
                                        'No comments yet',
                                        style: TextStyle(
                                          fontSize: 16,
                                          color: Colors.grey,
                                        ),
                                      ),
                                      SizedBox(height: 8),
                                      Text(
                                        'Be the first to comment!',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.grey,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : RefreshIndicator(
                                  onRefresh: () => _loadComments(forceRefresh: true),
                                  child: ListView.builder(
                                    itemCount: _comments.length,
                                    itemBuilder: (context, index) {
                                      return _buildCommentItem(_comments[index]);
                                    },
                                  ),
                                ),
                    ),

                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black12,
                            offset: Offset(0, -2),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                      padding: EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_replyingToUsername != null) ...[
                            Container(
                              padding: EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  Text(
                                    'Replying to $_replyingToUsername',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.blue.shade700,
                                    ),
                                  ),
                                  Spacer(),
                                  GestureDetector(
                                    onTap: _cancelReply,
                                    child: Icon(
                                      Icons.close,
                                      size: 16,
                                      color: Colors.blue.shade700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(height: 8),
                          ],
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _commentController,
                                  decoration: InputDecoration(
                                    hintText: 'Write a comment...',
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(24),
                                    ),
                                    contentPadding: EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 8,
                                    ),
                                  ),
                                  maxLines: 1,
                                ),
                              ),
                              SizedBox(width: 8),
                              _isSubmittingComment
                                  ? SizedBox(
                                      width: 40,
                                      height: 40,
                                      child: Center(
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      ),
                                    )
                                  : IconButton(
                                      onPressed: _submitComment,
                                      icon: Icon(Icons.send),
                                      color: Colors.green,
                                    ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}