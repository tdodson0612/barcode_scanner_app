// lib/home_screen.dart - FULLY FIXED VERSION
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
  static Future<List<Recipe>> searchByKeywords(List<String> rawKeywords) async {
    final keywords = rawKeywords
        .map((w) => w.trim().toLowerCase())
        .where((w) => w.isNotEmpty)
        .toSet()
        .toList();

    AppConfig.debugPrint('🔎 Selected keywords: $keywords');

    if (keywords.isEmpty) {
      AppConfig.debugPrint('⚠️ No keywords selected, falling back to healthy defaults.');
      return _getHealthyRecipes();
    }

    try {
      AppConfig.debugPrint('📡 Sending multi-keyword search: $keywords');

      final response = await http.post(
        Uri.parse(AppConfig.cloudflareWorkerQueryEndpoint),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'search_recipes',
          'keyword': keywords,
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

      if (data is Map<String, dynamic>) {
        final results = data['results'] as List? ?? [];
        final matchType = data['matchType'] ?? 'UNKNOWN';
        final searchedKeywords = data['searchedKeywords'] as List? ?? [];
        final totalResults = data['totalResults'] ?? 0;

        AppConfig.debugPrint('✅ Search complete: $matchType match, $totalResults total results');
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

      AppConfig.debugPrint('⚠️ Unexpected response format, using defaults');
      return _getHealthyRecipes();

    } catch (e) {
      AppConfig.debugPrint('❌ Error searching recipes: $e');
      return _getHealthyRecipes();
    }
  }

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
          ingredients: ['Fresh salmon', 'Mixed greens', 'Olive oil', 'Lemon', 'Cherry tomatoes'],
          instructions: 'Grill salmon, serve over greens with olive oil and lemon dressing.',
        ),
        Recipe(
          title: 'Quinoa Vegetable Stir-fry',
          description: 'Protein-rich quinoa with colorful vegetables',
          ingredients: ['Quinoa', 'Bell peppers', 'Broccoli', 'Carrots', 'Soy sauce'],
          instructions: 'Cook quinoa, stir-fry vegetables, combine and season.',
        ),
      ];

  static List<Recipe> _getModerateRecipes() => [
        Recipe(
          title: 'Baked Chicken with Sweet Potato',
          description: 'Lean protein with nutrient-rich sweet potato',
          ingredients: ['Chicken breast', 'Sweet potato', 'Herbs', 'Olive oil'],
          instructions: 'Season chicken, bake with sweet potato slices until golden.',
        ),
        Recipe(
          title: 'Lentil Soup',
          description: 'Fiber-rich soup to support liver health',
          ingredients: ['Red lentils', 'Carrots', 'Celery', 'Onions', 'Vegetable broth'],
          instructions: 'Sauté vegetables, add lentils and broth, simmer until tender.',
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
          instructions: 'Steam vegetables, serve over cooked brown rice with herbs.',
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
    _premiumController.removeListener(_onPremiumStateChanged);
    _interstitialAd?.dispose();
    _rewardedAd?.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _initializePremiumController() {
    _premiumController = PremiumGateController();
    _premiumController.addListener(_onPremiumStateChanged);
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _onPremiumStateChanged();
    });
  }

  void _onPremiumStateChanged() {
    if (!mounted || _isDisposed) return;
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_isDisposed) {
        final wasPremium = _isPremium;
        final isPremiumNow = _premiumController.isPremium;
        
        setState(() {
          _isPremium = isPremiumNow;
          _remainingScans = _premiumController.remainingScans;
          _hasUsedAllFreeScans = _premiumController.hasUsedAllFreeScans;
        });
        
        // ⭐ If user became premium, dispose all ads
        if (!wasPremium && isPremiumNow) {
          if (AppConfig.enableDebugPrints) {
            print("🎉 User became PREMIUM - disposing all ads");
          }
          
          _interstitialAd?.dispose();
          _interstitialAd = null;
          _isAdReady = false;
          
          _rewardedAd?.dispose();
          _rewardedAd = null;
          _isRewardedAdReady = false;
        }
        
        // ⭐ If user lost premium, reload ads
        if (wasPremium && !isPremiumNow) {
          if (AppConfig.enableDebugPrints) {
            print("⬇️ User lost PREMIUM - loading ads");
          }
          
          _loadInterstitialAd();
          _loadRewardedAd();
        }
      }
    });
  }

  Future<void> _initializeAsync() async {
    try {
      await Future.delayed(const Duration(milliseconds: 100));
      
      if (!mounted || _isDisposed) return;
      
      // ⭐ CRITICAL: Load premium status FIRST, before ads
      await _premiumController.refresh();
      
      if (AppConfig.enableDebugPrints) {
        print("🔐 Premium status after refresh: $_isPremium");
      }
      
      // ⭐ Now load ads ONLY if user is free
      if (!_isPremium) {
        if (AppConfig.enableDebugPrints) {
          print("📺 Loading ads for FREE user");
        }
        _loadInterstitialAd();
        _loadRewardedAd();
      } else {
        if (AppConfig.enableDebugPrints) {
          print("🚫 Skipping ads for PREMIUM user");
        }
      }
      
      await _loadFavoriteRecipes();
      await _syncFavoritesFromDatabase();

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

  void _loadInterstitialAd() {
    if (_isDisposed || _isPremium) {
      if (AppConfig.enableDebugPrints && _isPremium) {
        print("🚫 Not loading interstitial - user is PREMIUM");
      }
      return;
    }

    InterstitialAd.load(
      adUnitId: AppConfig.interstitialAdId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          // ⭐ CRITICAL: Check premium status again after ad loads
          final isPremiumNow = _premiumController.isPremium;
          
          if (!_isDisposed && !isPremiumNow) {
            _interstitialAd = ad;
            _isAdReady = true;
            ad.setImmersiveMode(true);
            
            if (AppConfig.enableDebugPrints) {
              print("✅ Interstitial ad loaded (FREE user)");
            }
          } else {
            // User became premium while ad was loading - dispose it
            ad.dispose();
            if (AppConfig.enableDebugPrints) {
              print("🚫 Disposed ad - user is PREMIUM (became premium during load)");
            }
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

  void _loadRewardedAd() {
    if (_isDisposed || _isPremium) {
      if (AppConfig.enableDebugPrints && _isPremium) {
        print("🚫 Not loading rewarded ad - user is PREMIUM");
      }
      return;
    }

    RewardedAd.load(
      adUnitId: AppConfig.rewardedAdId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          // ⭐ CRITICAL: Check premium status again after ad loads
          final isPremiumNow = _premiumController.isPremium;
          
          if (!_isDisposed && !isPremiumNow) {
            _rewardedAd = ad;
            _isRewardedAdReady = true;
            
            if (AppConfig.enableDebugPrints) {
              print("✅ Rewarded ad loaded (FREE user)");
            }
          } else {
            // User became premium while ad was loading - dispose it
            ad.dispose();
            if (AppConfig.enableDebugPrints) {
              print("🚫 Disposed rewarded ad - user is PREMIUM (became premium during load)");
            }
          }
        },
        onAdFailedToLoad: (error) {
          _isRewardedAdReady = false;
          if (AppConfig.enableDebugPrints) {
            print("❌ Rewarded ad failed to load: $error");
          }
        },
      ),
    );
  }

  // ✅ FIXED: Never show ads to premium users (with double-check)
  void _showInterstitialAd(VoidCallback onAdClosed) {
    // ⭐ CRITICAL: Double-check premium status at show time
    final isPremiumNow = _premiumController.isPremium;
    
    if (_isDisposed || isPremiumNow || !_isAdReady || _interstitialAd == null) {
      if (AppConfig.enableDebugPrints) {
        if (isPremiumNow) {
          print("🚫 BLOCKED AD: User is PREMIUM");
        } else if (!_isAdReady) {
          print("⚠️ Ad not ready");
        } else if (_interstitialAd == null) {
          print("⚠️ No ad loaded");
        }
      }
      onAdClosed();
      return;
    }

    if (AppConfig.enableDebugPrints) {
      print("📺 Showing interstitial ad to FREE user");
    }

    _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        // Only reload if still free user
        if (!_premiumController.isPremium) {
          _loadInterstitialAd();
        }
        onAdClosed();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        if (!_premiumController.isPremium) {
          _loadInterstitialAd();
        }
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
            createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
            updatedAt: json['updated_at'] != null ? DateTime.tryParse(json['updated_at']) : null,
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
        _currentRecipeIndex = 0;
      });

      final recipes = await RecipeGenerator.searchByKeywords(_selectedKeywords.toList());

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

  void _loadNextRecipeSuggestions() {
    if (_recipeSuggestions.isEmpty) return;
    
    setState(() {
      _currentRecipeIndex += _recipesPerPage;
      if (_currentRecipeIndex >= _recipeSuggestions.length) {
        _currentRecipeIndex = 0;
      }
    });
  }

  List<Recipe> _getCurrentPageRecipes() {
    if (_recipeSuggestions.isEmpty) return [];
    
    final endIndex = (_currentRecipeIndex + _recipesPerPage).clamp(0, _recipeSuggestions.length);
    
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
      final serialized = favorites.map((recipe) => jsonEncode(recipe.toCache())).toList();

      await prefs.setStringList('favorite_recipes_detailed', serialized);
      print('✅ Synced favorites to cache');
    } catch (e) {
      print('⚠️ Error saving favorites locally: $e');
    }
  }

  Future<void> _toggleFavoriteRecipe(Recipe recipe) async {
    try {
      final name = recipe.title;
      final ingredients = recipe.ingredients.join(', ');
      final directions = recipe.instructions;

      final existing = await FavoriteRecipesService.findExistingFavorite(recipeName: name);

      if (existing != null) {
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
        try {
          final created = await FavoriteRecipesService.addFavoriteRecipe(
            name,
            ingredients,
            directions,
          );

          setState(() => _favoriteRecipes.add(created));
          await _saveFavoritesToLocalCache(_favoriteRecipes);

          if (mounted) {
            ErrorHandlingService.showSuccess(context, 'Added to favorites!');
          }
        } catch (e) {
          if (e.toString().contains('already in your favorites')) {
            if (mounted) {
              ErrorHandlingService.showSimpleError(
                context,
                'This recipe is already in your favorites',
              );
            }
            return;
          }
          rethrow;
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
    
    await MenuIconWithBadge.invalidateCache();
    await AppDrawer.invalidateUnreadCache();
    
    MenuIconWithBadge.globalKey.currentState?.refresh();
    
    print('✅ Badge refresh triggered!\n');
  }

  Future<void> _performScan() async {
    try {
      if (!_premiumController.canAccessFeature(PremiumFeature.scan)) {
        Navigator.pushNamed(context, '/purchase');
        return;
      }

      // ⭐ CRITICAL: Check premium status from controller directly
      final isPremiumNow = _premiumController.isPremium;
      
      if (AppConfig.enableDebugPrints) {
        print("🔍 Scan requested - Premium: $isPremiumNow, Ad Ready: $_isAdReady");
      }

      // Only show ad to FREE users with loaded ads
      if (!isPremiumNow && _isAdReady) {
        if (AppConfig.enableDebugPrints) {
          print("📺 Showing ad before scan (FREE user)");
        }
        _showInterstitialAd(() => _executePerformScan());
      } else {
        if (AppConfig.enableDebugPrints) {
          if (isPremiumNow) {
            print("✅ Skipping ad (PREMIUM user)");
          } else {
            print("⚠️ Skipping ad (no ad ready)");
          }
        }
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

  Future<void> _takePhoto() async {
    try {
      if (!_premiumController.canAccessFeature(PremiumFeature.scan)) {
        Navigator.pushNamed(context, '/purchase');
        return;
      }

      // ⭐ CRITICAL: Check premium status from controller directly
      final isPremiumNow = _premiumController.isPremium;
      
      if (AppConfig.enableDebugPrints) {
        print("📸 Photo requested - Premium: $isPremiumNow, Ad Ready: $_isAdReady");
      }

      // Only show ad to FREE users with loaded ads
      if (!isPremiumNow && _isAdReady) {
        if (AppConfig.enableDebugPrints) {
          print("📺 Showing ad before photo (FREE user)");
        }
        _showInterstitialAd(() => _executeTakePhoto());
      } else {
        if (AppConfig.enableDebugPrints) {
          if (isPremiumNow) {
            print("✅ Skipping ad (PREMIUM user)");
          } else {
            print("⚠️ Skipping ad (no ad ready)");
          }
        }
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

  // ✅ FIXED: Improved camera handling with better timeouts
  Future<void> _executeTakePhoto() async {
    if (_isDisposed) return;

    if (_imageFile != null) {
      try {
        if (await _imageFile!.exists()) {
          await _imageFile!.delete();
          AppConfig.debugPrint('🗑️ Deleted old image file');
        }
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

      XFile? pickedFile;
      
      try {
        pickedFile = await _picker.pickImage(
          source: ImageSource.camera,
          imageQuality: 70,
          maxWidth: 1024,
          maxHeight: 1024,
          preferredCameraDevice: CameraDevice.rear,
        ).timeout(
          const Duration(seconds: 90),
          onTimeout: () {
            throw TimeoutException('Camera timed out after 90 seconds');
          },
        );
      } on TimeoutException catch (e) {
        throw TimeoutException(
          'Camera operation timed out.\n\n'
          'Tips:\n'
          '• Close any background apps using the camera\n'
          '• Ensure sufficient device storage\n'
          '• Restart the app if problem persists'
        );
      } catch (e) {
        final errorString = e.toString().toLowerCase();
        
        if (errorString.contains('camera_access_denied') || errorString.contains('permission')) {
          throw Exception(
            'Camera permission denied.\n\n'
            'Please enable camera access in your device Settings:\n'
            'Settings > Apps > Liver Wise > Permissions > Camera'
          );
        } else if (errorString.contains('no camera available')) {
          throw Exception('No camera found on this device');
        } else if (errorString.contains('already in use')) {
          throw Exception(
            'Camera is already in use by another app.\n\n'
            'Please close other camera apps and try again.'
          );
        }
        
        rethrow;
      }

      if (pickedFile == null) {
        if (mounted && !_isDisposed) {
          _resetToHome();
        }
        return;
      }

      final file = File(pickedFile.path);
      
      try {
        final exists = await file.exists();
        if (!exists) {
          throw Exception('Image file not found after capture');
        }

        final fileSize = await file.length();
        
        if (fileSize == 0) {
          throw Exception('Captured image is empty. Please try again.');
        }
        
        if (fileSize < 1024) {
          throw Exception('Captured image is too small. Please try again.');
        }
        
        if (fileSize > 10 * 1024 * 1024) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Image is large (${(fileSize / (1024 * 1024)).toStringAsFixed(1)}MB). Processing may take longer.'
                ),
                backgroundColor: Colors.orange,
                duration: Duration(seconds: 3),
              ),
            );
          }
        }

        if (mounted && !_isDisposed) {
          setState(() => _imageFile = file);
          
          AppConfig.debugPrint('✅ Image captured: ${(fileSize / 1024).toStringAsFixed(1)}KB');
          
          if (mounted) {
            await Future.delayed(Duration(milliseconds: 300));
            _submitPhoto();
          }
        }
        
      } catch (e) {
        try {
          if (await file.exists()) {
            await file.delete();
          }
        } catch (_) {}
        rethrow;
      }

    } on TimeoutException catch (e) {
      if (mounted) {
        await _showCameraTimeoutDialog(e.message ?? 'Camera operation timed out');
      }
    } catch (e) {
      if (mounted) {
        final errorMessage = e.toString().replaceFirst('Exception: ', '');
        
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.error_outline, color: Colors.orange),
                SizedBox(width: 8),
                Expanded(child: Text('Camera Error')),
              ],
            ),
            content: Text(errorMessage),
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
  }

  // ✅ NEW: Improved timeout dialog
  Future<void> _showCameraTimeoutDialog(String message) async {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.wifi_off, color: Colors.orange),
            ),
            SizedBox(width: 12),
            Expanded(child: Text('Connection Issue')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message),
            SizedBox(height: 16),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.lightbulb_outline, 
                        color: Colors.blue.shade700, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Tips for Better Results:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade900,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  _buildTipRow('Close background apps'),
                  _buildTipRow('Ensure sufficient storage space'),
                  _buildTipRow('Check WiFi or cellular connection'),
                  _buildTipRow('Restart the app if needed'),
                ],
              ),
            ),
          ],
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
            icon: Icon(Icons.refresh),
            label: Text('Try Again'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTipRow(String text) {
    return Padding(
      padding: EdgeInsets.only(left: 8, top: 4),
      child: Row(
        children: [
          Icon(Icons.arrow_right, size: 16, color: Colors.blue.shade700),
          SizedBox(width: 4),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 13, color: Colors.blue.shade900),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _submitPhoto() async {
    if (_imageFile == null || _isDisposed) return;

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

      NutritionInfo? nutrition;
      
      try {
        nutrition = await BarcodeScannerService.scanAndLookup(_imageFile!.path).timeout(
          const Duration(seconds: 20),
          onTimeout: () {
            throw TimeoutException('Barcode scanning is taking too long. This may be due to:\n• Poor barcode quality\n• Poor lighting conditions\n• Network connection issues');
          },
        );
      } catch (e) {
        if (e is TimeoutException) {
          rethrow;
        }
        
        if (e.toString().contains('network')) {
          throw Exception('Network error while looking up product. Please check your connection and try again.');
        }
        
        throw Exception('Error scanning barcode: ${e.toString()}');
      }

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

      _initKeywordButtonsFromProductName(nutrition.productName);

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

      await SavedIngredientsService.saveIngredient(_currentNutrition!);

      if (mounted) {
        ErrorHandlingService.showSuccess(
          context,
          '✅ Saved "${_currentNutrition!.productName}" to ingredients!',
        );

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
                if (hasRecipes)
                  IconButton(
                    icon: const Icon(Icons.save_outlined, color: Colors.white),
                    tooltip: 'Save Recipe as Draft',
                    onPressed: _saveRecipeDraft,
                  ),
              ],
            ),
            const SizedBox(height: 12),

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

            if (hasRecipes) ...[
              const SizedBox(height: 8),
              
              ..._getCurrentPageRecipes().map((r) => _buildNutritionRecipeCard(r)),
              
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
              setState(() {});
            },
            tooltip: 'Clear All Caches',
          ),
        ],
      ),
    );
  }
}