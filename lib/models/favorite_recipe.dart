// favorite_recipe.dart
class FavoriteRecipe {
  final int? id;
  final String userId;
  final String recipeName;
  final String ingredients;
  final String directions;
  final DateTime createdAt;
  final DateTime? updatedAt; // Track last modification for cache validation

  FavoriteRecipe({
    this.id,
    required this.userId,
    required this.recipeName,
    required this.ingredients,
    required this.directions,
    required this.createdAt,
    this.updatedAt,
  });

  // From Supabase database response
  factory FavoriteRecipe.fromJson(Map<String, dynamic> json) {
    return FavoriteRecipe(
      id: json['id'],
      userId: json['user_id'],
      recipeName: json['recipe_name'],
      ingredients: json['ingredients'],
      directions: json['directions'],
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: json['updated_at'] != null 
          ? DateTime.parse(json['updated_at']) 
          : null,
    );
  }

  // To Supabase database (for insert/update)
  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'recipe_name': recipeName,
      'ingredients': ingredients,
      'directions': directions,
      'created_at': createdAt.toIso8601String(),
      if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
    };
  }

  // For local cache storage (includes all fields)
  Map<String, dynamic> toCache() {
    return {
      'id': id,
      'user_id': userId,
      'recipe_name': recipeName,
      'ingredients': ingredients,
      'directions': directions,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
      'cached_at': DateTime.now().toIso8601String(), // Track when we cached it
    };
  }

  // From local cache storage
  factory FavoriteRecipe.fromCache(Map<String, dynamic> json) {
    return FavoriteRecipe(
      id: json['id'],
      userId: json['user_id'],
      recipeName: json['recipe_name'],
      ingredients: json['ingredients'],
      directions: json['directions'],
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: json['updated_at'] != null 
          ? DateTime.parse(json['updated_at']) 
          : null,
    );
  }

  // Create a copy with updated fields (useful for updates)
  FavoriteRecipe copyWith({
    int? id,
    String? userId,
    String? recipeName,
    String? ingredients,
    String? directions,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return FavoriteRecipe(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      recipeName: recipeName ?? this.recipeName,
      ingredients: ingredients ?? this.ingredients,
      directions: directions ?? this.directions,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}