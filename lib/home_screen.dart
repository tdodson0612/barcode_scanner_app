import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/app_drawer.dart';
import '../widgets/premium_gate.dart';
import '../controllers/premium_gate_controller.dart';
import 'liverhealthbar.dart';
import '../pages/profile_screen.dart';
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

/// --- Combined Home Page with Premium Features ---
class HomePage extends StatefulWidget {
  final bool isPremium;

  const HomePage({super.key, this.isPremium = false});

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // Premium scanning state
  bool _isScanning = false;
  List<Map<String, String>> _scannedRecipes = [];
  
  // Nutrition scanner state
  File? _imageFile;
  String _nutritionText = '';
  int? _liverHealthScore;
  bool _showLiverBar = false;
  bool _isLoading = false;
  List<Recipe> _recipeSuggestions = [];
  List<String> _favoriteRecipes = [];
  bool _showInitialView = true;
  NutritionInfo? _currentNutrition;

  // Ad state
  InterstitialAd? _interstitialAd;
  bool _isAdReady = false;
  RewardedAd? _rewardedAd;
  bool _isRewardedAdReady = false;

  // Image picker
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    PremiumGateController().refresh();
    _loadFavoriteRecipes();
    _loadInterstitialAd();
    _loadRewardedAd();
  }

  @override
  void dispose() {
    _interstitialAd?.dispose();
    _rewardedAd?.dispose();
    super.dispose();
  }

  /// Load interstitial ad for free users
  void _loadInterstitialAd() {
    InterstitialAd.load(
      adUnitId: Platform.isAndroid
          ? 'ca-app-pub-3940256099942544/1033173712' // Test ad unit ID
          : 'ca-app-pub-3940256099942544/4411468910',
      request: AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd = ad;
          _isAdReady = true;
          
          ad.setImmersiveMode(true);
        },
        onAdFailedToLoad: (error) {
          debugPrint('InterstitialAd failed to load: $error');
          _isAdReady = false;
        },
      ),
    );
  }

  /// Load rewarded ad for free users to earn extra scans
  void _loadRewardedAd() {
    RewardedAd.load(
      adUnitId: Platform.isAndroid
          ? 'ca-app-pub-3940256099942544/5224354917' // Test ad unit ID
          : 'ca-app-pub-3940256099942544/1712485313',
      request: AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewardedAd = ad;
          _isRewardedAdReady = true;
        },
        onAdFailedToLoad: (error) {
          debugPrint('RewardedAd failed to load: $error');
          _isRewardedAdReady = false;
        },
      ),
    );
  }

  /// Show interstitial ad before allowing scan for free users
  void _showInterstitialAd(VoidCallback onAdClosed) {
    if (_isAdReady && _interstitialAd != null) {
      _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
        onAdShowedFullScreenContent: (ad) {
          debugPrint('Interstitial ad showed full screen content');
        },
        onAdDismissedFullScreenContent: (ad) {
          debugPrint('Interstitial ad dismissed');
          ad.dispose();
          _loadInterstitialAd(); // Load next ad
          onAdClosed(); // Continue with scan
        },
        onAdFailedToShowFullScreenContent: (ad, error) {
          debugPrint('Interstitial ad failed to show: $error');
          ad.dispose();
          _loadInterstitialAd();
          onAdClosed(); // Continue with scan even if ad fails
        },
      );
      _interstitialAd!.show();
      _isAdReady = false;
    } else {
      onAdClosed(); // Continue with scan if no ad available
    }
  }

  /// Show rewarded ad to earn extra scans
  void _showRewardedAd() {
    if (_isRewardedAdReady && _rewardedAd != null) {
      _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
        onAdShowedFullScreenContent: (ad) {
          debugPrint('Rewarded ad showed full screen content');
        },
        onAdDismissedFullScreenContent: (ad) {
          debugPrint('Rewarded ad dismissed');
          ad.dispose();
          _loadRewardedAd(); // Load next ad
        },
        onAdFailedToShowFullScreenContent: (ad, error) {
          debugPrint('Rewarded ad failed to show: $error');
          ad.dispose();
          _loadRewardedAd();
        },
      );
      
      _rewardedAd!.show(
        onUserEarnedReward: (ad, reward) {
          debugPrint('User earned reward: ${reward.amount} ${reward.type}');
          // Award extra scan to user
          final controller = PremiumGateController();
          controller.addBonusScans(1);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Bonus scan earned! You now have ${controller.remainingScans + 1} scans remaining.'),
              backgroundColor: Colors.green,
            ),
          );
        },
      );
      _isRewardedAdReady = false;
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ad not ready yet. Please try again in a moment.'),
          backgroundColor: Colors.orange,
        ),
      );
    }
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
      _scannedRecipes = [];
      _currentNutrition = null;
    });
  }

  /// Premium scan method (simulated) - Free users must watch ad first
  Future<void> _performScan() async {
    final controller = PremiumGateController();
    
    // Check if user can scan
    if (!controller.canAccessFeature(PremiumFeature.scan)) {
      Navigator.pushNamed(context, '/premium');
      return;
    }

    // Free users must watch interstitial ad before scanning
    if (!controller.isPremium) {
      _showInterstitialAd(() => _executePerformScan());
    } else {
      _executePerformScan();
    }
  }

  /// Execute the actual scan after ad is watched (or for premium users)
  Future<void> _executePerformScan() async {
    final controller = PremiumGateController();

    setState(() {
      _isScanning = true;
    });

    try {
      // Use a scan (for free users)
      final success = await controller.useScan();
      
      if (!success) {
        Navigator.pushNamed(context, '/premium');
        return;
      }

      // Simulate scanning delay
      await Future.delayed(Duration(seconds: 2));

      // Simulate scan results
      setState(() {
        _scannedRecipes = [
          {
            'name': 'Tomato Pasta',
            'ingredients': '2 cups pasta, 4 tomatoes, 1 onion, garlic, olive oil',
            'directions': '1. Cook pasta. 2. Sauté onion and garlic. 3. Add tomatoes. 4. Mix with pasta.',
          },
          {
            'name': 'Vegetable Stir Fry',
            'ingredients': '2 cups mixed vegetables, soy sauce, ginger, garlic, oil',
            'directions': '1. Heat oil in pan. 2. Add ginger and garlic. 3. Add vegetables. 4. Stir fry with soy sauce.',
          },
        ];
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Scan successful! ${controller.remainingScans} scans remaining today.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error scanning: $e')),
      );
    } finally {
      setState(() {
        _isScanning = false;
      });
    }
  }

  /// Take photo from camera (Real nutrition scanner) - Free users must watch ad first
  Future<void> _takePhoto() async {
    final controller = PremiumGateController();
    
    // Check if user can scan (premium feature)
    if (!controller.canAccessFeature(PremiumFeature.scan)) {
      Navigator.pushNamed(context, '/premium');
      return;
    }

    // Free users must watch interstitial ad before taking photo
    if (!controller.isPremium) {
      _showInterstitialAd(() => _executeTakePhoto());
    } else {
      _executeTakePhoto();
    }
  }

  /// Execute taking photo after ad is watched (or for premium users)
  Future<void> _executeTakePhoto() async {
    try {
      setState(() {
        _showInitialView = false;
        _nutritionText = '';
        _showLiverBar = false;
        _imageFile = null;
        _recipeSuggestions = [];
        _isLoading = false;
        _scannedRecipes = [];
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

  /// Submit photo for analysis (Real nutrition analysis)
  Future<void> _submitPhoto() async {
    if (_imageFile == null) return;

    final controller = PremiumGateController();
    
    // Use a scan for analysis
    final success = await controller.useScan();
    if (!success) {
      Navigator.pushNamed(context, '/premium');
      return;
    }

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
        _currentNutrition = nutrition;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Analysis successful! ${controller.remainingScans} scans remaining today.'),
          backgroundColor: Colors.green,
        ),
      );
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

  /// Build recipe suggestions widget for real nutrition analysis
  Widget _buildNutritionRecipeSuggestions() {
    if (_recipeSuggestions.isEmpty) return const SizedBox.shrink();

    return PremiumGate(
      feature: PremiumFeature.viewRecipes,
      featureName: 'Recipe Details',
      featureDescription: 'View full recipe details with ingredients and directions.',
      child: Container(
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
              'Health-Based Recipe Suggestions:',
              style: TextStyle(
                fontSize: 20,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            ..._recipeSuggestions.map((recipe) => _buildNutritionRecipeCard(recipe)),
          ],
        ),
      ),
    );
  }

  /// Build individual recipe card for nutrition analysis
  Widget _buildNutritionRecipeCard(Recipe recipe) {
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
              PremiumGate(
                feature: PremiumFeature.favoriteRecipes,
                featureName: 'Favorite Recipes',
                child: IconButton(
                  icon: Icon(
                    isFavorite ? Icons.favorite : Icons.favorite_border,
                    color: isFavorite ? Colors.red : Colors.white,
                  ),
                  onPressed: () => _toggleFavoriteRecipe(recipe.title),
                ),
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
          const SizedBox(height: 8),
          Text(
            'Instructions: ${recipe.instructions}',
            style: const TextStyle(
              fontSize: 12,
              color: Colors.white60,
            ),
          ),
          const SizedBox(height: 12),
          // Premium action buttons
          Row(
            children: [
              Expanded(
                child: PremiumGate(
                  feature: PremiumFeature.favoriteRecipes,
                  featureName: 'Favorite Recipes',
                  child: ElevatedButton.icon(
                    onPressed: () {
                      _toggleFavoriteRecipe(recipe.title);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Added to favorites!')),
                      );
                    },
                    icon: Icon(Icons.favorite),
                    label: Text('Save Recipe'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: PremiumGate(
                  feature: PremiumFeature.groceryList,
                  featureName: 'Grocery List',
                  child: ElevatedButton.icon(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Added to grocery list!')),
                      );
                    },
                    icon: Icon(Icons.add_shopping_cart),
                    label: Text('Add to List'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Build initial welcome view
  Widget _buildInitialView() {
    return Stack(
      children: [
        // Background
        Positioned.fill(
          child: Image.asset(
            'assets/background.png',
            fit: BoxFit.cover,
          ),
        ),
        
        // Content
        SingleChildScrollView(
          padding: EdgeInsets.all(16),
          child: Column(
            children: [
              // Welcome Section
              Container(
                padding: EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha((0.9 * 255).toInt()),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.scanner,
                      size: 48,
                      color: Colors.green,
                    ),
                    SizedBox(height: 12),
                    Text(
                      'Welcome to Recipe Scanner',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Scan products to discover amazing recipes and get nutrition insights!',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey.shade600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              
              SizedBox(height: 30),
              
              // Scan Button Section
              Center(
                child: AnimatedBuilder(
                  animation: PremiumGateController(),
                  builder: (context, _) {
                    final controller = PremiumGateController();
                    
                    return Column(
                      children: [
                        // Main Scan Button
                        GestureDetector(
                          onTap: _isScanning ? null : _takePhoto,
                          child: Container(
                            width: 200,
                            height: 200,
                            decoration: BoxDecoration(
                              color: _isScanning 
                                  ? Colors.grey 
                                  : (controller.canAccessFeature(PremiumFeature.scan) 
                                      ? Colors.blue 
                                      : Colors.red),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black26,
                                  blurRadius: 10,
                                  offset: Offset(0, 5),
                                ),
                              ],
                            ),
                            child: Center(
                              child: _isScanning
                                  ? Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        CircularProgressIndicator(color: Colors.white),
                                        SizedBox(height: 16),
                                        Text(
                                          'Scanning...',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    )
                                  : Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          controller.canAccessFeature(PremiumFeature.scan)
                                              ? Icons.camera_alt
                                              : Icons.lock,
                                          color: Colors.white,
                                          size: 60,
                                        ),
                                        SizedBox(height: 12),
                                        Text(
                                          controller.canAccessFeature(PremiumFeature.scan)
                                              ? 'Tap to Scan'
                                              : 'Upgrade to Scan',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                            ),
                          ),
                        ),
                        
                        SizedBox(height: 20),
                        
                        // Scan Status
                        Container(
                          padding: EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white.withAlpha((0.9 * 255).toInt()),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            children: [
                              if (!controller.isPremium) ...[
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      controller.canAccessFeature(PremiumFeature.scan)
                                          ? Icons.check_circle
                                          : Icons.warning,
                                      color: controller.canAccessFeature(PremiumFeature.scan)
                                          ? Colors.green
                                          : Colors.red,
                                      size: 20,
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      controller.canAccessFeature(PremiumFeature.scan)
                                          ? 'Free scans remaining: ${controller.remainingScans}/3'
                                          : 'Daily scan limit reached!',
                                      style: TextStyle(
                                        fontSize: 16,
                                        color: controller.canAccessFeature(PremiumFeature.scan)
                                            ? Colors.green.shade700
                                            : Colors.red.shade700,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 12),
                                ElevatedButton.icon(
                                  onPressed: () {
                                    Navigator.pushNamed(context, '/premium');
                                  },
                                  icon: Icon(Icons.star),
                                  label: Text('Upgrade for Unlimited Scans'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.amber,
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                                
                                // Watch ad for bonus scan button
                                SizedBox(height: 8),
                                ElevatedButton.icon(
                                  onPressed: _showRewardedAd,
                                  icon: Icon(Icons.play_circle_fill),
                                  label: Text('Watch Ad for Bonus Scan'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.purple,
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                              ] else ...[
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.star, color: Colors.amber, size: 20),
                                    SizedBox(width: 8),
                                    Text(
                                      'Premium: Unlimited Scans',
                                      style: TextStyle(
                                        fontSize: 16,
                                        color: Colors.amber.shade700,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                        
                        // Quick Scan Demo Button (for premium demo)
                        SizedBox(height: 20),
                        ElevatedButton.icon(
                          onPressed: _performScan,
                          icon: Icon(Icons.qr_code_scanner),
                          label: Text('Quick Recipe Scan Demo'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              
              SizedBox(height: 30),
              
              // Recipe Results from Demo Scan (PREMIUM GATED)
              if (_scannedRecipes.isNotEmpty) ...[
                PremiumGate(
                  feature: PremiumFeature.viewRecipes,
                  featureName: 'Recipe Details',
                  featureDescription: 'View full recipe details with ingredients and directions.',
                  child: Column(
                    children: [
                      Container(
                        padding: EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha((0.9 * 255).toInt()),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.restaurant, color: Colors.green, size: 24),
                            SizedBox(width: 12),
                            Text(
                              'Recipe Suggestions',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      SizedBox(height: 16),
                      
                      ..._scannedRecipes.map((recipe) => Container(
                        margin: EdgeInsets.only(bottom: 16),
                        padding: EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha((0.9 * 255).toInt()),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.restaurant, color: Colors.green),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    recipe['name']!,
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 16),
                            
                            Text(
                              'Ingredients:',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            SizedBox(height: 8),
                            Text(recipe['ingredients']!),
                            
                            SizedBox(height: 16),
                            
                            Text(
                              'Directions:',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            SizedBox(height: 8),
                            Text(recipe['directions']!),
                            
                            SizedBox(height: 16),
                            
                            // Premium action buttons
                            Row(
                              children: [
                                Expanded(
                                  child: PremiumGate(
                                    feature: PremiumFeature.favoriteRecipes,
                                    featureName: 'Favorite Recipes',
                                    child: ElevatedButton.icon(
                                      onPressed: () {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text('Added to favorites!')),
                                        );
                                      },
                                      icon: Icon(Icons.favorite),
                                      label: Text('Save Recipe'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.red,
                                        foregroundColor: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                                SizedBox(width: 12),
                                Expanded(
                                  child: PremiumGate(
                                    feature: PremiumFeature.groceryList,
                                    featureName: 'Grocery List',
                                    child: ElevatedButton.icon(
                                      onPressed: () {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text('Added to grocery list!')),
                                        );
                                      },
                                      icon: Icon(Icons.add_shopping_cart),
                                      label: Text('Add to List'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.green,
                                        foregroundColor: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      )),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// Build scanning view with results
  Widget _buildScanningView() {
    return Container(
      decoration: const BoxDecoration(
        image: DecorationImage(
          image: AssetImage('assets/background.png'),
          fit: BoxFit.cover,
        ),
      ),
      child: SingleChildScrollView(
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
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                ),
                if (_imageFile != null && !_isLoading)
                  ElevatedButton.icon(
                    onPressed: _submitPhoto,
                    icon: const Icon(Icons.send),
                    label: const Text('Analyze'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ElevatedButton.icon(
                  onPressed: _resetToHome,
                  icon: const Icon(Icons.home),
                  label: const Text('Home'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Loading indicator
            if (_isLoading)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha((0.9 * 255).toInt()),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text(
                      'Analyzing nutrition information...',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),

            // Nutrition information
            if (_nutritionText.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.symmetric(horizontal: 4),
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info, color: Colors.white, size: 24),
                        SizedBox(width: 12),
                        Text(
                          'Nutrition Information',
                          style: TextStyle(
                            fontSize: 20,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 12),
                    Text(
                      _nutritionText,
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.left,
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 20),

            // Liver health bar
            if (_showLiverBar && _liverHealthScore != null)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                child: LiverHealthBar(healthScore: _liverHealthScore!),
              ),

            const SizedBox(height: 20),

            // Recipe suggestions from nutrition analysis
            _buildNutritionRecipeSuggestions(),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Recipe Scanner'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
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
      body: _showInitialView ? _buildInitialView() : _buildScanningView(),
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
              color: Colors.green,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.restaurant_menu,
                  color: Colors.white,
                  size: 48,
                ),
                SizedBox(height: 16),
                Text(
                  'Recipe Scanner Menu',
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
            leading: const Icon(Icons.star),
            title: const Text('Premium Features'),
            onTap: () {
              Navigator.pop(context);
              Navigator.pushNamed(context, '/premium');
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