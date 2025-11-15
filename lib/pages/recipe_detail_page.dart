// lib/pages/recipe_detail_page.dart - ENHANCED: Added favorites and grocery list buttons
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../services/database_service.dart';
import '../services/error_handling_service.dart';
import '../services/auth_service.dart';
import '../pages/user_profile_page.dart';
import '../models/favorite_recipe.dart';

class RecipeDetailPage extends StatefulWidget {
  final String recipeName;
  final String ingredients;
  final String directions;
  final int recipeId;

  const RecipeDetailPage({
    super.key,
    required this.recipeName,
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
  
  // NEW: Favorite status
  bool _isFavorite = false;
  bool _isLoadingFavorite = true;

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

  // NEW: Check if recipe is favorited
  Future<void> _checkIfFavorite() async {
    try {
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
      
      if (mounted) {
        setState(() {
          _isFavorite = favorites.any((fav) => fav.recipeName == widget.recipeName);
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

  // NEW: Toggle favorite status
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
          ingredients: widget.ingredients,
          directions: widget.directions,
          createdAt: DateTime.now(),
        );
        
        favorites.add(favoriteRecipe);
        
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

  // NEW: Add recipe to grocery list
  Future<void> _addToGroceryList() async {
    try {
      final result = await DatabaseService.addRecipeToShoppingList(
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
                Navigator.pushNamed(context, '/grocerylist');
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

  Future<void> _loadComments() async {
    setState(() {
      _isLoadingComments = true;
    });

    try {
      final comments = await DatabaseService.getRecipeComments(widget.recipeId);
      
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
      await DatabaseService.addComment(
        recipeId: widget.recipeId,
        commentText: _commentController.text.trim(),
        parentCommentId: _replyingToCommentId,
      );

      _commentController.clear();
      setState(() {
        _replyingToCommentId = null;
        _replyingToUsername = null;
      });

      await _loadComments();

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
      final isLiked = await DatabaseService.hasUserLikedPost(commentId);
      
      if (isLiked) {
        await DatabaseService.unlikeComment(commentId);
      } else {
        await DatabaseService.likeComment(commentId);
      }

      await _loadComments();
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
        await DatabaseService.deleteComment(commentId);
        await _loadComments();
        
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
                  await DatabaseService.reportComment(commentId, reason);
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
    final isCurrentUser = user['id'] == DatabaseService.currentUserId;

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
          // NEW: Favorite button in app bar
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
          // Tab bar
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

          // Tab views
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
                      // NEW: Action buttons section
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
                          ],
                        ),
                      ),
                      
                      SizedBox(height: 24),
                      
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
                              : ListView.builder(
                                  itemCount: _comments.length,
                                  itemBuilder: (context, index) {
                                    return _buildCommentItem(_comments[index]);
                                  },
                                ),
                    ),

                    // Comment input
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