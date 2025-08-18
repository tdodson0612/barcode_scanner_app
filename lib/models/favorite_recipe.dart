class FavoriteRecipe {
  final int? id;
  final String userId;
  final String recipeName;
  final String ingredients;
  final String directions;
  final DateTime createdAt;

  FavoriteRecipe({
    this.id,
    required this.userId,
    required this.recipeName,
    required this.ingredients,
    required this.directions,
    required this.createdAt,
  });

  factory FavoriteRecipe.fromJson(Map<String, dynamic> json) {
    return FavoriteRecipe(
      id: json['id'],
      userId: json['user_id'],
      recipeName: json['recipe_name'],
      ingredients: json['ingredients'],
      directions: json['directions'],
      createdAt: DateTime.parse(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'recipe_name': recipeName,
      'ingredients': ingredients,
      'directions': directions,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
