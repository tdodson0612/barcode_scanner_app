// lib/home_screen.dart 
import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:liver_wise/services/local_draft_service.dart';
import 'package:liver_wise/services/saved_ingredients_service.dart';  
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:liver_wise/services/grocery_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:liver_wise/widgets/add_to_cookbook_button.dart';
import 'package:liver_wise/models/nutrition_info.dart';
import 'package:liver_wise/widgets/premium_gate.dart';
import 'package:liver_wise/controllers/premium_gate_controller.dart';
import 'package:liver_wise/liverhealthbar.dart';
import 'package:liver_wise/services/auth_service.dart';
import 'package:liver_wise/services/error_handling_service.dart';
import 'package:liver_wise/services/food_classifier_service.dart';
import 'package:liver_wise/models/favorite_recipe.dart';
import 'package:liver_wise/pages/search_users_page.dart';
import 'package:liver_wise/widgets/app_drawer.dart';
import 'package:liver_wise/config/app_config.dart';
import 'package:liver_wise/widgets/menu_icon_with_badge.dart';
import 'package:liver_wise/services/database_service_core.dart';
import 'package:liver_wise/services/favorite_recipes_service.dart';

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
        title: json['title'] ?? json['name'] ?? '',
        description: json['description'] ?? '',
        ingredients: json['ingredients'] is String
            ? (json['ingredients'] as String)
                .split(',')
                .map((e) => e.trim())
                .toList()
            : List<String>.from(json['ingredients'] ?? []),
        instructions: json['instructions'] ?? json['directions'] ?? '',
      );
}



class RecipeGenerator {
  /// Search recipes by one or more keywords (button selections).
  ///
  /// Rules:
  /// 1. Try AND (all keywords) first.
  /// 2. If none, fall back to OR (any keyword).
  /// 3. Sort by match count (most matches first).
  /// 4. Return up to 2 recipes.
  static Future<List<Recipe>> searchByKeywords(List<String> rawKeywords) async {
    // Normalize & dedupe keywords
    final keywords = rawKeywords
        .map((w) => w.trim().toLowerCase())
        .where((w) => w.isNotEmpty)
        .toSet()
        .toList();

    AppConfig.debugPrint('🔎 Selected keywords: $keywords');

    if (keywords.isEmpty) {
      AppConfig.debugPrint(
        '⚠️ No keywords selected, falling back to healthy defaults.',
      );
      return _getHealthyRecipes();
    }

    try {
      AppConfig.debugPrint('📡 Sending multi-keyword search: $keywords');

      // Send ALL keywords to worker in one request
      final response = await http.post(
        Uri.parse(AppConfig.cloudflareWorkerQueryEndpoint),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'search_recipes',
          'keyword': keywords, // Worker handles array now
          'limit': 50,
        }),
      );

      AppConfig.debugPrint('📡 Response status: ${response.statusCode}');
      AppConfig.debugPrint('📡 Response body: ${response.body}');

      if (response.statusCode != 200) {
        AppConfig.debugPrint('❌ Non-200 status: ${response.statusCode}');
        return _getHealthyRecipes();
      }

      final data = jsonDecode(response.body);

      // Handle new worker response format
      if (data is Map<String, dynamic>) {
        final results = data['results'] as List? ?? [];
        final matchType = data['matchType'] ?? 'UNKNOWN';
        final searchedKeywords = data['searchedKeywords'] as List? ?? [];
        final totalResults = data['totalResults'] ?? 0;

        AppConfig.debugPrint(
          '✅ Search complete: $matchType match, $totalResults total results',
        );
        AppConfig.debugPrint('🔍 Searched keywords: $searchedKeywords');

        if (results.isEmpty) {
          AppConfig.debugPrint('⚠️ No recipes found, using healthy defaults');
          return _getHealthyRecipes();
        }

        final recipes = results
            .map((item) => Recipe.fromJson(item as Map<String, dynamic>))
            .where((r) => r.title.isNotEmpty)
            .toList();

        AppConfig.debugPrint('✅ Parsed ${recipes.length} recipes');
        return recipes;
      }

      // Fallback for old response format (shouldn't happen)
      AppConfig.debugPrint('⚠️ Unexpected response format, using defaults');
      return _getHealthyRecipes();

    } catch (e) {
      AppConfig.debugPrint('❌ Error searching recipes: $e');
      return _getHealthyRecipes();
    }
  }
  /// Still available if you use liverHealthScore → static suggestions anywhere.
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
          title: 'Mediterranean Salmon Bowl',
          description: 'Heart-healthy salmon with fresh vegetables',
          ingredients: [
            'Fresh salmon',
            'Mixed greens',
            'Olive oil',
            'Lemon',
            'Cherry tomatoes',
          ],
          instructions:
              'Grill salmon, serve over greens with olive oil and lemon dressing.',
        ),
        Recipe(
          title: 'Quinoa Vegetable Stir-fry',
          description: 'Protein-rich quinoa with colorful vegetables',
          ingredients: [
            'Quinoa',
            'Bell peppers',
            'Broccoli',
            'Carrots',
            'Soy sauce',
          ],
          instructions:
              'Cook quinoa, stir-fry vegetables, combine and season.',
        ),
      ];

  static List<Recipe> _getModerateRecipes() => [
        Recipe(
          title: 'Baked Chicken with Sweet Potato',
          description: 'Lean protein with nutrient-rich sweet potato',
          ingredients: ['Chicken breast', 'Sweet potato', 'Herbs', 'Olive oil'],
          instructions:
              'Season chicken, bake with sweet potato slices until golden.',
        ),
        Recipe(
          title: 'Lentil Soup',
          description: 'Fiber-rich soup to support liver health',
          ingredients: [
            'Red lentils',
            'Carrots',
            'Celery',
            'Onions',
            'Vegetable broth',
          ],
          instructions:
              'Sauté vegetables, add lentils and broth, simmer until tender.',
        ),
      ];

  static List<Recipe> _getDetoxRecipes() => [
        Recipe(
          title: 'Green Detox Smoothie',
          description: 'Liver-cleansing green smoothie',
          ingredients: ['Spinach', 'Green apple', 'Lemon juice', 'Ginger', 'Water'],
          instructions: 'Blend all ingredients until smooth, serve immediately.',
        ),
        Recipe(
          title: 'Steamed Vegetables with Brown Rice',
          description: 'Simple, clean eating option',
          ingredients: ['Brown rice', 'Broccoli', 'Carrots', 'Zucchini', 'Herbs'],
          instructions:
              'Steam vegetables, serve over cooked brown rice with herbs.',
        ),
      ];
}

class NutritionApiService {
  static String get baseUrl => AppConfig.openFoodFactsUrl;

  static Future<NutritionInfo?> fetchNutritionInfo(String barcode) async {
    if (barcode.isEmpty) return null;
    final url = '$baseUrl/$barcode.json';

    try {
      final response = await http
          .get(
            Uri.parse(url),
            headers: {'User-Agent': 'FlutterApp/1.0'},
          )
          .timeout(Duration(seconds: AppConfig.apiTimeoutSeconds));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        // 🔥 DEBUG: Print raw API response
        if (AppConfig.enableDebugPrints) {
          print('📡 OpenFoodFacts API Response:');
          print('  Status: ${data['status']}');
          print('  Product name: ${data['product']?['product_name']}');
          print('  Nutriments keys: ${data['product']?['nutriments']?.keys.toList()}');
          print('  Sample nutriment: ${data['product']?['nutriments']?['energy-kcal_100g']}');
        }
        
        if (data['status'] == 1) {
          return NutritionInfo.fromJson(data);
        }
      }
      
      return null;
    } catch (e) {
      if (AppConfig.enableDebugPrints) {
        print('Nutrition API Error: $e');
      }
      return null;
    }
  }
}
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
      print('Barcode Scanner Error: $e');
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

// lib/home_screen.dart - PART 2 OF 5

class HomePage extends StatefulWidget {
  final bool isPremium;
  const HomePage({super.key, this.isPremium = false});

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with AutomaticKeepAliveClientMixin {
  bool _isScanning = false;
  List<Map<String, String>> _scannedRecipes = [];
  File? _imageFile;
  String _nutritionText = '';
  int? _liverHealthScore;
  bool _showLiverBar = false;
  bool _isLoading = false;
  List<Recipe> _recipeSuggestions = [];
  List<FavoriteRecipe> _favoriteRecipes = [];
  bool _showInitialView = true;
  NutritionInfo? _currentNutrition;

  late final PremiumGateController _premiumController;
  // ✅ REMOVED: StreamSubscription? _premiumSubscription;

  bool _isPremium = false;
  int _remainingScans = 3;
  bool _hasUsedAllFreeScans = false;

  InterstitialAd? _interstitialAd;
  bool _isAdReady = false;

  RewardedAd? _rewardedAd;
  bool _isRewardedAdReady = false;

  bool _isDisposed = false;

  final ImagePicker _picker = ImagePicker();
  final TextEditingController _searchController = TextEditingController();

  // ⭐ FINAL — only declared once
  List<String> _keywordTokens = [];
  Set<String> _selectedKeywords = {};
  bool _isSearchingRecipes = false;

  int _currentRecipeIndex = 0;
  static const int _recipesPerPage = 2;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _initializePremiumController();
    _initializeAsync();
  }

  bool _didPrecache = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_didPrecache) {
      _didPrecache = true;
      _precacheImages();
    }
  }

  Future<void> _precacheImages() async {
    await precacheImage(
      const AssetImage('assets/backgrounds/home_background.png'),
      context,
    );

    await precacheImage(
      const AssetImage('assets/backgrounds/login_background.png'),
      context,
    );

    if (MediaQuery.of(context).size.width > 600) {
      await precacheImage(
        const AssetImage('assets/backgrounds/ipad_background.png'),
        context,
      );
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    // ✅ FIXED: Remove listener properly (no cancel())
    _premiumController.removeListener(_onPremiumStateChanged);
    _interstitialAd?.dispose();
    _rewardedAd?.dispose();
    _searchController.dispose();
    super.dispose();
  }

// ✅ FIXED: Proper ChangeNotifier listener pattern with scheduled updates
  void _initializePremiumController() {
    _premiumController = PremiumGateController();

    // Add listener directly - addListener returns void, not StreamSubscription
    _premiumController.addListener(_onPremiumStateChanged);
    
    // Initialize state AFTER build phase using addPostFrameCallback
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _onPremiumStateChanged();
    });
  }


  void _onPremiumStateChanged() {
    if (!mounted || _isDisposed) return;
    
    // Schedule the setState for after the current build phase
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_isDisposed) {
        setState(() {
          _isPremium = _premiumController.isPremium;
          _remainingScans = _premiumController.remainingScans;
          _hasUsedAllFreeScans = _premiumController.hasUsedAllFreeScans;
        });
      }
    });
  }

  Future<void> _initializeAsync() async {
    try {
      // Delay initial refresh to avoid build phase issues
      await Future.delayed(const Duration(milliseconds: 100));
      
      if (!mounted || _isDisposed) return;
      
      await _premiumController.refresh();
      await _loadFavoriteRecipes();
      await _syncFavoritesFromDatabase();

      // These WILL be added in next portion
      _loadInterstitialAd();
      _loadRewardedAd();

    } catch (e) {
      if (mounted) {
        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          category: ErrorHandlingService.initializationError,
          showSnackBar: true,
          customMessage: 'Failed to initialize home screen',
        );
      }
    }
  }


    // ----------------------------------------------------
  // ADS — REQUIRED METHODS
  // ----------------------------------------------------

  // Load Interstitial Ad
  void _loadInterstitialAd() {
    if (_isDisposed) return;

    InterstitialAd.load(
      adUnitId: AppConfig.interstitialAdId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          if (!_isDisposed) {
            _interstitialAd = ad;
            _isAdReady = true;
            ad.setImmersiveMode(true);
          } else {
            ad.dispose();
          }
        },
        onAdFailedToLoad: (error) {
          _isAdReady = false;
          if (AppConfig.enableDebugPrints) {
            print("❌ Interstitial failed to load: $error");
          }
        },
      ),
    );
  }

  // Load Rewarded Ad
  void _loadRewardedAd() {
    if (_isDisposed) return;

    RewardedAd.load(
      adUnitId: AppConfig.rewardedAdId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          if (!_isDisposed) {
            _rewardedAd = ad;
            _isRewardedAdReady = true;
          } else {
            ad.dispose();
          }
        },
        onAdFailedToLoad: (error) {
          _isRewardedAdReady = false;
          if (AppConfig.enableDebugPrints) {
            print("❌ Rewarded failed to load: $error");
          }
        },
      ),
    );
  }

  // Show Interstitial Ad
  void _showInterstitialAd(VoidCallback onAdClosed) {
    if (_isDisposed || !_isAdReady || _interstitialAd == null) {
      onAdClosed();
      return;
    }

    _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _loadInterstitialAd();
        onAdClosed();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _loadInterstitialAd();
        onAdClosed();
      },
    );

    _interstitialAd!.show();
    _isAdReady = false;
  }


  Future<void> _syncFavoritesFromDatabase() async {
    try {
      final currentUserId = AuthService.currentUserId;
      if (currentUserId == null) return;

      final response = await http.post(
        Uri.parse(AppConfig.cloudflareWorkerQueryEndpoint),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'select',
          'table': 'favorite_recipes_with_details',
          'filters': {'user_id': currentUserId},
          'orderBy': 'created_at',
          'ascending': false,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as List;

        final favoriteRecipes = data.map((json) {
          return FavoriteRecipe(
            id: json['id'],
            userId: json['user_id'] ?? '',
            recipeName: json['recipe_name'] ?? json['title'] ?? '',
            ingredients: json['ingredients'] ?? '',
            directions: json['directions'] ?? '',
            createdAt:
                DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
            updatedAt: json['updated_at'] != null
                ? DateTime.tryParse(json['updated_at'])
                : null,
          );
        }).toList();

        if (mounted && !_isDisposed) {
          setState(() => _favoriteRecipes = favoriteRecipes);
        }

        await _saveFavoritesToLocalCache(favoriteRecipes);
        print('✅ Synced ${favoriteRecipes.length} favorites from database');
      }
    } catch (e) {
      print('⚠️ Error syncing favorites from database: $e');
    }
  }

  // -----------------------------------------------------
  // ⭐ NEW KEYWORD SYSTEM (NO LLM)
  // -----------------------------------------------------

  void _initKeywordButtonsFromProductName(String productName) {
    final tokens = productName
        .split(RegExp(r'\s+'))
        .map((w) => w.replaceAll(RegExp(r'[^\w]'), ''))
        .where((w) => w.length > 2)
        .toList();

    setState(() {
      _keywordTokens = tokens;
      _selectedKeywords = tokens.toSet();
    });
  }

  void _toggleKeyword(String word) {
    setState(() {
      if (_selectedKeywords.contains(word)) {
        _selectedKeywords.remove(word);
      } else {
        _selectedKeywords.add(word);
      }
    });
  }

  Future<void> _searchRecipesBySelectedKeywords() async {
    if (_selectedKeywords.isEmpty) {
      ErrorHandlingService.showSimpleError(
        context,
        'Please select at least one keyword.',
      );
      return;
    }

    try {
      setState(() {
        _isSearchingRecipes = true;
        _currentRecipeIndex = 0; // ⭐ RESET pagination on new search
      });

      final recipes =
          await RecipeGenerator.searchByKeywords(_selectedKeywords.toList());

      if (mounted && !_isDisposed) {
        setState(() => _recipeSuggestions = recipes);
      }

      if (recipes.isEmpty) {
        ErrorHandlingService.showSimpleError(
          context,
          'No recipes found for those ingredients.',
        );
      }
    } catch (e) {
      if (mounted) {
        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          category: ErrorHandlingService.databaseError,
          customMessage: 'Error searching recipes',
        );
      }
    } finally {
      if (mounted && !_isDisposed) {
        setState(() => _isSearchingRecipes = false);
      }
    }
  }

// Add these methods AFTER _searchRecipesBySelectedKeywords()

  void _loadNextRecipeSuggestions() {
    if (_recipeSuggestions.isEmpty) return;
    
    setState(() {
      _currentRecipeIndex += _recipesPerPage;
      if (_currentRecipeIndex >= _recipeSuggestions.length) {
        _currentRecipeIndex = 0; // Loop back to start
      }
    });
  }

  List<Recipe> _getCurrentPageRecipes() {
    if (_recipeSuggestions.isEmpty) return [];
    
    final endIndex = (_currentRecipeIndex + _recipesPerPage)
        .clamp(0, _recipeSuggestions.length);
    
    return _recipeSuggestions.sublist(_currentRecipeIndex, endIndex);
  }

  Future<void> _loadFavoriteRecipes() async {
    try {
      final recipes = await FavoriteRecipesService.getFavoriteRecipes();

      if (mounted && !_isDisposed) {
        setState(() => _favoriteRecipes = recipes);
      }
    } catch (e) {
      if (mounted) {
        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          category: ErrorHandlingService.databaseError,
          showSnackBar: true,
          customMessage: 'Failed to load favorite recipes',
        );
      }
    }
  }

  Future<void> _saveFavoritesToLocalCache(List<FavoriteRecipe> favorites) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final serialized =
          favorites.map((recipe) => jsonEncode(recipe.toCache())).toList();

      await prefs.setStringList('favorite_recipes_detailed', serialized);
      print('✅ Synced favorites to cache');
    } catch (e) {
      print('⚠️ Error saving favorites locally: $e');
    }
  }

  // PASTE THIS INTO home_screen.dart
  // REPLACE your existing _toggleFavoriteRecipe() method (around line 684)

  Future<void> _toggleFavoriteRecipe(Recipe recipe) async {
    try {
      final name = recipe.title;
      final ingredients = recipe.ingredients.join(', ');
      final directions = recipe.instructions;

      // ⭐ FIXED: Check if already favorited using improved service
      final existing = await FavoriteRecipesService.findExistingFavorite(
        recipeName: name,
      );

      if (existing != null) {
        // Recipe is favorited - remove it
        if (existing.id == null) {
          throw Exception('Favorite recipe has no ID — cannot remove');
        }

        await FavoriteRecipesService.removeFavoriteRecipe(existing.id!);

        setState(() {
          _favoriteRecipes.removeWhere((r) => r.recipeName == name);
        });

        if (mounted) {
          ErrorHandlingService.showSuccess(context, 'Removed from favorites');
        }
      } else {
        // Recipe is not favorited - add it
        try {
          final created = await FavoriteRecipesService.addFavoriteRecipe(
            name,
            ingredients,
            directions,
            // ⭐ TODO: If you have recipe.id from recipe_master, pass it here:
            // recipeId: recipe.id,
          );

          setState(() => _favoriteRecipes.add(created));
          await _saveFavoritesToLocalCache(_favoriteRecipes);

          if (mounted) {
            ErrorHandlingService.showSuccess(context, 'Added to favorites!');
          }
        } catch (e) {
          if (e.toString().contains('already in your favorites')) {
            // Handle duplicate error gracefully
            if (mounted) {
              ErrorHandlingService.showSimpleError(
                context,
                'This recipe is already in your favorites',
              );
            }
            return;
          }
          rethrow; // Other errors bubble up
        }
      }
    } catch (e) {
      if (mounted) {
        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          category: ErrorHandlingService.databaseError,
          customMessage: 'Error saving recipe',
        );
      }
    }
  }

  bool _isRecipeFavorited(String recipeTitle) {
    return _favoriteRecipes.any((fav) => fav.recipeName == recipeTitle);
  }

  void _resetToHome() {
    if (!mounted || _isDisposed) return;

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
      _keywordTokens = [];
      _selectedKeywords = {};
      _currentRecipeIndex = 0;
    });
  }

  Future<void> _debugCheckAllCaches() async {
    print('\n========================================');
    print('🔍 DEBUG: Checking ALL cache keys...');
    print('========================================\n');
    
    final prefs = await SharedPreferences.getInstance();
    final allKeys = prefs.getKeys().toList()..sort();
    
    // Filter for message/unread related keys
    final relevantKeys = allKeys.where((key) => 
      key.toLowerCase().contains('unread') ||
      key.toLowerCase().contains('message') ||
      key.toLowerCase().contains('badge') ||
      key.toLowerCase().contains('cached')
    ).toList();
    
    print('📊 Total cache keys: ${allKeys.length}');
    print('📬 Message/badge related keys: ${relevantKeys.length}\n');
    
    if (relevantKeys.isEmpty) {
      print('✅ No message/badge cache keys found (this is suspicious!)\n');
    } else {
      print('🔎 RELEVANT CACHE KEYS:\n');
      
      for (final key in relevantKeys) {
        final value = prefs.get(key);
        print('Key: $key');
        print('  Type: ${value.runtimeType}');
        
        if (value is String) {
          try {
            final decoded = jsonDecode(value);
            final preview = decoded.toString();
            print('  Value (parsed): ${preview.length > 200 ? preview.substring(0, 200) + '...' : preview}');
          } catch (_) {
            final preview = value.length > 100 ? value.substring(0, 100) + '...' : value;
            print('  Value: $preview');
          }
        } else {
          print('  Value: $value');
        }
        print('');
      }
    }
    
    // Check specific known keys
    print('\n🎯 CHECKING SPECIFIC BADGE CACHE KEYS:\n');
    
    final knownKeys = [
      'cached_unread_count',
      'cached_unread_count_time',
      'cache_messages_${AuthService.currentUserId}',
      'user_chats',
      'friend_requests',
    ];
    
    for (final key in knownKeys) {
      final value = prefs.get(key);
      if (value != null) {
        print('✅ Found: $key');
        print('   Value: $value');
        print('   Type: ${value.runtimeType}\n');
      } else {
        print('❌ Missing: $key\n');
      }
    }
    
    // Check timestamp freshness
    final cachedTime = prefs.getInt('cached_unread_count_time');
    if (cachedTime != null) {
      final age = DateTime.now().millisecondsSinceEpoch - cachedTime;
      final ageSeconds = (age / 1000).round();
      print('⏰ Badge cache age: $ageSeconds seconds');
      print('   Fresh?: ${age < 3000 ? "YES ✅" : "NO ❌ (stale!)"}\n');
    }
    
    print('========================================');
    print('🔍 DEBUG CHECK COMPLETE');
    print('========================================\n');
  }

  Future<void> _debugClearAllCaches() async {
    print('\n🗑️ NUCLEAR OPTION: Clearing ALL caches...\n');
    
    final prefs = await SharedPreferences.getInstance();
    
    // Get all message-related keys
    final keys = prefs.getKeys().where((key) => 
      key.toLowerCase().contains('unread') ||
      key.toLowerCase().contains('message') ||
      key.toLowerCase().contains('badge') ||
      key.toLowerCase().contains('cached') ||
      key.toLowerCase().contains('chat')
    ).toList();
    
    print('Found ${keys.length} cache keys to clear:');
    for (final key in keys) {
      print('  - $key');
      await prefs.remove(key);
    }
    
    print('\n✅ All message/badge caches cleared!');
    print('🔄 Now force refresh the badge...\n');
    
    // Force refresh badge
    await MenuIconWithBadge.invalidateCache();
    await AppDrawer.invalidateUnreadCache();
    
    // Force the widget to rebuild
    MenuIconWithBadge.globalKey.currentState?.refresh();
    
    print('✅ Badge refresh triggered!\n');
  }

// -----------------------------
// SCANNING & PHOTO OPERATIONS
// -----------------------------

  Future<void> _performScan() async {
    try {
      if (!_premiumController.canAccessFeature(PremiumFeature.scan)) {
        Navigator.pushNamed(context, '/purchase');
        return;
      }

      if (!_isPremium) {
        _showInterstitialAd(() => _executePerformScan());
      } else {
        _executePerformScan();
      }

    } catch (e) {
      if (mounted) {
        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          category: ErrorHandlingService.scanError,
          customMessage: 'Unable to start scan',
        );
      }
    }
  }

  Future<void> _executePerformScan() async {
    if (_isDisposed) return;

    try {
      setState(() => _isScanning = true);

      final success = await _premiumController.useScan();
      if (!success) {
        Navigator.pushNamed(context, '/purchase');
        return;
      }

      await Future.delayed(Duration(seconds: 2));

      if (mounted && !_isDisposed) {
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

        ErrorHandlingService.showSuccess(
          context,
          'Scan successful! ${_premiumController.remainingScans} scans remaining today.',
        );
      }
    } catch (e) {
      if (mounted) {
        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          category: ErrorHandlingService.scanError,
          customMessage: 'Error during scanning',
        );
      }
    } finally {
      if (mounted && !_isDisposed) {
        setState(() => _isScanning = false);
      }
    }
  }

  // -----------------------------
  // CAMERA HANDLING
  // -----------------------------

  Future<void> _takePhoto() async {
    try {
      if (!_premiumController.canAccessFeature(PremiumFeature.scan)) {
        Navigator.pushNamed(context, '/purchase');
        return;
      }

      if (!_isPremium) {
        _showInterstitialAd(() => _executeTakePhoto());
      } else {
        _executeTakePhoto();
      }

    } catch (e) {
      if (mounted) {
        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          category: ErrorHandlingService.imageError,
          customMessage: 'Unable to access camera',
        );
      }
    }
  }

  Future<void> _executeTakePhoto() async {
    if (_isDisposed) return;

    // ✅ NEW: Cleanup any existing image before taking new one
    if (_imageFile != null) {
      try {
        await _imageFile!.delete();
        AppConfig.debugPrint('🗑️ Deleted old image file');
      } catch (e) {
        AppConfig.debugPrint('⚠️ Could not delete old image: $e');
      }
    }

    try {
      if (mounted) {
        setState(() {
          _showInitialView = false;
          _nutritionText = '';
          _showLiverBar = false;
          _imageFile = null;
          _recipeSuggestions = [];
          _isLoading = false;
          _scannedRecipes = [];
          _keywordTokens = [];
          _selectedKeywords = {};
        });
      }

      // ✅ FIXED: More lenient settings + better error handling
      XFile? pickedFile;
      
      try {
        pickedFile = await _picker.pickImage(
          source: ImageSource.camera,
          imageQuality: 65,              // Reduced for faster processing
          maxWidth: 720,                 // Reduced from 800
          maxHeight: 720,                // Reduced from 800
          preferredCameraDevice: CameraDevice.rear,
        ).timeout(
          const Duration(seconds: 45),  // ✅ Increased timeout from 30s
          onTimeout: () {
            throw TimeoutException('Camera took too long. Please try again.');
          },
        );
      } catch (e) {
        // ✅ NEW: Handle specific camera errors
        if (e.toString().contains('camera_access_denied')) {
          throw Exception('Camera access denied. Please enable camera permissions in Settings.');
        } else if (e.toString().contains('operation_in_progress')) {
          throw Exception('Camera is already open. Please close it and try again.');
        } else if (e is TimeoutException) {
          throw TimeoutException('Camera operation timed out. Please ensure your device has enough memory and try again.');
        }
        rethrow;
      }

      if (pickedFile == null) {
        // User cancelled - reset to home
        if (mounted && !_isDisposed) {
          _resetToHome();
        }
        return;
      }

      // ✅ NEW: Verify file exists and is valid
      final file = File(pickedFile.path);
      
      try {
        final exists = await file.exists();
        
        if (!exists) {
          throw Exception('Captured image file not found');
        }

        // ✅ NEW: Check file size
        final fileSize = await file.length();
        
        if (fileSize == 0) {
          throw Exception('Captured image is empty. Please try again.');
        }
        
        if (fileSize > 10 * 1024 * 1024) {
          AppConfig.debugPrint('⚠️ Large image file: ${fileSize / (1024 * 1024)}MB');
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Image is large (${(fileSize / (1024 * 1024)).toStringAsFixed(1)}MB). Processing may take longer.'),
                backgroundColor: Colors.orange,
                duration: Duration(seconds: 3),
              ),
            );
          }
        }

        if (mounted && !_isDisposed) {
          setState(() => _imageFile = file);
          
          AppConfig.debugPrint('✅ Image captured: ${fileSize / 1024}KB');
          
          // ✅ NEW: Auto-analyze after successful capture
          if (mounted) {
            // Small delay to ensure UI updates
            await Future.delayed(Duration(milliseconds: 300));
            _submitPhoto();
          }
        }
      } catch (e) {
        // Clean up invalid file
        try {
          await file.delete();
        } catch (_) {}
        rethrow;
      }

    } on TimeoutException catch (e) {
      if (mounted) {
        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          category: ErrorHandlingService.imageError,
          customMessage: 'Camera operation timed out. Please ensure:\n• Your device has sufficient storage\n• Camera app is not running in background\n• Device has enough memory available',
          onRetry: _executeTakePhoto,
        );
      }
    } catch (e) {
      if (mounted) {
        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          category: ErrorHandlingService.imageError,
          customMessage: 'Failed to take photo',
          onRetry: _executeTakePhoto,
        );
      }
    }
  }

  // ✅ IMPROVED: Better barcode scanning with timeouts
  Future<void> _submitPhoto() async {
    if (_imageFile == null || _isDisposed) return;

    // ✅ NEW: Verify file still exists before processing
    final fileExists = await _imageFile!.exists();
    if (!fileExists) {
      if (mounted) {
        ErrorHandlingService.showSimpleError(
          context,
          'Image file not found. Please take a new photo.',
        );
        _resetToHome();
      }
      return;
    }

    try {
      final success = await _premiumController.useScan();
      if (!success) {
        Navigator.pushNamed(context, '/purchase');
        return;
      }

      if (mounted) {
        setState(() {
          _isLoading = true;
          _nutritionText = '';
          _showLiverBar = false;
          _recipeSuggestions = [];
          _keywordTokens = [];
          _selectedKeywords = {};
        });
      }

      // ✅ FIXED: Increased timeout and better error handling
      NutritionInfo? nutrition;
      
      try {
        nutrition = await BarcodeScannerService.scanAndLookup(_imageFile!.path)
            .timeout(
          const Duration(seconds: 20),  // ✅ Increased from 15s
          onTimeout: () {
            throw TimeoutException('Barcode scanning is taking too long. This may be due to:\n• Poor barcode quality\n• Poor lighting conditions\n• Network connection issues');
          },
        );
      } catch (e) {
        if (e is TimeoutException) {
          rethrow;
        }
        
        // Handle specific scanning errors
        if (e.toString().contains('network')) {
          throw Exception('Network error while looking up product. Please check your connection and try again.');
        }
        
        throw Exception('Error scanning barcode: ${e.toString()}');
      }

      // 🔥 DEBUG: Log the nutrition data
      if (nutrition != null) {
        AppConfig.debugPrint('✅ Nutrition data received:');
        AppConfig.debugPrint('  Product: ${nutrition.productName}');
        AppConfig.debugPrint('  Calories: ${nutrition.calories}');
        AppConfig.debugPrint('  Fat: ${nutrition.fat}');
        AppConfig.debugPrint('  Sugar: ${nutrition.sugar}');
        AppConfig.debugPrint('  Sodium: ${nutrition.sodium}');
      } else {
        AppConfig.debugPrint('❌ Nutrition is null');
      }


      if (nutrition == null) {
        if (mounted && !_isDisposed) {
          setState(() {
            _nutritionText = "No barcode found or product not recognized.\n\nTips:\n• Ensure barcode is clearly visible\n• Try better lighting\n• Hold camera steady\n• Make sure barcode fills most of frame";
            _showLiverBar = false;
            _isLoading = false;
          });
          
          // ✅ NEW: Show helpful error with retry option
          if (mounted) {
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: Row(
                  children: [
                    Icon(Icons.error_outline, color: Colors.orange),
                    SizedBox(width: 8),
                    Text('Barcode Not Found'),
                  ],
                ),
                content: Text(
                  'We couldn\'t detect a barcode in this image.\n\n'
                  'Tips for better results:\n'
                  '• Ensure barcode is clearly visible and centered\n'
                  '• Use good lighting (avoid shadows)\n'
                  '• Hold camera steady when taking photo\n'
                  '• Make sure barcode is not blurry\n'
                  '• Try holding phone closer or further away'
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _resetToHome();
                    },
                    child: Text('Cancel'),
                  ),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _executeTakePhoto();
                    },
                    icon: Icon(Icons.camera_alt),
                    label: Text('Try Again'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            );
          }
        }
        return;
      }

      final score = LiverHealthCalculator.calculate(
        fat: nutrition.fat,
        sodium: nutrition.sodium,
        sugar: nutrition.sugar,
        calories: nutrition.calories,
      );

      // Generate ingredient keyword buttons from product name
      _initKeywordButtonsFromProductName(nutrition.productName);

      // Auto-search recipes based on keywords
      if (_keywordTokens.isNotEmpty) {
        _searchRecipesBySelectedKeywords();
      }

      if (mounted && !_isDisposed) {
        setState(() {
          _nutritionText = _buildNutritionDisplay(nutrition!);
          _liverHealthScore = score;
          _showLiverBar = true;
          _isLoading = false;
          _currentNutrition = nutrition;
        });

        // ✅ FIXED: Better success message
        String message;
        if (_premiumController.isPremium) {
          message = '✅ Analysis successful! You have unlimited scans.';
        } else {
          final remaining = _premiumController.remainingScans.clamp(0, 3);
          message = '✅ Analysis successful! $remaining scan${remaining == 1 ? '' : 's'} remaining today.';
        }
        
        ErrorHandlingService.showSuccess(context, message);
      }

    } on TimeoutException catch (e) {
      if (mounted) {
        setState(() {
          _nutritionText = "Scanning timed out. Please try again.";
          _showLiverBar = false;
          _isLoading = false;
        });

        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          category: ErrorHandlingService.scanError,
          customMessage: e.message ?? 'Scanning operation timed out',
          onRetry: _submitPhoto,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _nutritionText = "Error: ${e.toString()}";
          _showLiverBar = false;
          _isLoading = false;
        });

        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          category: ErrorHandlingService.scanError,
          customMessage: 'Failed to analyze image',
          onRetry: _submitPhoto,
        );
      }
    }
  }
  // -----------------------------
  // SUPPORT UTILITIES
  // -----------------------------

  String _buildNutritionDisplay(NutritionInfo nutrition) {
    return "Product: ${nutrition.productName}\n"
          "Energy: ${nutrition.calories.toStringAsFixed(1)} kcal/100g\n"
          "Fat: ${nutrition.fat.toStringAsFixed(1)} g/100g\n"
          "Sugar: ${nutrition.sugar.toStringAsFixed(1)} g/100g\n"
          "Sodium: ${nutrition.sodium.toStringAsFixed(1)} mg/100g";
  }

  Future<void> _searchUsers(String query) async {
    if (query.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Please enter a search term'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    try {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => SearchUsersPage(initialQuery: query),
        ),
      );
    } catch (e) {
      if (mounted) {
        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          category: ErrorHandlingService.navigationError,
          customMessage: 'Error opening user search',
        );
      }
    }
  }

  Future<void> _addNutritionToGroceryList() async {
    if (_currentNutrition == null) {
      if (mounted) {
        ErrorHandlingService.showSimpleError(
          context,
          'No nutrition data available',
        );
      }
      return;
    }

    try {
      final productName = _currentNutrition!.productName;

      await GroceryService.addToGroceryList(productName);

      if (mounted) {
        ErrorHandlingService.showSuccess(
          context,
          'Added "$productName" to grocery list!',
        );
        Navigator.pushNamed(context, '/grocery-list');
      }

    } catch (e) {
      if (mounted) {
        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          category: ErrorHandlingService.navigationError,
          customMessage: 'Error adding to grocery list',
        );
      }
    }
  }

  // -----------------------------------------------------
  // SAVE SCANNED INGREDIENT TO SAVED INGREDIENTS
  // -----------------------------------------------------
  Future<void> _saveCurrentIngredient() async {
    if (_currentNutrition == null) {
      if (mounted) {
        ErrorHandlingService.showSimpleError(
          context,
          'No nutrition data available to save',
        );
      }
      return;
    }

    try {
      // Check if already saved
      final alreadySaved = await SavedIngredientsService.isSaved(
        _currentNutrition!.productName,
      );

      if (alreadySaved) {
        if (mounted) {
          final shouldUpdate = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Already Saved'),
              content: Text(
                '"${_currentNutrition!.productName}" is already in your saved ingredients.\n\n'
                'Do you want to update it?'
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Update'),
                ),
              ],
            ),
          );

          if (shouldUpdate != true) return;
        }
      }

      // Save the ingredient
      await SavedIngredientsService.saveIngredient(_currentNutrition!);

      if (mounted) {
        ErrorHandlingService.showSuccess(
          context,
          '✅ Saved "${_currentNutrition!.productName}" to ingredients!',
        );

        // Ask if user wants to view saved ingredients
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ingredient saved successfully'),
            backgroundColor: Colors.green,
            action: SnackBarAction(
              label: 'VIEW',
              textColor: Colors.white,
              onPressed: () {
                Navigator.pushNamed(context, '/saved-ingredients');
              },
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          category: ErrorHandlingService.databaseError,
          customMessage: 'Failed to save ingredient',
        );
      }
    }
  }



  Future<void> _saveRecipeDraft() async {
    if (_recipeSuggestions.isEmpty || _currentNutrition == null) {
      ErrorHandlingService.showSimpleError(
        context,
        'No recipe to save. Please scan a product first.',
      );
      return;
    }

    // Show dialog to select which recipe to save
    final selectedRecipe = await showDialog<Recipe>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save Recipe as Draft'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Select a recipe to save:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ..._getCurrentPageRecipes().map((recipe) {
              return ListTile(
                title: Text(recipe.title),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.pop(context, recipe),
              );
            }).toList(),
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

    if (selectedRecipe == null) return;

    try {
      // Convert Recipe ingredients to JSON format
      final ingredientsJson = selectedRecipe.ingredients
          .map((ing) => {
                'quantity': '',
                'measurement': '',
                'name': ing,
              })
          .toList();

      await LocalDraftService.saveDraft(
        name: selectedRecipe.title,
        ingredients: jsonEncode(ingredientsJson),
        directions: selectedRecipe.instructions,
      );

      if (mounted) {
        ErrorHandlingService.showSuccess(
          context,
          '✅ Recipe "${selectedRecipe.title}" saved as draft!',
        );

        // Ask if user wants to edit it now
        final shouldEdit = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Draft Saved'),
            content: Text(
              'Recipe "${selectedRecipe.title}" has been saved.\n\n'
              'Would you like to edit it now?'
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Later'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Edit Now'),
              ),
            ],
          ),
        );

        if (shouldEdit == true && mounted) {
          Navigator.pushNamed(context, '/submit-recipe');
        }
      }
    } catch (e) {
      if (mounted) {
        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          category: ErrorHandlingService.databaseError,
          customMessage: 'Failed to save recipe draft',
        );
      }
    }
  }

  // -----------------------------------------------------
  // ADD INGREDIENTS TO GROCERY LIST
  // -----------------------------------------------------
  Future<void> _addRecipeIngredientsToGroceryList(dynamic recipe) async {
    try {
      List<String> ingredients = [];

      if (recipe is Recipe) {
        ingredients = recipe.ingredients;
      } else if (recipe is Map<String, String>) {
        ingredients = recipe['ingredients']!
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
      } else {
        throw Exception("Unsupported recipe type");
      }

      if (ingredients.isEmpty) {
        ErrorHandlingService.showSimpleError(
          context,
          'No ingredients found for this recipe.',
        );
        return;
      }

      int addedCount = 0;

      for (String item in ingredients) {
        await GroceryService.addToGroceryList(item);
        addedCount++;
      }

      if (mounted) {
        ErrorHandlingService.showSuccess(
          context,
          'Added $addedCount ingredients to grocery list!',
        );
        Navigator.pushNamed(context, '/grocery-list');
      }
    } catch (e) {
      await ErrorHandlingService.handleError(
        context: context,
        error: e,
        category: ErrorHandlingService.databaseError,
        customMessage: 'Failed to add ingredients to grocery list',
      );
    }
  }

  // -----------------------------------------------------
  // MANUAL RECIPE CREATION FROM NUTRITION
  // -----------------------------------------------------
  Future<void> _makeRecipeFromNutrition() async {
    if (_currentNutrition == null) {
      if (mounted) {
        ErrorHandlingService.showSimpleError(
          context,
          'No nutrition data available',
        );
      }
      return;
    }

    try {
      final productName = _currentNutrition!.productName;

      // 🚀 NEW: Use existing keyword extraction (same system as recipe search)
      _initKeywordButtonsFromProductName(productName);

      final keywordString = _keywordTokens.join(', ');

      final recipeDraft = {
        'initialIngredients': keywordString.isNotEmpty ? keywordString : productName,
        'productName': productName,
        'initialTitle': "$productName Recipe",
        'initialDescription': "A recipe idea based on $productName.",
      };

      if (mounted) {
        final result = await Navigator.pushNamed(
          context,
          '/submit-recipe',
          arguments: recipeDraft,
        );

        if (result == true && mounted) {
          ErrorHandlingService.showSuccess(
            context,
            'Recipe submitted successfully!',
          );
          _resetToHome();
        }
      }
    } catch (e) {
      if (mounted) {
        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          category: ErrorHandlingService.navigationError,
          customMessage: 'Error opening recipe submission',
        );
      }
    }
  }


  // -----------------------------------------------------
  // NUTRITION RECIPE CARD UI
  // -----------------------------------------------------
  Widget _buildNutritionRecipeCard(Recipe recipe) {
    final isFavorite = _isRecipeFavorited(recipe.title);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ExpansionTile(
        title: Text(
          recipe.title,
          style: const TextStyle(
            fontSize: 16,
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            PremiumGate(
              feature: PremiumFeature.favoriteRecipes,
              featureName: 'Favorite Recipes',
              child: IconButton(
                icon: Icon(
                  isFavorite ? Icons.favorite : Icons.favorite_border,
                  color: isFavorite ? Colors.red : Colors.white,
                  size: 20,
                ),
                onPressed: () => _toggleFavoriteRecipe(recipe),
              ),
            ),
            const Icon(Icons.expand_more, color: Colors.white),
          ],
        ),
        iconColor: Colors.white,
        collapsedIconColor: Colors.white,
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  recipe.description,
                  style: const TextStyle(fontSize: 14, color: Colors.white70),
                ),
                const SizedBox(height: 8),
                Text(
                  'Ingredients: ${recipe.ingredients.join(', ')}',
                  style: const TextStyle(fontSize: 12, color: Colors.white60),
                ),
                const SizedBox(height: 8),
                Text(
                  'Instructions: ${recipe.instructions}',
                  style: const TextStyle(fontSize: 12, color: Colors.white60),
                ),
                const SizedBox(height: 12),
                
                // 🔥 UPDATED: Added Cookbook button
                Row(
                  children: [
                    Expanded(
                      child: PremiumGate(
                        feature: PremiumFeature.favoriteRecipes,
                        featureName: 'Favorite Recipes',
                        child: ElevatedButton.icon(
                          onPressed: () => _toggleFavoriteRecipe(recipe),
                          icon: const Icon(Icons.favorite),
                          label: const Text('Favorite'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    
                    // 🔥 NEW: Cookbook button
                    AddToCookbookButton(
                      recipeName: recipe.title,
                      ingredients: recipe.ingredients.join(', '),
                      directions: recipe.instructions,
                      compact: true,
                    ),
                    const SizedBox(width: 8),
                    
                    Expanded(
                      child: PremiumGate(
                        feature: PremiumFeature.groceryList,
                        featureName: 'Grocery List',
                        child: ElevatedButton.icon(
                          onPressed: () => _addRecipeIngredientsToGroceryList(recipe),
                          icon: const Icon(Icons.add_shopping_cart),
                          label: const Text('Grocery'),
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
          ),
        ],
      ),
    );
  }
  // Rest of the file continues unchanged from here...
  // (All remaining methods stay the same)

  // -----------------------------------------------------
  // INITIAL HOME VIEW
  // -----------------------------------------------------
  
  // lib/home_screen.dart - BACKGROUND IMAGE FIX
  // Replace your _buildInitialView() method with this version

  Widget _buildInitialView() {
    return Container(
      decoration: BoxDecoration(
        image: DecorationImage(
          image: AssetImage(
            MediaQuery.of(context).size.width > 600
                ? 'assets/backgrounds/ipad_background.png'
                : 'assets/backgrounds/home_background.png',
          ),
          fit: BoxFit.cover,
        ),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // -----------------------------------------
            // WELCOME CARD
            // -----------------------------------------
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha((0.9 * 255).toInt()),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Column(
                children: [
                  const Icon(Icons.scanner, size: 48, color: Colors.green),
                  const SizedBox(height: 12),
                  const Text(
                    'Welcome to Liver Food Scanner',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Scan products, look up foods, and get nutrition insights!',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey.shade600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 30),

            // -----------------------------------------
            // MAIN ACTION CARD (SCAN + BUTTONS)
            // -----------------------------------------
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha((0.95 * 255).toInt()),
                borderRadius: BorderRadius.circular(15),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // Premium Scan Status
                  if (!_isPremium)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _hasUsedAllFreeScans
                            ? Colors.red.shade50
                            : Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _hasUsedAllFreeScans
                              ? Colors.red.shade200
                              : Colors.blue.shade200,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _hasUsedAllFreeScans
                                ? Icons.warning_rounded
                                : Icons.info_outline,
                            color: _hasUsedAllFreeScans
                                ? Colors.red.shade700
                                : Colors.blue.shade700,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _hasUsedAllFreeScans
                                  ? 'Daily free scans used. Upgrade for unlimited!'
                                  : '$_remainingScans free scan${_remainingScans == 1 ? '' : 's'} remaining today',
                              style: TextStyle(
                                color: _hasUsedAllFreeScans
                                    ? Colors.red.shade900
                                    : Colors.blue.shade900,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 16),

                  // -----------------------------------------
                  // SCAN BUTTON
                  // -----------------------------------------
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton.icon(
                      onPressed: _isScanning ? null : _takePhoto,
                      icon: _isScanning
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2.5,
                              ),
                            )
                          : const Icon(Icons.camera_alt, size: 28),
                      label: Text(
                        _isScanning ? 'Scanning...' : 'Scan Food Product',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green.shade600,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 2,
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  Text(
                    'Take a photo of the product barcode',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade600,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 24),

                  // -----------------------------------------
                  // MANUAL BARCODE ENTRY BUTTON
                  // -----------------------------------------
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.pushNamed(
                        context,
                        '/manual-barcode-entry',
                      ),
                      icon: const Icon(Icons.edit),
                      label: const Text(
                        "Manual Barcode Entry",
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade600,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 2,
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // -----------------------------------------
                  // SEARCH FOOD NAME BUTTON
                  // -----------------------------------------
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton.icon(
                      onPressed: () =>
                          Navigator.pushNamed(context, '/nutrition-search'),
                      icon: const Icon(Icons.search),
                      label: const Text(
                        "Search Food by Name",
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange.shade800,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 2,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 30),

            // -----------------------------------------
            // RECIPE SUGGESTIONS SECTION
            // -----------------------------------------
            if (_scannedRecipes.isNotEmpty)
              PremiumGate(
                feature: PremiumFeature.viewRecipes,
                featureName: "Recipe Details",
                featureDescription:
                    "View full recipe details with ingredients and directions.",
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha((0.9 * 255).toInt()),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: const [
                          Icon(Icons.restaurant, color: Colors.green, size: 24),
                          SizedBox(width: 12),
                          Text(
                            "Recipe Suggestions",
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    ..._scannedRecipes.map((recipe) =>
                        _buildScannedRecipeCard(recipe)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ✅ ALSO FIX: _buildScanningView() - Replace the Stack with Container
  Widget _buildScanningView() {
    return Container(
      decoration: BoxDecoration(
        image: DecorationImage(
          image: AssetImage(
            MediaQuery.of(context).size.width > 600
                ? 'assets/backgrounds/ipad_background.png'
                : 'assets/backgrounds/home_background.png',
          ),
          fit: BoxFit.cover,
        ),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const SizedBox(height: 20),

            // IMAGE PREVIEW
            if (_imageFile != null)
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(
                    _imageFile!,
                    height: 300,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
              ),

            const SizedBox(height: 20),

            // BUTTON ROW
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: _takePhoto,
                    icon: const Icon(Icons.camera_alt),
                    label: const Text("Retake"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 8),

                  if (_imageFile != null && !_isLoading)
                    ElevatedButton.icon(
                      onPressed: _submitPhoto,
                      icon: const Icon(Icons.send),
                      label: const Text("Analyze"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  const SizedBox(width: 8),

                  // 🔥 NEW: Save Ingredient button (Issue #2, #3, #10 fix)
                  if (_currentNutrition != null && _nutritionText.isNotEmpty)
                    ElevatedButton.icon(
                      onPressed: _saveCurrentIngredient,
                      icon: const Icon(Icons.bookmark_add),
                      label: const Text("Save Ingredient"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  const SizedBox(width: 8),

                  if (_nutritionText.isNotEmpty)
                    ElevatedButton.icon(
                      onPressed: _addNutritionToGroceryList,
                      icon: const Icon(Icons.add_shopping_cart),
                      label: const Text("Grocery List"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.purple,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  const SizedBox(width: 8),

                  // Save Recipe Draft button (only show if recipes exist)
                  if (_recipeSuggestions.isNotEmpty)
                    ElevatedButton.icon(
                      onPressed: _saveRecipeDraft,
                      icon: const Icon(Icons.save_outlined),
                      label: const Text("Save Draft"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade700,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  const SizedBox(width: 8),

                  ElevatedButton.icon(
                    onPressed: _resetToHome,
                    icon: const Icon(Icons.home),
                    label: const Text("Home"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // LOADING
            if (_isLoading)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text("Analyzing nutrition information..."),
                  ],
                ),
              ),

            // NUTRITION INFO
            if (_nutritionText.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green.shade700,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _nutritionText,
                  style: const TextStyle(color: Colors.white),
                ),
              ),

            const SizedBox(height: 20),

            if (_showLiverBar && _liverHealthScore != null)
              LiverHealthBar(healthScore: _liverHealthScore!),

            const SizedBox(height: 20),

            _buildNutritionRecipeSuggestions(),
          ],
        ),
      ),
    );
  }

  // ----------------------------------------------------
  // SCANNED RECIPE CARD
  // ----------------------------------------------------
  Widget _buildScannedRecipeCard(Map<String, String> recipe) {
    final isFavorite = _isRecipeFavorited(recipe['name']!);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(10),
      ),
      child: ExpansionTile(
        title: Row(
          children: [
            const Icon(Icons.restaurant, color: Colors.green),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                recipe['name']!,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            PremiumGate(
              feature: PremiumFeature.favoriteRecipes,
              featureName: 'Favorite Recipes',
              child: IconButton(
                icon: Icon(
                  isFavorite ? Icons.favorite : Icons.favorite_border,
                  color: isFavorite ? Colors.red : Colors.grey,
                  size: 20,
                ),
                onPressed: () {
                  final recipeObj = Recipe(
                    title: recipe['name']!,
                    description: 'Scanned recipe',
                    ingredients: recipe['ingredients']!.split(', '),
                    instructions: recipe['directions']!,
                  );
                  _toggleFavoriteRecipe(recipeObj);
                },
              ),
            ),
            // 🔥 ADD: Cookbook button in header
            AddToCookbookButton(
              recipeName: recipe['name']!,
              ingredients: recipe['ingredients']!,
              directions: recipe['directions']!,
              compact: true,
            ),
            const Icon(Icons.expand_more),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Ingredients:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 8),
                Text(recipe['ingredients']!),
                const SizedBox(height: 16),
                const Text('Directions:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 8),
                Text(recipe['directions']!),
                const SizedBox(height: 16),
                
                // 🔥 UPDATED: Action buttons with Cookbook
                Row(
                  children: [
                    Expanded(
                      child: PremiumGate(
                        feature: PremiumFeature.favoriteRecipes,
                        featureName: 'Favorite Recipes',
                        child: ElevatedButton.icon(
                          onPressed: () {
                            final recipeObj = Recipe(
                              title: recipe['name']!,
                              description: 'Scanned recipe',
                              ingredients: recipe['ingredients']!.split(', '),
                              instructions: recipe['directions']!,
                            );
                            _toggleFavoriteRecipe(recipeObj);
                          },
                          icon: const Icon(Icons.favorite),
                          label: const Text('Favorite'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    
                    // 🔥 ADD: Cookbook button
                    AddToCookbookButton(
                      recipeName: recipe['name']!,
                      ingredients: recipe['ingredients']!,
                      directions: recipe['directions']!,
                      compact: true,
                    ),
                    const SizedBox(width: 8),
                    
                    Expanded(
                      child: PremiumGate(
                        feature: PremiumFeature.groceryList,
                        featureName: 'Grocery List',
                        child: ElevatedButton.icon(
                          onPressed: () =>
                              _addRecipeIngredientsToGroceryList(recipe),
                          icon: const Icon(Icons.add_shopping_cart),
                          label: const Text('Grocery'),
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
          ),
        ],
      ),
    );
  }


  // ----------------------------------------------------
  // HEALTH-BASED RECIPE SUGGESTIONS
  // ----------------------------------------------------
  Widget _buildNutritionRecipeSuggestions() {
    final hasKeywords = _keywordTokens.isNotEmpty;
    final hasRecipes = _recipeSuggestions.isNotEmpty;

    if (!hasKeywords && !hasRecipes) return const SizedBox.shrink();

    return PremiumGate(
      feature: PremiumFeature.viewRecipes,
      featureName: 'Recipe Details',
      featureDescription:
          'View full recipe details with ingredients and directions.',
      child: Container(
        margin: const EdgeInsets.all(20),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.blue.shade800,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with Save Draft button
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Expanded(
                  child: Text(
                    'Health-Based Recipe Suggestions:',
                    style: TextStyle(
                      fontSize: 20,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                // ✅ NEW: Save Draft button
                if (hasRecipes)
                  IconButton(
                    icon: const Icon(Icons.save_outlined, color: Colors.white),
                    tooltip: 'Save Recipe as Draft',
                    onPressed: _saveRecipeDraft,
                  ),
              ],
            ),
            const SizedBox(height: 12),

            // ---------------------------
            // KEYWORD BUTTONS
            // ---------------------------
            if (hasKeywords) ...[
              const Text(
                'Select your key search word(s):',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white70,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),

              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _keywordTokens.map((word) {
                  final selected = _selectedKeywords.contains(word);
                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => _toggleKeyword(word),
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: selected 
                              ? Colors.green 
                              : Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: selected ? Colors.white : Colors.white30,
                            width: 1.5,
                          ),
                        ),
                        child: Text(
                          word,
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),

              const SizedBox(height: 14),

              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton.icon(
                  onPressed:
                      _isSearchingRecipes ? null : _searchRecipesBySelectedKeywords,
                  icon: _isSearchingRecipes
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.search),
                  label: Text(
                      _isSearchingRecipes ? 'Searching...' : 'Search Recipes'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),

              const SizedBox(height: 18),

              if (!hasRecipes)
                const Text(
                  'No recipes yet. Select words above and tap Search.',
                  style: TextStyle(fontSize: 12, color: Colors.white60),
                ),
            ],

            // ---------------------------
            // RESULTS LIST (with pagination)
            // ---------------------------
            if (hasRecipes) ...[
              const SizedBox(height: 8),
              
              // Show current page recipes
              ..._getCurrentPageRecipes().map((r) => _buildNutritionRecipeCard(r)),
              
              // Pagination controls
              if (_recipeSuggestions.length > _recipesPerPage) ...[
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Showing ${_currentRecipeIndex + 1}-${(_currentRecipeIndex + _recipesPerPage).clamp(0, _recipeSuggestions.length)} of ${_recipeSuggestions.length} recipes',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white70,
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: _loadNextRecipeSuggestions,
                      icon: const Icon(Icons.arrow_forward, size: 16),
                      label: const Text('Next Suggestions'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

// ----------------------------------------------------
// MAIN BUILD()
// ----------------------------------------------------
@override
// Replace your entire build() method with this corrected version:

@override
Widget build(BuildContext context) {
  super.build(context);

  return Scaffold(
    drawerEnableOpenDragGesture: false,
    appBar: AppBar(
      leading: Builder(
        builder: (context) => IconButton(
          icon: MenuIconWithBadge(key: MenuIconWithBadge.globalKey),
          onPressed: () => Scaffold.of(context).openDrawer(),
        ),
      ),
      title: SizedBox(
        height: 40,
        child: TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: 'Search users...',
            hintStyle: const TextStyle(color: Colors.white70),
            prefixIcon:
                const Icon(Icons.person_search, color: Colors.white, size: 20),
            suffixIcon: IconButton(
              icon: const Icon(Icons.search, color: Colors.white),
              onPressed: () => _searchUsers(_searchController.text),
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(25),
              borderSide: BorderSide.none,
            ),
            filled: true,
            fillColor: Colors.white.withOpacity(0.2),
          ),
          style: const TextStyle(color: Colors.white),
          onSubmitted: (value) => _searchUsers(value),
        ),
      ),
      backgroundColor: Colors.green,
    ),
    drawer: AppDrawer(
      key: AppDrawer.globalKey,
      currentPage: 'home',
    ),
    body: _showInitialView ? _buildInitialView() : _buildScanningView(),
    // 🐛 TEMPORARY DEBUG BUTTONS (properly placed as Scaffold property)
    floatingActionButton: Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        FloatingActionButton(
          heroTag: 'debug1',
          mini: true,
          backgroundColor: Colors.orange,
          child: const Icon(Icons.bug_report, color: Colors.white),
          onPressed: _debugCheckAllCaches,
          tooltip: 'Check Caches',
        ),
        const SizedBox(height: 8),
        FloatingActionButton(
          heroTag: 'debug2',
          mini: true,
          backgroundColor: Colors.red,
          child: const Icon(Icons.delete_sweep, color: Colors.white),
          onPressed: () async {
            await _debugClearAllCaches();
            setState(() {}); // Force rebuild
          },
          tooltip: 'Clear All Caches',
        ),
      ],
    ),
  );
}
}