import 'dart:io';
import 'package:flutter/material.dart';
// import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'liverhealthbar.dart';
import 'profile_screen.dart';
import 'contact_screen.dart';

/// --- NutritionInfo Data Model ---
class NutritionInfo {
  final String productName;
  final double fat;
  final double sodium;
  final double sugar;
  final double calories;

  NutritionInfo({
    required this.productName,
    required this.fat,
    required this.sodium,
    required this.sugar,
    required this.calories,
  });

  factory NutritionInfo.fromJson(Map<String, dynamic> json) {
    final product = json['product'] ?? {};
    final nutriments = product['nutriments'] ?? {};

    double parseDouble(dynamic value) {
      if (value == null) return 0.0;
      return double.tryParse(value.toString()) ?? 0.0;
    }

    return NutritionInfo(
      productName: product['product_name'] ?? 'Unknown product',
      calories: parseDouble(nutriments['energy-kcal_100g']),
      fat: parseDouble(nutriments['fat_100g']),
      sugar: parseDouble(nutriments['sugars_100g']),
      sodium: parseDouble(nutriments['sodium_100g']),
    );
  }
}

/// --- Recipe Data Model ---
class Recipe {
  final String title;
  final String description;
  final List<String> ingredients;
  final String instructions;

  Recipe({
    required this.title,
    required this.description,
    required this.ingredients,
    required this.instructions,
  });

  Map<String, dynamic> toJson() => {
    'title': title,
    'description': description,
    'ingredients': ingredients,
    'instructions': instructions,
  };

  factory Recipe.fromJson(Map<String, dynamic> json) => Recipe(
    title: json['title'] ?? '',
    description: json['description'] ?? '',
    ingredients: List<String>.from(json['ingredients'] ?? []),
    instructions: json['instructions'] ?? '',
  );
}

/// --- Liver Health Score Calculator ---
class LiverHealthCalculator {
  static const double fatMax = 20.0;       // grams
  static const double sodiumMax = 500.0;   // mg
  static const double sugarMax = 20.0;     // grams
  static const double calMax = 400.0;      // kcal

  static int calculate({
    required double fat,
    required double sodium,
    required double sugar,
    required double calories,
  }) {
    double fatScore = 1 - (fat / fatMax).clamp(0, 1);
    double sodiumScore = 1 - (sodium / sodiumMax).clamp(0, 1);
    double sugarScore = 1 - (sugar / sugarMax).clamp(0, 1);
    double calScore = 1 - (calories / calMax).clamp(0, 1);

    double finalScore = (fatScore * 0.3) +
                        (sodiumScore * 0.25) +
                        (sugarScore * 0.25) +
                        (calScore * 0.2);

    return (finalScore * 100).round().clamp(0, 100);
  }
}

/// --- Recipe Generator ---
class RecipeGenerator {
  static List<Recipe> generateSuggestions(int liverHealthScore) {
    if (liverHealthScore >= 75) {
      return _getHealthyRecipes();
    } else if (liverHealthScore >= 50) {
      return _getModerateRecipes();
    } else {
      return _getDetoxRecipes();
    }
  }

  static List<Recipe> _getHealthyRecipes() => [
    Recipe(
      title: "Mediterranean Salmon Bowl",
      description: "Heart-healthy salmon with fresh vegetables",
      ingredients: ["Fresh salmon", "Mixed greens", "Olive oil", "Lemon", "Cherry tomatoes"],
      instructions: "Grill salmon, serve over greens with olive oil and lemon dressing.",
    ),
    Recipe(
      title: "Quinoa Vegetable Stir-fry",
      description: "Protein-rich quinoa with colorful vegetables",
      ingredients: ["Quinoa", "Bell peppers", "Broccoli", "Carrots", "Soy sauce"],
      instructions: "Cook quinoa, stir-fry vegetables, combine and season.",
    ),
  ];

  static List<Recipe> _getModerateRecipes() => [
    Recipe(
      title: "Baked Chicken with Sweet Potato",
      description: "Lean protein with nutrient-rich sweet potato",
      ingredients: ["Chicken breast", "Sweet potato", "Herbs", "Olive oil"],
      instructions: "Season chicken, bake with sweet potato slices until golden.",
    ),
    Recipe(
      title: "Lentil Soup",
      description: "Fiber-rich soup to support liver health",
      ingredients: ["Red lentils", "Carrots", "Celery", "Onions", "Vegetable broth"],
      instructions: "Sauté vegetables, add lentils and broth, simmer until tender.",
    ),
  ];

  static List<Recipe> _getDetoxRecipes() => [
    Recipe(
      title: "Green Detox Smoothie",
      description: "Liver-cleansing green smoothie",
      ingredients: ["Spinach", "Green apple", "Lemon juice", "Ginger", "Water"],
      instructions: "Blend all ingredients until smooth, serve immediately.",
    ),
    Recipe(
      title: "Steamed Vegetables with Brown Rice",
      description: "Simple, clean eating option",
      ingredients: ["Brown rice", "Broccoli", "Carrots", "Zucchini", "Herbs"],
      instructions: "Steam vegetables, serve over cooked brown rice with herbs.",
    ),
  ];
}

/// --- Nutrition API Service ---
class NutritionApiService {
  static const String baseUrl = "https://world.openfoodfacts.org/api/v0/product";

  static Future<NutritionInfo?> fetchNutritionInfo(String barcode) async {
    if (barcode.isEmpty) return null;

    final url = "$baseUrl/$barcode.json";

    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {'User-Agent': 'FlutterApp/1.0'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 1) {
          return NutritionInfo.fromJson(data);
        }
      }
      return null;
    } catch (e) {
      debugPrint('Error fetching nutrition info: $e');
      return null;
    }
  }
}

/// --- Barcode Scanner Service ---
class BarcodeScannerService {
  static Future<String?> scanBarcode(String imagePath) async {
    if (imagePath.isEmpty) return null;

    final inputImage = InputImage.fromFilePath(imagePath);
    final barcodeScanner = BarcodeScanner();

    try {
      final barcodes = await barcodeScanner.processImage(inputImage);
      
      if (barcodes.isNotEmpty) {
        return barcodes.first.rawValue;
      }
      return null;
    } catch (e) {
      debugPrint('Error scanning barcode: $e');
      return null;
    } finally {
      await barcodeScanner.close();
    }
  }

  static Future<NutritionInfo?> scanAndLookup(String imagePath) async {
    final barcode = await scanBarcode(imagePath);
    if (barcode == null) return null;
    
    return await NutritionApiService.fetchNutritionInfo(barcode);
  }
}

/// --- Home Screen ---
class HomeScreen extends StatefulWidget {
  final bool isPremium;

  const HomeScreen({super.key, required this.isPremium});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // State variables
  File? _imageFile;
  String _nutritionText = '';
  int? _liverHealthScore;
  bool _showLiverBar = false;
  bool _isLoading = false;
  List<Recipe> _recipeSuggestions = [];
  List<String> _favoriteRecipes = [];
  bool _showInitialView = true;

  // Image picker
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadFavoriteRecipes();
  }

  /// Load favorite recipes from SharedPreferences
  Future<void> _loadFavoriteRecipes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _favoriteRecipes = prefs.getStringList('favorite_recipes') ?? [];
      });
    } catch (e) {
      debugPrint('Error loading favorite recipes: $e');
    }
  }

  /// Toggle favorite recipe status
  Future<void> _toggleFavoriteRecipe(String recipeTitle) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        if (_favoriteRecipes.contains(recipeTitle)) {
          _favoriteRecipes.remove(recipeTitle);
        } else {
          _favoriteRecipes.add(recipeTitle);
        }
      });
      await prefs.setStringList('favorite_recipes', _favoriteRecipes);
    } catch (e) {
      debugPrint('Error saving favorite recipes: $e');
    }
  }

  /// Reset to initial home view
  void _resetToHome() {
    setState(() {
      _showInitialView = true;
      _nutritionText = '';
      _showLiverBar = false;
      _imageFile = null;
      _recipeSuggestions = [];
      _liverHealthScore = null;
      _isLoading = false;
    });
  }

  /// Take photo from camera
  Future<void> _takePhoto() async {
    try {
      setState(() {
        _showInitialView = false;
        _nutritionText = '';
        _showLiverBar = false;
        _imageFile = null;
        _recipeSuggestions = [];
        _isLoading = false;
      });

      final pickedFile = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
        maxWidth: 1024,
        maxHeight: 1024,
      );

      if (pickedFile != null) {
        setState(() {
          _imageFile = File(pickedFile.path);
        });
      }
    } catch (e) {
      _showErrorDialog('Failed to take photo: ${e.toString()}');
    }
  }

  /// Submit photo for analysis
  Future<void> _submitPhoto() async {
    if (_imageFile == null) return;

    setState(() {
      _isLoading = true;
      _nutritionText = '';
      _showLiverBar = false;
      _recipeSuggestions = [];
    });

    try {
      final nutrition = await BarcodeScannerService.scanAndLookup(_imageFile!.path);

      if (nutrition == null) {
        setState(() {
          _nutritionText = "No barcode found or product not recognized. Please try again.";
          _showLiverBar = false;
          _isLoading = false;
        });
        return;
      }

      final score = LiverHealthCalculator.calculate(
        fat: nutrition.fat,
        sodium: nutrition.sodium,
        sugar: nutrition.sugar,
        calories: nutrition.calories,
      );

      final suggestions = RecipeGenerator.generateSuggestions(score);

      setState(() {
        _nutritionText = _buildNutritionDisplay(nutrition);
        _liverHealthScore = score;
        _showLiverBar = true;
        _isLoading = false;
        _recipeSuggestions = suggestions;
      });
    } catch (e) {
      setState(() {
        _nutritionText = "Error processing image: ${e.toString()}";
        _showLiverBar = false;
        _isLoading = false;
      });
    }
  }

  /// Build nutrition information display text
  String _buildNutritionDisplay(NutritionInfo nutrition) {
    return "Product: ${nutrition.productName}\n"
           "Energy: ${nutrition.calories.toStringAsFixed(1)} kcal/100g\n"
           "Fat: ${nutrition.fat.toStringAsFixed(1)} g/100g\n"
           "Sugar: ${nutrition.sugar.toStringAsFixed(1)} g/100g\n"
           "Sodium: ${nutrition.sodium.toStringAsFixed(1)} mg/100g";
  }

  /// Show error dialog
  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Error'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// Build recipe suggestions widget
  Widget _buildRecipeSuggestions() {
    if (_recipeSuggestions.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.shade800,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Recipe Suggestions:',
            style: TextStyle(
              fontSize: 20,
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          ..._recipeSuggestions.map((recipe) => _buildRecipeCard(recipe)),
        ],
      ),
    );
  }

  /// Build individual recipe card
  Widget _buildRecipeCard(Recipe recipe) {
    final isFavorite = _favoriteRecipes.contains(recipe.title);
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  recipe.title,
                  style: const TextStyle(
                    fontSize: 16,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                icon: Icon(
                  isFavorite ? Icons.favorite : Icons.favorite_border,
                  color: isFavorite ? Colors.red : Colors.white,
                ),
                onPressed: () => _toggleFavoriteRecipe(recipe.title),
              ),
            ],
          ),
          Text(
            recipe.description,
            style: const TextStyle(
              fontSize: 14,
              color: Colors.white70,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Ingredients: ${recipe.ingredients.join(', ')}',
            style: const TextStyle(
              fontSize: 12,
              color: Colors.white60,
            ),
          ),
        ],
      ),
    );
  }

  /// Build initial welcome view
  Widget _buildInitialView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.camera_alt,
            size: 80,
            color: Colors.white.withValues(alpha: 0.8),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'Scan a product barcode',
              style: TextStyle(
                fontSize: 24,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'Take a photo of a product barcode to get nutrition information and health recommendations',
              style: TextStyle(
                fontSize: 16,
                color: Colors.white70,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 40),
          ElevatedButton.icon(
            onPressed: _takePhoto,
            icon: const Icon(Icons.camera_alt),
            label: const Text('Take Photo'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              textStyle: const TextStyle(fontSize: 18),
            ),
          ),
        ],
      ),
    );
  }

  /// Build scanning view with results
  Widget _buildScanningView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          const SizedBox(height: 20),

          // Image preview
          if (_imageFile != null)
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(
                  _imageFile!,
                  width: 200,
                  height: 200,
                  fit: BoxFit.cover,
                ),
              ),
            ),

          const SizedBox(height: 20),

          // Action buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton.icon(
                onPressed: _takePhoto,
                icon: const Icon(Icons.camera_alt),
                label: const Text('Retake'),
              ),
              if (_imageFile != null && !_isLoading)
                ElevatedButton.icon(
                  onPressed: _submitPhoto,
                  icon: const Icon(Icons.send),
                  label: const Text('Analyze'),
                ),
            ],
          ),

          const SizedBox(height: 20),

          // Loading indicator
          if (_isLoading)
            const Column(
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text(
                  'Analyzing image...',
                  style: TextStyle(color: Colors.white),
                ),
              ],
            ),

          // Nutrition information
          if (_nutritionText.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: Colors.green.shade700,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Text(
                _nutritionText,
                style: const TextStyle(
                  fontSize: 16,
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.left,
              ),
            ),

          const SizedBox(height: 20),

          // Liver health bar
          if (_showLiverBar && _liverHealthScore != null)
            LiverHealthBar(healthScore: _liverHealthScore!),

          const SizedBox(height: 20),

          // Recipe suggestions
          _buildRecipeSuggestions(),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color.fromARGB(255, 1, 110, 32),
        foregroundColor: Colors.white,
        title: const Text('LiverWise Scanner'),
        elevation: 0,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.shopping_cart),
            onPressed: () {
              Navigator.pushNamed(context, '/purchase');
            },
          ),
        ],
      ),
      drawer: _buildDrawer(),
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/background.png'),
            fit: BoxFit.cover,
          ),
        ),
        child: Column(
          children: [
            Expanded(
              child: _showInitialView ? _buildInitialView() : _buildScanningView(),
            ),
            // Welcome message
            Container(
              padding: const EdgeInsets.all(16),
              child: Text(
                widget.isPremium
                    ? 'Welcome, Premium User!'
                    : 'Welcome, Free User!',
                style: TextStyle(
                  fontSize: 18,
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                  shadows: [
                    Shadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      offset: const Offset(1, 1),
                      blurRadius: 2,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build navigation drawer
  Widget _buildDrawer() {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          const DrawerHeader(
            decoration: BoxDecoration(
              color: Color.fromARGB(255, 1, 110, 32),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.local_hospital,
                  color: Colors.white,
                  size: 48,
                ),
                SizedBox(height: 16),
                Text(
                  'LiverWise Menu:',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.home),
            title: const Text('Home'),
            onTap: () {
              Navigator.pop(context);
              _resetToHome();
            },
          ),
          ListTile(
            leading: const Icon(Icons.person),
            title: const Text('Profile'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ProfileScreen(favoriteRecipes: _favoriteRecipes),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.contact_mail),
            title: const Text('Contact Us'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const ContactScreen()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.shopping_cart),
            title: const Text('Purchase Premium'),
            onTap: () {
              Navigator.pop(context);
              Navigator.pushNamed(context, '/purchase');
            },
          ),
        ],
      ),
    );
  }
}