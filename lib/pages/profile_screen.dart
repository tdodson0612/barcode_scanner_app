// lib/pages/profile_screen.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:liver_wise/services/account_deletion_service.dart';
import 'package:liver_wise/services/friends_visibility_service.dart';
import 'package:liver_wise/services/picture_service.dart';
import 'package:liver_wise/services/profile_service.dart';
import 'package:liver_wise/services/submitted_recipes_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart'; 
import 'dart:convert';


// 🔥 NEW — listens to refresh_profile events
import 'package:liver_wise/services/profile_events.dart';

import '../widgets/app_drawer.dart';
import '../widgets/premium_gate.dart';
import '../widgets/recipe_card.dart';
import '../controllers/premium_gate_controller.dart';
import '../models/submitted_recipe.dart';
import '../services/database_service_core.dart';
import '../services/auth_service.dart';
import '../services/error_handling_service.dart';
import '../pages/user_profile_page.dart';
import '../pages/edit_recipe_page.dart';
import '../pages/submit_recipe.dart';
import '../config/app_config.dart';

class ProfileScreen extends StatefulWidget {
  final List<String> favoriteRecipes;

  const ProfileScreen({super.key, required this.favoriteRecipes});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with AutomaticKeepAliveClientMixin {

  // 🔧 URLs instead of local files
  String? _profileImageUrl;
  String? _backgroundImageUrl;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  bool _isEditingName = false;
  bool _isEditingEmail = false;
  String _userName = 'User';
  String _userEmail = '';
  bool _isLoading = false;

  List<Map<String, dynamic>> _friends = [];
  bool _friendsListVisible = true;
  bool _isLoadingFriends = false;

  List<String> _pictures = [];
  bool _isLoadingPictures = false;
  static const int _maxPictures = 20;
  bool _picturesExpanded = true; // NEW: Controls pictures section expand/collapse
  static const String _picturesExpandedKey = 'pictures_section_expanded'; // 🔥 ADD THIS LINE


  List<SubmittedRecipe> _submittedRecipes = [];
  bool _isLoadingRecipes = false;

  late final PremiumGateController _premiumController;
  bool _isPremium = false;
  int _totalScansUsed = 0;
  bool _hasUsedAllFreeScans = false;

  // 🔥 NEW — stream subscription
  late final StreamSubscription _profileUpdateSub;

  // Cache configuration
  static const Duration _recipesCacheDuration = Duration(minutes: 5);
  static const Duration _picturesCacheDuration = Duration(minutes: 10);
  static const Duration _friendsCacheDuration = Duration(minutes: 2);

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();

    _initializePremiumController();
    _loadProfile();
    _loadFriends();
    _loadPictures();
    _loadSubmittedRecipes();

    // 🔥 Listen for background push-triggered profile refreshes
    _profileUpdateSub = profileUpdateStreamController.stream.listen((_) async {
      print("🔄 ProfileScreen: received refresh_profile event");
      await _loadProfile();
    });
  }

  @override
  void dispose() {
    _profileUpdateSub.cancel();

    _nameController.dispose();
    _emailController.dispose();

    _premiumController.removeListener(_updatePremiumState);
    super.dispose();
  }

  void _initializePremiumController() {
    _premiumController = PremiumGateController();
    _premiumController.addListener(_updatePremiumState);
    _updatePremiumState();
  }

  void _updatePremiumState() {
    if (mounted) {
      setState(() {
        _isPremium = _premiumController.isPremium;
        _totalScansUsed = _premiumController.totalScansUsed;
        _hasUsedAllFreeScans = _premiumController.hasUsedAllFreeScans;
      });
    }
  }


  // ========== CACHING HELPERS ==========

  Future<List<SubmittedRecipe>?> _getCachedRecipes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString('user_submitted_recipes');

      if (cached == null) return null;

      final data = json.decode(cached);
      final timestamp = data['_cached_at'] as int?;

      if (timestamp == null) return null;

      final age = DateTime.now().millisecondsSinceEpoch - timestamp;
      if (age > _recipesCacheDuration.inMilliseconds) return null;

      final recipes =
          (data['recipes'] as List).map((e) => SubmittedRecipe.fromJson(e)).toList();

      print('📦 Using cached submitted recipes (${recipes.length} found)');
      return recipes;
    } catch (e) {
      print('Error loading cached recipes: $e');
      return null;
    }
  }

  Future<void> _cacheRecipes(List<SubmittedRecipe> recipes) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheData = {
        'recipes': recipes.map((r) => r.toJson()).toList(),
        '_cached_at': DateTime.now().millisecondsSinceEpoch,
      };
      await prefs.setString('user_submitted_recipes', json.encode(cacheData));
      print('💾 Cached ${recipes.length} submitted recipes');
    } catch (e) {
      print('Error caching recipes: $e');
    }
  }

  Future<void> _invalidateRecipesCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('user_submitted_recipes');
    } catch (e) {
      print('Error invalidating recipes cache: $e');
    }
  }

  Future<List<String>?> _getCachedPictures() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString('user_pictures');

      if (cached == null) return null;

      final data = json.decode(cached);
      final timestamp = data['_cached_at'] as int?;

      if (timestamp == null) return null;

      final age = DateTime.now().millisecondsSinceEpoch - timestamp;
      if (age > _picturesCacheDuration.inMilliseconds) return null;

      final pictures = List<String>.from(data['pictures']);

      print('📦 Using cached pictures (${pictures.length} found)');
      return pictures;
    } catch (e) {
      print('Error loading cached pictures: $e');
      return null;
    }
  }

  Future<void> _cachePictures(List<String> pictures) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheData = {
        'pictures': pictures,
        '_cached_at': DateTime.now().millisecondsSinceEpoch,
      };
      await prefs.setString('user_pictures', json.encode(cacheData));
      print('💾 Cached ${pictures.length} pictures');
    } catch (e) {
      print('Error caching pictures: $e');
    }
  }

  Future<void> _invalidatePicturesCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('user_pictures');
    } catch (e) {
      print('Error invalidating pictures cache: $e');
    }
  }

  Future<List<Map<String, dynamic>>?> _getCachedFriends() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString('user_friends');

      if (cached == null) return null;

      final data = json.decode(cached);
      final timestamp = data['_cached_at'] as int?;

      if (timestamp == null) return null;

      final age = DateTime.now().millisecondsSinceEpoch - timestamp;
      if (age > _friendsCacheDuration.inMilliseconds) return null;

      final friends = (data['friends'] as List)
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      print('📦 Using cached friends (${friends.length} found)');
      return friends;
    } catch (e) {
      print('Error loading cached friends: $e');
      return null;
    }
  }

  Future<void> _cacheFriends(List<Map<String, dynamic>> friends) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheData = {
        'friends': friends,
        '_cached_at': DateTime.now().millisecondsSinceEpoch,
      };
      await prefs.setString('user_friends', json.encode(cacheData));
      print('💾 Cached ${friends.length} friends');
    } catch (e) {
      print('Error caching friends: $e');
    }
  }

  Future<void> _invalidateFriendsCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('user_friends');
    } catch (e) {
      print('Error invalidating friends cache: $e');
    }
  }

// ======================================================
// FIXED RUNTIME PERMISSIONS FOR ANDROID + iOS
// ======================================================
  Future<bool> requestImagePermission(ImageSource source) async {
    if (source == ImageSource.camera) {
      final status = await Permission.camera.request();
      if (!status.isGranted) {
        if (status.isPermanentlyDenied) {
          openAppSettings();
        }
        return false;
      }
      return true;
    }

    // ---- GALLERY ----
    if (Platform.isAndroid) {
      // Try photos permission first (Android 13+)
      var status = await Permission.photos.request();
      
      if (status.isGranted) return true;
      
      // If denied, try storage permission (Android 10-12)
      if (status.isDenied) {
        status = await Permission.storage.request();
        if (status.isGranted) return true;
      }
      
      // If permanently denied, open settings
      if (status.isPermanentlyDenied) {
        openAppSettings();
      }
      
      return false;
    }

    // iOS
    final status = await Permission.photos.request();
    if (!status.isGranted && status.isPermanentlyDenied) {
      openAppSettings();
    }
    return status.isGranted;
  }


  // ========== LOAD FUNCTIONS WITH CACHING ==========

  Future<void> _loadSubmittedRecipes({bool forceRefresh = false}) async {
    if (!mounted) return;

    setState(() {
      _isLoadingRecipes = true;
    });

    try {
      if (!forceRefresh) {
        final cachedRecipes = await _getCachedRecipes();

        if (cachedRecipes != null) {
          if (mounted) {
            setState(() {
              _submittedRecipes = cachedRecipes;
              _isLoadingRecipes = false;
            });
          }
          return;
        }
      }

      final recipes = await SubmittedRecipesService.getSubmittedRecipes();
      await _cacheRecipes(recipes);

      if (mounted) {
        setState(() {
          _submittedRecipes = recipes;
          _isLoadingRecipes = false;
        });
      }
    } catch (e) {
      print('Error loading recipes: $e');

      if (!forceRefresh) {
        final staleRecipes = await _getCachedRecipes();
        if (staleRecipes != null && mounted) {
          setState(() {
            _submittedRecipes = staleRecipes;
            _isLoadingRecipes = false;
          });
          return;
        }
      }

      if (mounted) {
        setState(() {
          _submittedRecipes = [];
          _isLoadingRecipes = false;
        });
      }
    }
  }

  Future<void> _deleteRecipe(int recipeId) async {
    setState(() {
      _isLoading = true;
    });

    try {
      await DatabaseServiceCore.deleteSubmittedRecipe(recipeId);
      await _invalidateRecipesCache();

      if (mounted) {
        await _loadSubmittedRecipes(forceRefresh: true);
        ErrorHandlingService.showSuccess(
            context, 'Recipe deleted successfully');
      }
    } catch (e) {
      if (mounted) {
        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          category: ErrorHandlingService.databaseError,
          customMessage: 'Unable to delete recipe',
          onRetry: () => _deleteRecipe(recipeId),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _editRecipe(SubmittedRecipe recipe) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => EditRecipePage(recipe: recipe),
      ),
    );

    if (result == true) {
      await _invalidateRecipesCache();
      await _loadSubmittedRecipes(forceRefresh: true);
    }
  }

  Future<void> _loadPictures({bool forceRefresh = false}) async {
    if (!mounted) return;

    setState(() {
      _isLoadingPictures = true;
    });

    try {
      if (!forceRefresh) {
        final cachedPictures = await _getCachedPictures();

        if (cachedPictures != null) {
          if (mounted) {
            setState(() {
              _pictures = cachedPictures;
              _isLoadingPictures = false;
            });
          }
          return;
        }
      }

      final pictures = await PictureService.getCurrentUserPictures();
      await _cachePictures(pictures);

      if (mounted) {
        setState(() {
          _pictures = pictures;
          _isLoadingPictures = false;
        });
      }
    } catch (e) {
      print('Error loading pictures: $e');

      if (!forceRefresh) {
        final stalePictures = await _getCachedPictures();
        if (stalePictures != null && mounted) {
          setState(() {
            _pictures = stalePictures;
            _isLoadingPictures = false;
          });
          return;
        }
      }

      if (mounted) {
        setState(() {
          _pictures = [];
          _isLoadingPictures = false;
        });
      }
    }
  }

// lib/pages/profile_screen.dart - REPLACE _uploadPicture method

  Future<void> _uploadPicture(ImageSource source) async {
    if (_pictures.length >= _maxPictures) {
      ErrorHandlingService.showSimpleError(
        context,
        'Maximum $_maxPictures pictures allowed. Please delete some first.',
      );
      return;
    }

    bool startedUpload = false;

    try {
      // ✅ Request permission using the helper function
      final allowed = await requestImagePermission(source);
      if (!allowed) {
        _showPermissionError(source == ImageSource.camera ? 'Camera' : 'Photos');
        return;
      }

      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );

      if (pickedFile == null || !mounted) {
        AppConfig.debugPrint('⚠️ No image selected or widget unmounted');
        return;
      }

      AppConfig.debugPrint('📸 Image picked: ${pickedFile.path}');

      setState(() {
        _isLoadingPictures = true;
      });
      startedUpload = true;

      final imageFile = File(pickedFile.path);
      
      AppConfig.debugPrint('🚀 Starting gallery upload...');
      final url = await PictureService.uploadPicture(imageFile);

      AppConfig.debugPrint('✅ Gallery upload complete: $url');

      // 🔥 FIX: Invalidate cache AND force immediate refresh
      await _invalidatePicturesCache();

      // Force immediate reload (loading state handled by _loadPictures)
      if (mounted) {
        await _loadPictures(forceRefresh: true);
      }

      if (mounted) {
        ErrorHandlingService.showSuccess(
          context,
          'Picture uploaded successfully!',
        );
      }
    } on Exception catch (e) {
      AppConfig.debugPrint('❌ Gallery upload exception: $e');
      
      if (mounted) {
        final errorMsg = e.toString().replaceFirst('Exception: ', '');
        
        // Check for specific error types
        if (errorMsg.contains('session expired') || errorMsg.contains('authentication')) {
          // Show sign-out prompt
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Session Expired'),
              content: const Text(
                'Your session has expired. Please sign out and sign back in to continue.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(context);
                    await AuthService.signOut();
                    if (mounted) {
                      Navigator.pushNamedAndRemoveUntil(
                        context,
                        '/login',
                        (route) => false,
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Sign Out'),
                ),
              ],
            ),
          );
        } else {
          // Show regular error dialog
          await ErrorHandlingService.handleError(
            context: context,
            error: e,
            category: ErrorHandlingService.imageError,
            customMessage: errorMsg,
            onRetry: () => _uploadPicture(source),
          );
        }
      }
    } catch (e) {
      AppConfig.debugPrint('❌ Gallery upload error: $e');
      
      if (mounted) {
        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          category: ErrorHandlingService.imageError,
          customMessage: 'Unable to upload picture',
          onRetry: () => _uploadPicture(source),
        );
      }
    } finally {
      if (mounted && startedUpload) {
        setState(() {
          _isLoadingPictures = false;
        });
      }
    }
  }

  Future<void> _deletePicture(String pictureUrl) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Delete Picture'),
          content: const Text('Are you sure you want to delete this picture?'),
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
        );
      },
    );

    if (confirm == true && mounted) {
      setState(() {
        _isLoadingPictures = true;
      });

      try {
        await PictureService.deletePicture(pictureUrl);
        await _invalidatePicturesCache();
        await _loadPictures(forceRefresh: true);

        if (mounted) {
          ErrorHandlingService.showSuccess(
              context, 'Picture deleted successfully');
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _isLoadingPictures = false;
          });

          await ErrorHandlingService.handleError(
            context: context,
            error: e,
            category: ErrorHandlingService.databaseError,
            customMessage: 'Unable to delete picture',
            onRetry: () => _deletePicture(pictureUrl),
          );
        }
      }
    }
  }

  void _showPictureOptionsDialog(String pictureUrl) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Picture Options'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.account_circle, color: Colors.blue),
                title: const Text('Set as Profile Picture'),
                onTap: () {
                  Navigator.pop(context);
                  _setAsProfilePicture(pictureUrl);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('Delete Picture'),
                onTap: () {
                  Navigator.pop(context);
                  _deletePicture(pictureUrl);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _setAsProfilePicture(String pictureUrl) async {
    setState(() {
      _isLoading = true;
    });

    try {
      await PictureService.setPictureAsProfilePicture(pictureUrl);

      // Update local state
      setState(() {
        _profileImageUrl = pictureUrl;
      });

      if (mounted) {
        ErrorHandlingService.showSuccess(context, 'Profile picture updated!');
      }
    } catch (e) {
      if (mounted) {
        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          category: ErrorHandlingService.databaseError,
          customMessage: 'Unable to set profile picture',
          onRetry: () => _setAsProfilePicture(pictureUrl),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showFullScreenImage(String imageUrl, int index) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: Text('Picture ${index + 1} of ${_pictures.length}'),
            actions: [
              IconButton(
                icon: const Icon(Icons.more_vert),
                onPressed: () {
                  Navigator.pop(context);
                  _showPictureOptionsDialog(imageUrl);
                },
              ),
            ],
          ),
          body: Center(
            child: InteractiveViewer(
              child: Image.network(
                imageUrl,
                fit: BoxFit.contain,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return Center(
                    child: CircularProgressIndicator(
                      value: loadingProgress.expectedTotalBytes != null
                          ? loadingProgress.cumulativeBytesLoaded /
                              loadingProgress.expectedTotalBytes!
                          : null,
                    ),
                  );
                },
                errorBuilder: (context, error, stackTrace) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error, size: 50, color: Colors.red),
                        SizedBox(height: 10),
                        Text(
                          'Failed to load image',
                          style: TextStyle(color: Colors.white),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showPictureUploadDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Add Picture'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt, color: Colors.blue),
                title: const Text('Take Photo'),
                onTap: () {
                  Navigator.pop(context);
                  _uploadPicture(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library, color: Colors.blue),
                title: const Text('Choose from Gallery'),
                onTap: () {
                  Navigator.pop(context);
                  _uploadPicture(ImageSource.gallery);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  // Helper method for showing permission errors
  void _showPermissionError(String permissionType) {
    if (!mounted) return;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$permissionType Access Required'),
        content: Text(
          'This app needs access to your $permissionType to upload pictures.\n\n'
          'Please enable $permissionType access in your device settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings(); // Opens device settings
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  Future<void> _loadFriends({bool forceRefresh = false}) async {
    if (!mounted) return;

    setState(() {
      _isLoadingFriends = true;
    });

    try {
      final currentUserId = AuthService.currentUserId;
      if (currentUserId == null) {
        if (mounted) {
          setState(() {
            _friends = [];
            _isLoadingFriends = false;
          });
        }
        return;
      }

      if (!forceRefresh) {
        final cachedFriends = await _getCachedFriends();

        if (cachedFriends != null) {
          final visibility = await FriendsVisibilityService.getFriendsListVisibility();

          if (mounted) {
            setState(() {
              _friends = cachedFriends;
              _friendsListVisible = visibility;
              _isLoadingFriends = false;
            });
          }
          return;
        }
      }

      final friends = await FriendsVisibilityService.getUserFriends(currentUserId);
      final visibility = await FriendsVisibilityService.getFriendsListVisibility();
      await _cacheFriends(friends);

      if (mounted) {
        setState(() {
          _friends = friends;
          _friendsListVisible = visibility;
          _isLoadingFriends = false;
        });
      }
    } catch (e) {
      print('Error loading friends: $e');

      if (!forceRefresh) {
        final staleFriends = await _getCachedFriends();
        if (staleFriends != null && mounted) {
          setState(() {
            _friends = staleFriends;
            _isLoadingFriends = false;
          });
          return;
        }
      }

      if (mounted) {
        setState(() {
          _friends = [];
          _isLoadingFriends = false;
        });
      }
    }
  }

  Future<void> _toggleFriendsVisibility(bool isVisible) async {
    try {
      await FriendsVisibilityService.updateFriendsListVisibility(isVisible);
      if (mounted) {
        setState(() {
          _friendsListVisible = isVisible;
        });

        ErrorHandlingService.showSuccess(
          context,
          isVisible
              ? 'Friends list is now visible to others'
              : 'Friends list is now hidden from others',
        );
      }
    } catch (e) {
      if (mounted) {
        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          category: ErrorHandlingService.databaseError,
          customMessage: 'Unable to update privacy setting',
          onRetry: () => _toggleFriendsVisibility(isVisible),
        );
      }
    }
  }

  Future<void> _confirmDeleteAccount() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Account'),
        content: const Text(
          'This action is permanent and cannot be undone.\n\n'
          'All your recipes, pictures, friends, and account data will be permanently deleted.\n\n'
          'Are you sure you want to continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Delete',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() {
      _isLoading = true;
    });

    try {
      // ✅ Call the DatabaseService method that handles everything
      await AccountDeletionService.deleteAccountCompletely();

      if (!mounted) return;

      // ✅ Sign out
      await AuthService.signOut();

      if (!mounted) return;

      // ✅ Navigate to login
      Navigator.pushNamedAndRemoveUntil(
        context,
        '/login',
        (route) => false,
      );

      // ✅ Show success message
      Future.delayed(Duration(milliseconds: 500), () {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Account deleted successfully'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
      });

    } catch (e, stackTrace) {
      print('❌ Error deleting account: $e');
      print('Stack trace: $stackTrace');
      
      if (!mounted) return;

      // Better error handling with specific messages
      String errorMessage = 'Unable to delete account';
      
      final errorString = e.toString().toLowerCase();
      
      if (errorString.contains('no user')) {
        errorMessage = 'You must be logged in to delete your account';
      } else if (errorString.contains('network') || errorString.contains('socket')) {
        errorMessage = 'Network error. Please check your connection.';
      } else if (errorString.contains('timeout')) {
        errorMessage = 'Request timed out. Please try again.';
      } else if (errorString.contains('authentication') || errorString.contains('401')) {
        errorMessage = 'Session expired. Please sign out and sign back in.';
      } else if (errorString.contains('permission') || errorString.contains('403')) {
        errorMessage = 'Permission denied. Please sign out and try again.';
      } else {
        // Show the actual error to help debug
        errorMessage = 'Delete failed: ${e.toString().substring(0, e.toString().length > 100 ? 100 : e.toString().length)}';
      }

      // Show detailed error dialog
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Delete Account Failed'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(errorMessage),
                SizedBox(height: 16),
                Text(
                  'Technical details:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
                SizedBox(height: 4),
                Text(
                  e.toString(),
                  style: TextStyle(fontSize: 10, fontFamily: 'monospace'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('OK'),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // 🔧 Load profile + background URLs from database
  // Replace the _loadProfile() method in ProfileScreen with this:

  Future<void> _loadProfile() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();

      // Load from database
      final profile = await ProfileService.getCurrentUserProfile();

      if (profile != null && mounted) {
        final userName = profile['username'] ?? 'User';
        final userEmail = profile['email'] ?? '';
        
        // ✅ Use the correct field names from database
        final profilePictureUrl = profile['profile_picture'] as String?;
        final backgroundPictureUrl = profile['profile_background'] as String?;

        AppConfig.debugPrint('👤 Profile picture: $profilePictureUrl');
        AppConfig.debugPrint('🏞️ Background picture: $backgroundPictureUrl');

        // Save to local preferences for fallback
        await prefs.setString('user_name', userName);
        await prefs.setString('user_email', userEmail);
        if (profilePictureUrl != null) {
          await prefs.setString('profile_picture_url', profilePictureUrl);
        }
        if (backgroundPictureUrl != null) {
          await prefs.setString('background_picture_url', backgroundPictureUrl);
        }

        // 🔥 NEW: Restore pictures collapse state
        final expandedState = prefs.getBool(_picturesExpandedKey) ?? true;

        if (mounted) {
          setState(() {
            _userName = userName;
            _userEmail = userEmail;
            _nameController.text = userName;
            _emailController.text = userEmail;
            _profileImageUrl = profilePictureUrl;
            _backgroundImageUrl = backgroundPictureUrl;
            _picturesExpanded = expandedState; // 🔥 Restore collapse state
            
            AppConfig.debugPrint('✅ Profile loaded successfully');
          });
        }
      } else {
        // Fallback to local preferences
        final savedName = prefs.getString('user_name') ?? 'User';
        final savedEmail = prefs.getString('user_email') ?? '';
        final savedProfilePicture = prefs.getString('profile_picture_url');
        final savedBackgroundPicture = prefs.getString('background_picture_url');
        final expandedState = prefs.getBool(_picturesExpandedKey) ?? true;

        if (mounted) {
          setState(() {
            _userName = savedName;
            _userEmail = savedEmail;
            _nameController.text = savedName;
            _emailController.text = savedEmail;
            _profileImageUrl = savedProfilePicture;
            _backgroundImageUrl = savedBackgroundPicture;
            _picturesExpanded = expandedState; // 🔥 Restore collapse state
            
            AppConfig.debugPrint('⚠️ Using cached profile data');
          });
        }
      }
    } catch (e) {
      AppConfig.debugPrint('❌ Error loading profile: $e');
      
      try {
        final prefs = await SharedPreferences.getInstance();
        final savedName = prefs.getString('user_name') ?? 'User';
        final savedEmail = prefs.getString('user_email') ?? '';
        final savedProfilePicture = prefs.getString('profile_picture_url');
        final savedBackgroundPicture = prefs.getString('background_picture_url');
        final expandedState = prefs.getBool(_picturesExpandedKey) ?? true;

        if (mounted) {
          setState(() {
            _userName = savedName;
            _userEmail = savedEmail;
            _nameController.text = savedName;
            _emailController.text = savedEmail;
            _profileImageUrl = savedProfilePicture;
            _backgroundImageUrl = savedBackgroundPicture;
            _picturesExpanded = expandedState; // 🔥 Restore collapse state
          });
        }
      } catch (e2) {
        AppConfig.debugPrint('❌ Error loading from preferences: $e2');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _savePicturesExpandedState(bool expanded) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_picturesExpandedKey, expanded);
    } catch (e) {
      AppConfig.debugPrint('Error saving pictures expanded state: $e');
    }
  }

  // 🔧 Upload profile picture to Supabase Storage and save URL to database
  Future<void> _pickImage(ImageSource source) async {
    try {
      // 🔥 Request correct runtime permission
      final allowed = await requestImagePermission(source);
      if (!allowed) {
        _showPermissionError(source == ImageSource.camera ? 'Camera' : 'Photos');
        return;
      }

      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (pickedFile == null || !mounted) return;

      setState(() {
        _isLoading = true;
      });

      final imageFile = File(pickedFile.path);
      final url = await PictureService.uploadProfilePicture(imageFile);

      if (mounted) {
        setState(() {
          _profileImageUrl = url;
          _isLoading = false;
        });

        ErrorHandlingService.showSuccess(context, 'Profile picture updated!');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });

        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          category: ErrorHandlingService.imageError,
          customMessage: 'Unable to upload profile picture',
          onRetry: () => _pickImage(source),
        );
      }
    }
  }

  // 🔧 Upload background to Supabase Storage and save URL to database
  Future<void> _pickBackgroundImage(ImageSource source) async {
    try {
      // 🔥 Request correct runtime permission
      final allowed = await requestImagePermission(source);
      if (!allowed) {
        _showPermissionError(source == ImageSource.camera ? 'Camera' : 'Photos');
        return;
      }

      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );

      if (pickedFile == null || !mounted) return;

      setState(() {
        _isLoading = true;
      });

      final imageFile = File(pickedFile.path);
      final url = await PictureService.uploadBackgroundPicture(imageFile);

      if (mounted) {
        setState(() {
          _backgroundImageUrl = url;
          _isLoading = false;
        });

        ErrorHandlingService.showSuccess(context, 'Background updated!');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });

        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          category: ErrorHandlingService.imageError,
          customMessage: 'Unable to update background',
          onRetry: () => _pickBackgroundImage(source),
        );
      }
    }
  }

  Future<void> _removeBackgroundImage() async {
    try {
      setState(() {
        _isLoading = true;
      });

      await DatabaseServiceCore.removeBackgroundPicture();

      if (mounted) {
        setState(() {
          _backgroundImageUrl = null;
          _isLoading = false;
        });

        ErrorHandlingService.showSuccess(context, 'Background reset to default');
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
          customMessage: 'Unable to reset background',
        );
      }
    }
  }

  Future<void> _saveUserName() async {
    if (_nameController.text.trim().isEmpty) {
      ErrorHandlingService.showSimpleError(context, 'Name cannot be empty');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      await ProfileService.updateProfile(
        username: _nameController.text.trim(),
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_name', _nameController.text.trim());

      if (mounted) {
        setState(() {
          _userName = _nameController.text.trim();
          _isEditingName = false;
        });

        ErrorHandlingService.showSuccess(
            context, 'Name updated successfully!');
      }
    } catch (e) {
      if (mounted) {
        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          category: ErrorHandlingService.databaseError,
          customMessage: 'Unable to update name',
          onRetry: _saveUserName,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _saveUserEmail() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      ErrorHandlingService.showSimpleError(context, 'Email cannot be empty');
      return;
    }

    if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email)) {
      ErrorHandlingService.showSimpleError(
          context, 'Please enter a valid email address');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      await ProfileService.updateProfile(email: email);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_email', email);

      if (mounted) {
        setState(() {
          _userEmail = email;
          _isEditingEmail = false;
        });

        ErrorHandlingService.showSuccess(
            context, 'Email updated successfully!');
      }
    } catch (e) {
      if (mounted) {
        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          category: ErrorHandlingService.databaseError,
          customMessage: 'Unable to update email',
          onRetry: _saveUserEmail,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Widget _sectionContainer({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha((0.9 * 255).toInt()),
        borderRadius: BorderRadius.circular(10),
      ),
      child: child,
    );
  }

  void _toggleEditName() {
    setState(() {
      _isEditingName = !_isEditingName;
      if (_isEditingName) {
        _nameController.text = _userName;
      }
    });
  }

  void _toggleEditEmail() {
    setState(() {
      _isEditingEmail = !_isEditingEmail;
      if (_isEditingEmail) {
        _emailController.text = _userEmail;
      }
    });
  }

  void _cancelEditName() {
    setState(() {
      _isEditingName = false;
      _nameController.text = _userName;
    });
  }

  void _cancelEditEmail() {
    setState(() {
      _isEditingEmail = false;
      _emailController.text = _userEmail;
    });
  }

  void _showImagePickerDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Select Profile Picture'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Take Photo'),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Choose from Gallery'),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.gallery);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showBackgroundPickerDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Select Background'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt, color: Colors.blue),
                title: const Text('Take Photo'),
                onTap: () {
                  Navigator.pop(context);
                  _pickBackgroundImage(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library, color: Colors.blue),
                title: const Text('Choose from Gallery'),
                onTap: () {
                  Navigator.pop(context);
                  _pickBackgroundImage(ImageSource.gallery);
                },
              ),
              if (_backgroundImageUrl != null) ...[
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.restore, color: Colors.orange),
                  title: const Text('Reset to Default'),
                  onTap: () {
                    Navigator.pop(context);
                    _removeBackgroundImage();
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  void _navigateToUserProfile(String userId) {
    try {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => UserProfilePage(userId: userId),
        ),
      ).then((_) {
        _invalidateFriendsCache();
        _loadFriends(forceRefresh: true);
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to open profile')),
        );
      }
    }
  }

  void _navigateToSearchUsers() {
    try {
      Navigator.pushNamed(context, '/search-users');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Search page unavailable')),
        );
      }
    }
  }

  void _showFullFriendsList() {
    try {
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Row(
              children: const [
                Icon(Icons.people, color: Colors.blue),
                SizedBox(width: 8),
                Text('All Friends'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('You have ${_friends.length} friends:'),
                const SizedBox(height: 12),
                Container(
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: SingleChildScrollView(
                    child: Column(
                      children: _friends
                          .map(
                            (friend) => ListTile(
                              leading: CircleAvatar(
                                backgroundImage: friend['avatar_url'] != null
                                    ? NetworkImage(friend['avatar_url'])
                                    : null,
                                child: friend['avatar_url'] == null
                                    ? Text(
                                        (friend['username'] ?? 'U')[0]
                                            .toUpperCase(),
                                      )
                                    : null,
                              ),
                              title: Text(
                                friend['first_name'] != null &&
                                        friend['last_name'] != null
                                    ? '${friend['first_name']} ${friend['last_name']}'
                                    : friend['username'] ?? 'Unknown',
                              ),
                              onTap: () {
                                Navigator.pop(context);
                                _navigateToUserProfile(friend['id']);
                              },
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          );
        },
      );
    } catch (e) {
      print('Error showing friends dialog: $e');
    }
  }

  Widget _buildPremiumStatusSection() {
    return _sectionContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_isPremium) ...[
            Row(
              children: [
                const Icon(Icons.star, color: Colors.amber, size: 24),
                const SizedBox(width: 8),
                Text(
                  'Premium Account Active',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.amber.shade700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'You have access to all premium features!',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ] else ...[
            Row(
              children: [
                const Icon(Icons.person, color: Colors.grey, size: 24),
                const SizedBox(width: 8),
                Text(
                  'Free Account',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Daily scans used: $_totalScansUsed/3',
              style: TextStyle(
                color: _hasUsedAllFreeScans
                    ? Colors.red.shade600
                    : Colors.grey.shade600,
                fontWeight: _hasUsedAllFreeScans
                    ? FontWeight.w600
                    : FontWeight.normal,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  try {
                    Navigator.pushNamed(context, '/purchase');
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Premium page unavailable')),
                    );
                  }
                },
                icon: const Icon(Icons.star),
                label: const Text('Upgrade to Premium'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPicturesSection() {
    return _sectionContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 🔥 FIX: Make header clickable to expand/collapse with persistence
          InkWell(
            onTap: () {
              setState(() {
                _picturesExpanded = !_picturesExpanded;
              });
              _savePicturesExpandedState(_picturesExpanded); // 🔥 Persist state
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text(
                      'Pictures (${_pictures.length}/$_maxPictures)',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      _picturesExpanded ? Icons.expand_less : Icons.expand_more,
                      color: Colors.grey.shade600,
                    ),
                  ],
                ),
                if (_pictures.length < _maxPictures && _picturesExpanded)
                  IconButton(
                    icon: const Icon(Icons.add_photo_alternate, color: Colors.blue),
                    onPressed: _showPictureUploadDialog,
                    tooltip: 'Add Picture',
                  ),
              ],
            ),
          ),
          
          // Only show content if expanded
          if (_picturesExpanded) ...[
            const SizedBox(height: 12),
          if (_isLoadingPictures) ...[
            const Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(),
              ),
            ),
          ] else if (_pictures.isEmpty) ...[
            Center(
              child: Column(
                children: [
                  Icon(
                    Icons.photo_library,
                    size: 50,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'No pictures yet',
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: _showPictureUploadDialog,
                    icon: const Icon(Icons.add_photo_alternate),
                    label: const Text('Add Your First Picture'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 1,
              ),
              itemCount: _pictures.length,
              itemBuilder: (context, index) {
                final pictureUrl = _pictures[index];
                return GestureDetector(
                  onTap: () => _showFullScreenImage(pictureUrl, index),
                  onLongPress: () => _showPictureOptionsDialog(pictureUrl),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        pictureUrl,
                        fit: BoxFit.cover,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return Center(
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              value:
                                  loadingProgress.expectedTotalBytes != null
                                      ? loadingProgress.cumulativeBytesLoaded /
                                          loadingProgress.expectedTotalBytes!
                                      : null,
                            ),
                          );
                        },
                        errorBuilder: (context, error, stackTrace) {
                          return Center(
                            child: Icon(
                              Icons.broken_image,
                              color: Colors.grey.shade400,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ],
      ],
      ),
    );
  }

  Widget _buildSubmittedRecipesSection() {
    return _sectionContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'My Submitted Recipes (${_submittedRecipes.length})',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle, color: Colors.green),
                onPressed: () async {
                  try {
                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const SubmitRecipePage(),
                      ),
                    );

                    if (result == true && mounted) {
                      await _invalidateRecipesCache();
                      await _loadSubmittedRecipes(forceRefresh: true);
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Recipe page unavailable')),
                      );
                    }
                  }
                },
                tooltip: 'Submit New Recipe',
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_isLoadingRecipes) ...[
            const Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(),
              ),
            ),
          ] else if (_submittedRecipes.isEmpty) ...[
            Center(
              child: Column(
                children: [
                  Icon(
                    Icons.restaurant_menu,
                    size: 50,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'No recipes submitted yet',
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Share your favorite recipes with the community!',
                    style: TextStyle(
                      color: Colors.grey.shade500,
                      fontSize: 12,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: () async {
                      try {
                        final result = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const SubmitRecipePage(),
                          ),
                        );

                        if (result == true && mounted) {
                          await _invalidateRecipesCache();
                          await _loadSubmittedRecipes(forceRefresh: true);
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Recipe page unavailable')),
                          );
                        }
                      }
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Submit Your First Recipe'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _submittedRecipes.length,
              itemBuilder: (context, index) {
                final recipe = _submittedRecipes[index];

                if (recipe.id == null) {
                  return const SizedBox.shrink();
                }

                return RecipeCard(
                  recipe: recipe,
                  onDelete: () => _deleteRecipe(recipe.id!),
                  onEdit: () => _editRecipe(recipe),
                  onRatingChanged: () =>
                      _loadSubmittedRecipes(forceRefresh: true),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.wallpaper),
            tooltip: 'Change Background',
            onPressed: _showBackgroundPickerDialog,
          ),
          if (_isLoading)
            const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
            ),
        ],
      ),
      drawer: const AppDrawer(currentPage: 'profile'),
      body: Stack(
        children: [
          Positioned.fill(
            child: _backgroundImageUrl != null
                ? Image.network(
                    _backgroundImageUrl!,
                    fit: BoxFit.fill, // 🔥 FIXED: Stretch to fill instead of cover
                    errorBuilder: (context, error, stackTrace) {
                      return Image.asset(
                        'assets/background.png',
                        fit: BoxFit.fill, // 🔥 FIXED: Consistent scaling
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            color: Colors.green.shade50,
                          );
                        },
                      );
                    },
                  )
                : Image.asset(
                    'assets/background.png',
                    fit: BoxFit.fill, // 🔥 FIXED: Consistent scaling
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        color: Colors.green.shade50,
                        child: const Center(
                          child: Icon(
                            Icons.image_not_supported,
                            size: 50,
                            color: Colors.grey,
                          ),
                        ),
                      );
                    },
                  ),
          ),
          RefreshIndicator(
            onRefresh: () async {
              await _invalidateRecipesCache();
              await _invalidatePicturesCache();
              await _invalidateFriendsCache();

              await Future.wait([
                _loadSubmittedRecipes(forceRefresh: true),
                _loadPictures(forceRefresh: true),
                _loadFriends(forceRefresh: true),
                _loadProfile(),
              ]);
            },
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Center(
                    child: Stack(
                      children: [
                        CircleAvatar(
                          radius: 80,
                          backgroundColor: Colors.grey[300],
                          backgroundImage: _profileImageUrl != null
                              ? NetworkImage(_profileImageUrl!)
                              : null,
                          child: _profileImageUrl == null
                              ? const Icon(
                                  Icons.person,
                                  size: 80,
                                  color: Colors.grey,
                                )
                              : null,
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: GestureDetector(
                            onTap: _showImagePickerDialog,
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: const BoxDecoration(
                                color: Colors.blue,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.camera_alt,
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 30),
                  _sectionContainer(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Username:',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (!_isEditingName)
                              TextButton.icon(
                                onPressed: _toggleEditName,
                                icon: const Icon(Icons.edit, size: 16),
                                label: const Text('Edit'),
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.blue,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        if (_isEditingName) ...[
                          TextField(
                            controller: _nameController,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              hintText: 'Enter your username',
                            ),
                            autofocus: true,
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              ElevatedButton(
                                onPressed: _isLoading ? null : _saveUserName,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue,
                                  foregroundColor: Colors.white,
                                ),
                                child: _isLoading
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                                  Colors.white),
                                        ),
                                      )
                                    : const Text('Save'),
                              ),
                              const SizedBox(width: 10),
                              TextButton(
                                onPressed: _cancelEditName,
                                child: const Text('Cancel'),
                              ),
                            ],
                          ),
                        ] else ...[
                          Text(
                            _userName.isEmpty ? 'No username set' : _userName,
                            style: const TextStyle(fontSize: 16),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  _sectionContainer(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Email:',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (!_isEditingEmail)
                              TextButton.icon(
                                onPressed: _toggleEditEmail,
                                icon: const Icon(Icons.edit, size: 16),
                                label: const Text('Edit'),
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.blue,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        if (_isEditingEmail) ...[
                          TextField(
                            controller: _emailController,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              hintText: 'Enter your email',
                            ),
                            keyboardType: TextInputType.emailAddress,
                            autofocus: true,
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              ElevatedButton(
                                onPressed: _isLoading ? null : _saveUserEmail,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue,
                                  foregroundColor: Colors.white,
                                ),
                                child: _isLoading
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                                  Colors.white),
                                        ),
                                      )
                                    : const Text('Save'),
                              ),
                              const SizedBox(width: 10),
                              TextButton(
                                onPressed: _cancelEditEmail,
                                child: const Text('Cancel'),
                              ),
                            ],
                          ),
                        ] else ...[
                          Text(
                            _userEmail.isEmpty ? 'No email set' : _userEmail,
                            style: const TextStyle(fontSize: 16),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  _buildPicturesSection(),
                  const SizedBox(height: 20),
                  _sectionContainer(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Friends (${_friends.length})',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert, size: 20),
                              onSelected: (value) {
                                if (value == 'toggle_visibility') {
                                  _toggleFriendsVisibility(!_friendsListVisible);
                                }
                              },
                              itemBuilder: (context) => [
                                PopupMenuItem(
                                  value: 'toggle_visibility',
                                  child: Row(
                                    children: [
                                      Icon(
                                        _friendsListVisible
                                            ? Icons.visibility_off
                                            : Icons.visibility,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(_friendsListVisible
                                          ? 'Hide from Others'
                                          : 'Make Visible'),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(
                              _friendsListVisible
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                              size: 16,
                              color: Colors.grey.shade600,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _friendsListVisible
                                  ? 'Visible to others'
                                  : 'Hidden from others',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        if (_isLoadingFriends) ...[
                          const Center(child: CircularProgressIndicator()),
                        ] else if (_friends.isEmpty) ...[
                          Text(
                            'No friends yet. Start by finding and adding friends!',
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton.icon(
                            onPressed: _navigateToSearchUsers,
                            icon: const Icon(Icons.person_search),
                            label: const Text('Find Friends'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ] else ...[
                          GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              childAspectRatio: 0.8,
                              crossAxisSpacing: 8,
                              mainAxisSpacing: 8,
                            ),
                            itemCount:
                                _friends.length > 6 ? 6 : _friends.length,
                            itemBuilder: (context, index) {
                              if (index == 5 && _friends.length > 6) {
                                return GestureDetector(
                                  onTap: _showFullFriendsList,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade100,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                          color: Colors.grey.shade300),
                                    ),
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.more_horiz,
                                            size: 30,
                                            color: Colors.grey.shade600),
                                        const SizedBox(height: 4),
                                        Text(
                                          'View All\n${_friends.length} friends',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }

                              final friend = _friends[index];
                              return GestureDetector(
                                onTap: () => _navigateToUserProfile(friend['id']),
                                child: Column(
                                  children: [
                                    CircleAvatar(
                                      radius: 25,
                                      backgroundImage:
                                          friend['avatar_url'] != null
                                              ? NetworkImage(
                                                  friend['avatar_url'],
                                                )
                                              : null,
                                      child: friend['avatar_url'] == null
                                          ? Text(
                                              (friend['username'] ??
                                                          friend['first_name'] ??
                                                          friend['email'] ??
                                                          'U')[0]
                                                  .toUpperCase(),
                                              style: const TextStyle(
                                                fontSize: 20,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            )
                                          : null,
                                    ),
                                    const SizedBox(height: 4),
                                    Expanded(
                                      child: Text(
                                        friend['first_name'] != null &&
                                                friend['last_name'] != null
                                            ? '${friend['first_name']} ${friend['last_name']}'
                                            : friend['username'] ?? 'Unknown',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                        ),
                                        textAlign: TextAlign.center,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                          if (_friends.length > 6) ...[
                            const SizedBox(height: 12),
                            TextButton(
                              onPressed: _showFullFriendsList,
                              child:
                                  Text('View All ${_friends.length} Friends'),
                            ),
                          ],
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  _buildPremiumStatusSection(),
                  const SizedBox(height: 20),
                  PremiumGate(
                    feature: PremiumFeature.submitRecipes,
                    featureName: 'Recipe Submission',
                    featureDescription:
                        'Share your favorite recipes with the community.',
                    child: _buildSubmittedRecipesSection(),
                  ),
                  const SizedBox(height: 20),
                  PremiumGate(
                    feature: PremiumFeature.favoriteRecipes,
                    featureName: 'Favorite Recipes',
                    featureDescription:
                        'Save and organize your favorite recipes.',
                    showSoftPreview: true,
                    child: _sectionContainer(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Favorite Recipes',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            widget.favoriteRecipes.isEmpty
                                ? 'No favorite recipes yet. Start scanning to discover new recipes!'
                                : '${widget.favoriteRecipes.length} favorite recipes saved',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          if (widget.favoriteRecipes.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  try {
                                    Navigator.pushNamed(
                                        context, '/favorite-recipes');
                                  } catch (e) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content: Text(
                                              'Favorites page unavailable')),
                                    );
                                  }
                                },
                                icon: const Icon(Icons.favorite),
                                label: const Text('View Favorite Recipes'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red,
                                  foregroundColor: Colors.white,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _sectionContainer(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Danger Zone',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.red.shade700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Permanently delete your account and all associated data. This action cannot be undone.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed:
                                _isLoading ? null : _confirmDeleteAccount,
                            icon: const Icon(Icons.delete_forever),
                            label: const Text('Delete My Account'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.red,
                              side: const BorderSide(color: Colors.red),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 100),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
