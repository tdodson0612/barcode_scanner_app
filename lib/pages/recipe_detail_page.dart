// lib/pages/recipe_detail_page.dart - COMPLETE WITH NUTRITION + PROFILE ALTERATION
import 'package:flutter/material.dart';
import 'package:liver_wise/services/comments_service.dart';
import 'package:liver_wise/services/grocery_service.dart';
import 'package:liver_wise/services/feed_posts_service.dart';
import 'package:liver_wise/widgets/nutrition_facts_label.dart';
import 'package:liver_wise/models/nutrition_info.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../services/error_handling_service.dart';
import '../services/auth_service.dart';
import '../pages/user_profile_page.dart';
import '../models/favorite_recipe.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Brittney's per-meal profile constraints (1200 kcal / 3 meals)
// Source: co-CEO nutrition profile document
// ─────────────────────────────────────────────────────────────────────────────
class _BrittneyProfile {
  static const double maxCaloriesPerMeal = 400;  // 1200 kcal / 3
  static const double maxProteinPerMeal  = 35;   // g  (35% of 1200)
  static const double maxCarbsPerMeal    = 25;   // g  (25% of 1200)
  static const double maxFatPerMeal      = 9;    // g  (20% of 1200)
  static const double maxSodiumPerMeal   = 300;  // mg (200–300 range, upper bound)
  static const double maxSugarPerMeal    = 10;   // g  (10% of 1200)
  static const double minFiberPerDay     = 25;   // g  (daily, informational only)
}

// ─────────────────────────────────────────────────────────────────────────────
// Data models for alteration
// ─────────────────────────────────────────────────────────────────────────────

/// One nutrient that is over the per-meal limit.
class _NutrientFlag {
  final String nutrient;
  final double original; // per-serving value
  final double limit;
  final String unit;

  const _NutrientFlag({
    required this.nutrient,
    required this.original,
    required this.limit,
    required this.unit,
  });

  /// How many percent over the limit this nutrient is.
  double get overagePercent => ((original - limit) / limit * 100).clamp(0, 999);
}

/// Result of running the alteration algorithm.
class _AlterationResult {
  /// The NutritionInfo scaled to fit all per-meal constraints.
  final NutritionInfo adjusted;

  /// Fraction of the recipe (or serving) to use, e.g. 0.6 = 60 %.
  final double scaleFactor;

  /// Which nutrients triggered the scale-down.
  final List<_NutrientFlag> flags;

  const _AlterationResult({
    required this.adjusted,
    required this.scaleFactor,
    required this.flags,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Pure alteration logic — no Flutter deps
// ─────────────────────────────────────────────────────────────────────────────
class _ProfileAlterationService {
  /// Returns [null] when the recipe already fits all limits.
  /// Otherwise returns the minimum scale needed and which nutrients caused it.
  static _AlterationResult? alter(NutritionInfo n, int? servings) {
    // Work on per-serving values so the user sees per-plate numbers.
    final divisor = (servings != null && servings > 0) ? servings.toDouble() : 1.0;

    final calPerServing    = n.calories / divisor;
    final fatPerServing    = n.fat      / divisor;
    final sodiumPerServing = n.sodium   / divisor;
    final carbsPerServing  = n.carbs    / divisor;
    final sugarPerServing  = n.sugar    / divisor;
    // Protein is a minimum target for Brittney, not a ceiling — we do not
    // reduce the recipe because of protein.

    final flags   = <_NutrientFlag>[];
    final ratios  = <double>[]; // required multipliers to hit each limit

    void check(String nutrient, double value, double limit, String unit) {
      if (value > limit) {
        ratios.add(limit / value);
        flags.add(_NutrientFlag(
          nutrient: nutrient,
          original: value,
          limit: limit,
          unit: unit,
        ));
      }
    }

    check('Calories', calPerServing,    _BrittneyProfile.maxCaloriesPerMeal, 'kcal');
    check('Fat',      fatPerServing,    _BrittneyProfile.maxFatPerMeal,      'g');
    check('Sodium',   sodiumPerServing, _BrittneyProfile.maxSodiumPerMeal,   'mg');
    check('Carbs',    carbsPerServing,  _BrittneyProfile.maxCarbsPerMeal,    'g');
    check('Sugar',    sugarPerServing,  _BrittneyProfile.maxSugarPerMeal,    'g');

    if (flags.isEmpty) return null; // Already fits — no alteration needed.

    // Most restrictive constraint drives the scale factor.
    final scaleFactor = ratios.reduce((a, b) => a < b ? a : b);

    // Scale the full recipe (not per-serving) so NutritionFactsLabel stays consistent.
    final adjusted = n.scale(scaleFactor);

    return _AlterationResult(
      adjusted: adjusted,
      scaleFactor: scaleFactor,
      flags: flags,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Page widget
// ─────────────────────────────────────────────────────────────────────────────
class RecipeDetailPage extends StatefulWidget {
  final String recipeName;
  final String? description;
  final String ingredients;
  final String directions;
  final int recipeId;
  final NutritionInfo? nutrition;
  final int? servings;

  const RecipeDetailPage({
    super.key,
    required this.recipeName,
    this.description,
    required this.ingredients,
    required this.directions,
    required this.recipeId,
    this.nutrition,
    this.servings,
  });

  @override
  State<RecipeDetailPage> createState() => _RecipeDetailPageState();
}

class _RecipeDetailPageState extends State<RecipeDetailPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _commentController = TextEditingController();

  List<Map<String, dynamic>> _comments      = [];
  bool _isLoadingComments                   = false;
  bool _isSubmittingComment                 = false;
  String? _replyingToCommentId;
  String? _replyingToUsername;

  bool _isFavorite        = false;
  bool _isLoadingFavorite = true;

  // Profile alteration state
  _AlterationResult? _alterationResult;
  bool _showAltered = false; // toggle between original / adjusted nutrition display

  static const Duration _commentsCacheDuration = Duration(minutes: 2);
  static const Duration _favoriteCacheDuration  = Duration(minutes: 5);

  // ── Lifecycle ────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadComments();
    _checkIfFavorite();
    _computeAlteration();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _commentController.dispose();
    super.dispose();
  }

  void _computeAlteration() {
    if (widget.nutrition == null) return;
    final result = _ProfileAlterationService.alter(widget.nutrition!, widget.servings);
    if (mounted) setState(() => _alterationResult = result);
  }

  // ── Cache helpers ────────────────────────────────────────────────────────

  String get _commentsCacheKey => 'recipe_comments_${widget.recipeId}';
  String get _favoriteCacheKey => 'recipe_favorite_${widget.recipeName}';

  Future<List<Map<String, dynamic>>?> _getCachedComments() async {
    try {
      final prefs  = await SharedPreferences.getInstance();
      final cached = prefs.getString(_commentsCacheKey);
      if (cached == null) return null;
      final data = json.decode(cached);
      final age  = DateTime.now().millisecondsSinceEpoch - (data['_cached_at'] as int? ?? 0);
      if (age > _commentsCacheDuration.inMilliseconds) return null;
      return (data['comments'] as List)
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {
      return null;
    }
  }

  Future<void> _cacheComments(List<Map<String, dynamic>> comments) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_commentsCacheKey, json.encode({
        'comments':    comments,
        '_cached_at':  DateTime.now().millisecondsSinceEpoch,
      }));
    } catch (_) {}
  }

  Future<void> _invalidateCommentsCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_commentsCacheKey);
    } catch (_) {}
  }

  Future<bool?> _getCachedFavoriteStatus() async {
    try {
      final prefs  = await SharedPreferences.getInstance();
      final cached = prefs.getString(_favoriteCacheKey);
      if (cached == null) return null;
      final data = json.decode(cached);
      final age  = DateTime.now().millisecondsSinceEpoch - (data['_cached_at'] as int? ?? 0);
      if (age > _favoriteCacheDuration.inMilliseconds) return null;
      return data['is_favorite'] as bool?;
    } catch (_) {
      return null;
    }
  }

  Future<void> _cacheFavoriteStatus(bool isFavorite) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_favoriteCacheKey, json.encode({
        'is_favorite': isFavorite,
        '_cached_at':  DateTime.now().millisecondsSinceEpoch,
      }));
    } catch (_) {}
  }

  // ── Favorites ────────────────────────────────────────────────────────────

  Future<void> _checkIfFavorite() async {
    try {
      final cached = await _getCachedFavoriteStatus();
      if (cached != null) {
        if (mounted) setState(() { _isFavorite = cached; _isLoadingFavorite = false; });
        return;
      }
      final prefs     = await SharedPreferences.getInstance();
      final favJson   = prefs.getStringList('favorite_recipes_detailed') ?? [];
      final favorites = favJson
          .map((s) { try { return FavoriteRecipe.fromJson(json.decode(s)); } catch (_) { return null; } })
          .whereType<FavoriteRecipe>()
          .toList();
      final isFav = favorites.any((f) => f.recipeName == widget.recipeName);
      await _cacheFavoriteStatus(isFav);
      if (mounted) setState(() { _isFavorite = isFav; _isLoadingFavorite = false; });
    } catch (_) {
      if (mounted) setState(() => _isLoadingFavorite = false);
    }
  }

  Future<void> _toggleFavorite() async {
    try {
      final currentUserId = AuthService.currentUserId;
      if (currentUserId == null) {
        if (mounted) ErrorHandlingService.showSimpleError(context, 'Please log in to save recipes');
        return;
      }
      final prefs     = await SharedPreferences.getInstance();
      final favJson   = prefs.getStringList('favorite_recipes_detailed') ?? [];
      final favorites = favJson
          .map((s) { try { return FavoriteRecipe.fromJson(json.decode(s)); } catch (_) { return null; } })
          .whereType<FavoriteRecipe>()
          .toList();
      final idx = favorites.indexWhere((f) => f.recipeName == widget.recipeName);
      if (idx >= 0) {
        favorites.removeAt(idx);
        await _cacheFavoriteStatus(false);
        if (mounted) {
          setState(() => _isFavorite = false);
          ErrorHandlingService.showSuccess(context, 'Removed "${widget.recipeName}" from favorites');
        }
      } else {
        favorites.add(FavoriteRecipe(
          userId:      currentUserId,
          recipeName:  widget.recipeName,
          description: widget.description,
          ingredients: widget.ingredients,
          directions:  widget.directions,
          createdAt:   DateTime.now(),
        ));
        await _cacheFavoriteStatus(true);
        if (mounted) {
          setState(() => _isFavorite = true);
          ErrorHandlingService.showSuccess(context, 'Added "${widget.recipeName}" to favorites!');
        }
      }
      await prefs.setStringList(
        'favorite_recipes_detailed',
        favorites.map((r) => json.encode(r.toJson())).toList(),
      );
    } catch (_) {
      if (mounted) ErrorHandlingService.showSimpleError(context, 'Error saving recipe');
    }
  }

  // ── Grocery list ─────────────────────────────────────────────────────────

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
              'Added ${result['added']} items to grocery list'
              '${result['skipped'] > 0 ? ' (${result['skipped']} duplicates skipped)' : ''}',
            ),
            backgroundColor: Colors.green,
            action: SnackBarAction(
              label: 'View List',
              textColor: Colors.white,
              onPressed: () => Navigator.pushNamed(context, '/grocery-list'),
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) ErrorHandlingService.showSimpleError(context, 'Error adding to grocery list');
    }
  }

  // ── Share to feed ─────────────────────────────────────────────────────────

  Future<void> _shareRecipeToFeed() async {
    final visibility = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Share Recipe'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Who can see this post?'),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.public, color: Colors.blue),
              title: const Text('Public'),
              subtitle: const Text('Anyone can see this'),
              onTap: () => Navigator.pop(context, 'public'),
            ),
            ListTile(
              leading: const Icon(Icons.people, color: Colors.green),
              title: const Text('Friends Only'),
              subtitle: const Text('Only your friends can see this'),
              onTap: () => Navigator.pop(context, 'friends'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (visibility == null) return;
    try {
      await FeedPostsService.shareRecipeToFeed(
        recipeName:  widget.recipeName,
        description: widget.description,
        ingredients: widget.ingredients,
        directions:  widget.directions,
        visibility:  visibility,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(child: Text(
                'Recipe shared to your feed '
                '(${visibility == 'public' ? 'Public' : 'Friends Only'})!',
              )),
            ]),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
            action: SnackBarAction(
              label: 'View Feed',
              textColor: Colors.white,
              onPressed: () => Navigator.pushNamed(context, '/home'),
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) ErrorHandlingService.showSimpleError(context, 'Failed to share recipe');
    }
  }

  // ── Comments ─────────────────────────────────────────────────────────────

  Future<void> _loadComments({bool forceRefresh = false}) async {
    setState(() => _isLoadingComments = true);
    try {
      if (!forceRefresh) {
        final cached = await _getCachedComments();
        if (cached != null) {
          if (mounted) setState(() { _comments = cached; _isLoadingComments = false; });
          return;
        }
      }
      final comments = await CommentsService.getRecipeComments(widget.recipeId);
      await _cacheComments(comments);
      if (mounted) setState(() { _comments = comments; _isLoadingComments = false; });
    } catch (_) {
      if (mounted) {
        setState(() => _isLoadingComments = false);
        final stale = await _getCachedComments();
        if (stale != null && mounted) setState(() => _comments = stale);
        ErrorHandlingService.showSimpleError(context, 'Unable to load comments');
      }
    }
  }

  Future<void> _submitComment() async {
    if (_commentController.text.trim().isEmpty) return;
    setState(() => _isSubmittingComment = true);
    try {
      await CommentsService.addComment(
        recipeId:        widget.recipeId,
        commentText:     _commentController.text.trim(),
        parentCommentId: _replyingToCommentId,
      );
      _commentController.clear();
      setState(() { _replyingToCommentId = null; _replyingToUsername = null; });
      await _invalidateCommentsCache();
      await _loadComments(forceRefresh: true);
      if (mounted) ErrorHandlingService.showSuccess(context, 'Comment posted!');
    } catch (e) {
      if (mounted) {
        await ErrorHandlingService.handleError(
          context:       context,
          error:         e,
          category:      ErrorHandlingService.databaseError,
          customMessage: 'Failed to post comment',
          onRetry:       _submitComment,
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmittingComment = false);
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
      await _invalidateCommentsCache();
      await _loadComments(forceRefresh: true);
    } catch (_) {
      if (mounted) ErrorHandlingService.showSimpleError(context, 'Failed to update like');
    }
  }

  void _replyToComment(String commentId, String username) {
    setState(() { _replyingToCommentId = commentId; _replyingToUsername = username; });
    FocusScope.of(context).requestFocus(FocusNode());
  }

  void _cancelReply() {
    setState(() { _replyingToCommentId = null; _replyingToUsername = null; });
  }

  Future<void> _deleteComment(String commentId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title:   const Text('Delete Comment'),
        content: const Text('Are you sure you want to delete this comment?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      try {
        await CommentsService.deleteComment(commentId);
        await _invalidateCommentsCache();
        await _loadComments(forceRefresh: true);
        if (mounted) ErrorHandlingService.showSuccess(context, 'Comment deleted');
      } catch (_) {
        if (mounted) ErrorHandlingService.showSimpleError(context, 'Failed to delete comment');
      }
    }
  }

  void _reportComment(String commentId) {
    showDialog(
      context: context,
      builder: (context) {
        String reason = '';
        return AlertDialog(
          title: const Text('Report Comment'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Why are you reporting this comment?'),
              const SizedBox(height: 16),
              TextField(
                onChanged: (value) => reason = value,
                decoration: const InputDecoration(
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
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                if (reason.trim().isEmpty) {
                  ErrorHandlingService.showSimpleError(context, 'Please enter a reason');
                  return;
                }
                try {
                  await CommentsService.reportComment(commentId, reason);
                  Navigator.pop(context);
                  if (mounted) {
                    ErrorHandlingService.showSuccess(context, 'Comment reported. Thank you!');
                  }
                } catch (_) {
                  if (mounted) {
                    ErrorHandlingService.showSimpleError(context, 'Failed to report comment');
                  }
                }
              },
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Report'),
            ),
          ],
        );
      },
    );
  }

  // ── Comment item widget ───────────────────────────────────────────────────

  Widget _buildCommentItem(Map<String, dynamic> comment) {
    final user          = comment['user'] ?? {};
    final username      = user['username'] ?? 'Unknown';
    final commentText   = comment['comment_text'] ?? '';
    final createdAt     = comment['created_at'];
    final isCurrentUser = user['id'] == AuthService.currentUserId;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => UserProfilePage(userId: user['id'])),
            ),
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
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        username,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      const SizedBox(height: 4),
                      Text(commentText),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      _formatTimeAgo(createdAt),
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(width: 16),
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
                    const SizedBox(width: 16),
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
                    const Spacer(),
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_horiz, size: 16),
                      onSelected: (value) {
                        if (value == 'delete') _deleteComment(comment['id']);
                        else if (value == 'report') _reportComment(comment['id']);
                      },
                      itemBuilder: (_) => [
                        if (isCurrentUser)
                          const PopupMenuItem(
                            value: 'delete',
                            child: Row(children: [
                              Icon(Icons.delete, size: 16, color: Colors.red),
                              SizedBox(width: 8),
                              Text('Delete'),
                            ]),
                          ),
                        if (!isCurrentUser)
                          const PopupMenuItem(
                            value: 'report',
                            child: Row(children: [
                              Icon(Icons.flag, size: 16, color: Colors.red),
                              SizedBox(width: 8),
                              Text('Report'),
                            ]),
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
      final dt   = DateTime.parse(timestamp);
      final diff = DateTime.now().difference(dt);
      if (diff.inDays > 7) return '${dt.month}/${dt.day}';
      if (diff.inDays > 0) return '${diff.inDays}d';
      if (diff.inHours > 0) return '${diff.inHours}h';
      if (diff.inMinutes > 0) return '${diff.inMinutes}m';
      return 'now';
    } catch (_) {
      return '';
    }
  }

  // ── Profile alteration UI ─────────────────────────────────────────────────

  /// Yellow banner shown only when the recipe exceeds at least one limit.
  Widget _buildAlterationBanner(_AlterationResult result) {
    final pct         = (result.scaleFactor * 100).round();
    final servings    = widget.servings ?? 1;
    final adjServings = (result.scaleFactor * servings).toStringAsFixed(1);

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFCC02), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // ── Header row ─────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFCC02),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.tune, size: 18, color: Colors.white),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Recipe adjusted for your profile',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF7B5800),
                    ),
                  ),
                ),
                // Toggle: original ↔ adjusted nutrition label
                if (widget.nutrition != null)
                  GestureDetector(
                    onTap: () => setState(() => _showAltered = !_showAltered),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: _showAltered ? const Color(0xFF7B5800) : Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFF7B5800)),
                      ),
                      child: Text(
                        _showAltered ? 'View original' : 'View adjusted',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _showAltered ? Colors.white : const Color(0xFF7B5800),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // ── Explanation text ────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Text(
              'To meet your per-meal limits, use $pct% of this recipe '
              '($adjServings of $servings serving${servings == 1 ? '' : 's'}).',
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF5C4000),
                height: 1.45,
              ),
            ),
          ),

          const SizedBox(height: 10),

          // ── Nutrient chips ──────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              children: result.flags.map(_buildNutrientChip).toList(),
            ),
          ),
        ],
      ),
    );
  }

  /// Small pill showing original → limit for one nutrient.
  Widget _buildNutrientChip(_NutrientFlag flag) {
    final isInt = flag.unit == 'mg' || flag.unit == 'kcal';
    String fmt(double v) => isInt ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFFFCC02), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.arrow_downward_rounded, size: 12, color: Color(0xFF7B5800)),
          const SizedBox(width: 4),
          Text(
            '${flag.nutrient}: ${fmt(flag.original)}${flag.unit} → ${fmt(flag.limit)}${flag.unit}',
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF5C4000),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  /// Per-meal compliance row shown in the blue panel.
  Widget _buildLimitRow(
    String label,
    double perServingValue,
    double limit,
    String unit,
  ) {
    final over  = perServingValue > limit;
    final color = over ? Colors.red.shade600 : Colors.green.shade600;
    final isInt = unit == 'mg' || unit == 'kcal';
    String fmt(double v) => isInt ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Container(
            width: 8, height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
          ),
          Text(
            '${fmt(perServingValue)}$unit  /  limit ${fmt(limit)}$unit',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }

  /// Informational row (protein target, fiber) without a hard limit concept.
  Widget _buildInsightRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Container(
            width: 8, height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
          ),
          Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  // ── Nutrition section ─────────────────────────────────────────────────────

  Widget _buildNutritionSection() {
    if (widget.nutrition == null) return const SizedBox.shrink();

    final n        = widget.nutrition!;
    final servings = widget.servings;
    final divisor  = (servings != null && servings > 0) ? servings.toDouble() : 1.0;

    // Switch between original and adjusted for the FDA label.
    final displayNutrition = (_showAltered && _alterationResult != null)
        ? _alterationResult!.adjusted
        : n;

    // Per-serving values for the compliance panel (always original).
    final calPerServing    = n.calories / divisor;
    final fatPerServing    = n.fat      / divisor;
    final sodiumPerServing = n.sodium   / divisor;
    final carbsPerServing  = n.carbs    / divisor;
    final sugarPerServing  = n.sugar    / divisor;
    final protPerServing   = n.protein  / divisor;
    final fiberPerServing  = (n.fiber ?? 0) / divisor;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        const Divider(thickness: 2),
        const SizedBox(height: 16),

        // Section title
        Row(
          children: [
            const Icon(Icons.restaurant_menu, color: Colors.green, size: 24),
            const SizedBox(width: 8),
            Text(
              _showAltered ? 'Nutrition Facts (Adjusted)' : 'Nutrition Facts',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            if (_showAltered) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF8E1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFFFCC02)),
                ),
                child: const Text(
                  'Profile-adjusted',
                  style: TextStyle(
                    fontSize: 11,
                    color: Color(0xFF7B5800),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),

        // FDA-style nutrition label
        NutritionFactsLabel(
          nutrition:      displayNutrition,
          servings:       servings,
          showLiverScore: true,
        ),

        const SizedBox(height: 16),

        // ── Per-meal compliance panel ──────────────────────────────────
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.blue.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.person_outline, size: 16, color: Colors.blue.shade700),
                  const SizedBox(width: 6),
                  Text(
                    "Brittney's per-meal limits",
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Hard ceilings — red when exceeded.
              _buildLimitRow('Calories', calPerServing,    _BrittneyProfile.maxCaloriesPerMeal, 'kcal'),
              _buildLimitRow('Fat',      fatPerServing,    _BrittneyProfile.maxFatPerMeal,      'g'),
              _buildLimitRow('Sodium',   sodiumPerServing, _BrittneyProfile.maxSodiumPerMeal,   'mg'),
              _buildLimitRow('Carbs',    carbsPerServing,  _BrittneyProfile.maxCarbsPerMeal,    'g'),
              _buildLimitRow('Sugar',    sugarPerServing,  _BrittneyProfile.maxSugarPerMeal,    'g'),

              // Protein is a floor/target — orange if under, green if met.
              _buildInsightRow(
                'Protein (target ≥ ${_BrittneyProfile.maxProteinPerMeal.toStringAsFixed(0)}g)',
                '${protPerServing.toStringAsFixed(1)}g per serving',
                protPerServing >= _BrittneyProfile.maxProteinPerMeal
                    ? Colors.green.shade600
                    : Colors.orange.shade700,
              ),

              // Fiber — daily target, shown informational only when present.
              if (n.fiber != null && n.fiber! > 0)
                _buildInsightRow(
                  'Fiber (daily goal ≥ ${_BrittneyProfile.minFiberPerDay.toStringAsFixed(0)}g)',
                  '${fiberPerServing.toStringAsFixed(1)}g this meal',
                  fiberPerServing >= 5 ? Colors.green.shade600 : Colors.grey.shade500,
                ),
            ],
          ),
        ),

        const SizedBox(height: 32),
      ],
    );
  }

  // ── Main build ────────────────────────────────────────────────────────────

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
              const Tab(text: 'Recipe'),
              Tab(text: 'Comments (${_comments.length})'),
            ],
          ),

          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [

                // ════════════════════════════════════════════════
                // RECIPE TAB
                // ════════════════════════════════════════════════
                SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [

                      // Profile alteration banner — only when limits are exceeded.
                      if (_alterationResult != null)
                        _buildAlterationBanner(_alterationResult!),

                      // Action buttons
                      Container(
                        padding: const EdgeInsets.all(16),
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
                                    icon: Icon(_isFavorite
                                        ? Icons.favorite
                                        : Icons.favorite_border),
                                    label: Text(_isFavorite ? 'Favorited' : 'Favorite'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: _isFavorite
                                          ? Colors.red
                                          : Colors.grey.shade700,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: _addToGroceryList,
                                    icon: const Icon(Icons.add_shopping_cart),
                                    label: const Text('Grocery List'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.green,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: _shareRecipeToFeed,
                                icon: const Icon(Icons.share),
                                label: const Text('Share to Feed'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Description
                      if (widget.description != null &&
                          widget.description!.trim().isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.blue.shade200, width: 1),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.info_outline,
                                      size: 20, color: Colors.blue.shade700),
                                  const SizedBox(width: 8),
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
                              const SizedBox(height: 8),
                              Text(
                                widget.description!,
                                style: const TextStyle(
                                  fontSize: 14,
                                  height: 1.5,
                                  color: Colors.black87,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],

                      // Ingredients
                      const Text(
                        'Ingredients',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(widget.ingredients),

                      const SizedBox(height: 24),

                      // Directions
                      const Text(
                        'Directions',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(widget.directions),

                      // Nutrition facts label + compliance panels
                      _buildNutritionSection(),
                    ],
                  ),
                ),

                // ════════════════════════════════════════════════
                // COMMENTS TAB
                // ════════════════════════════════════════════════
                Column(
                  children: [
                    Expanded(
                      child: _isLoadingComments
                          ? const Center(child: CircularProgressIndicator())
                          : _comments.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.comment,
                                          size: 60, color: Colors.grey),
                                      const SizedBox(height: 16),
                                      const Text(
                                        'No comments yet',
                                        style: TextStyle(
                                            fontSize: 16, color: Colors.grey),
                                      ),
                                      const SizedBox(height: 8),
                                      const Text(
                                        'Be the first to comment!',
                                        style: TextStyle(
                                            fontSize: 14, color: Colors.grey),
                                      ),
                                    ],
                                  ),
                                )
                              : RefreshIndicator(
                                  onRefresh: () =>
                                      _loadComments(forceRefresh: true),
                                  child: ListView.builder(
                                    itemCount: _comments.length,
                                    itemBuilder: (_, i) =>
                                        _buildCommentItem(_comments[i]),
                                  ),
                                ),
                    ),

                    // Comment input bar
                    Container(
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black12,
                            offset: Offset(0, -2),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_replyingToUsername != null) ...[
                            Container(
                              padding: const EdgeInsets.all(8),
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
                                  const Spacer(),
                                  GestureDetector(
                                    onTap: _cancelReply,
                                    child: Icon(Icons.close,
                                        size: 16, color: Colors.blue.shade700),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
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
                                    contentPadding:
                                        const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 8,
                                    ),
                                  ),
                                  maxLines: 1,
                                ),
                              ),
                              const SizedBox(width: 8),
                              _isSubmittingComment
                                  ? const SizedBox(
                                      width: 40,
                                      height: 40,
                                      child: Center(
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2),
                                      ),
                                    )
                                  : IconButton(
                                      onPressed: _submitComment,
                                      icon: const Icon(Icons.send),
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