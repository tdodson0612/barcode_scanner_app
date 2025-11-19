// main.dart – Unified version with Supabase, App Links (MainNavigation removed)

import 'package:flutter/material.dart';
import 'package:app_links/app_links.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config/app_config.dart';

// Screens and Pages
import 'login.dart';
import 'pages/premium_page.dart';
import 'pages/grocery_list.dart';
import 'pages/submit_recipe.dart';
import 'pages/messages_page.dart';
import 'pages/search_users_page.dart';
import 'pages/profile_screen.dart';
import 'pages/favorite_recipes_page.dart';
import 'models/favorite_recipe.dart';
import 'contact_screen.dart';
// import 'pages/discovery_feed_page.dart';  // ✅ Commented out
// import 'pages/create_post_page.dart';     // ✅ Commented out
import 'home_screen.dart';
// import 'pages/main_navigation.dart';      // ✅ Commented out

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      anonKey: AppConfig.supabaseAnonKey,
    );

    if (AppConfig.enableDebugPrints) {
      AppConfig.debugPrint('✅ App initialization completed successfully');
      AppConfig.debugPrint('Supabase URL: ${AppConfig.supabaseUrl}');
      AppConfig.debugPrint('App Name: ${AppConfig.appName}');
    }

    runApp(const MyApp());
  } catch (e) {
    if (AppConfig.enableDebugPrints) {
      print('❌ App initialization failed: $e');
    }

    runApp(MaterialApp(
      home: Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              const Text(
                'App Initialization Failed',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Please check your configuration and try again.\n\nError: $e',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  main();
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    ));
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool _isPremium = false;
  late final AppLinks _appLinks;

  @override
  void initState() {
    super.initState();
    _checkPremiumStatus();
    _initAppLinks();
  }

  Future<void> _initAppLinks() async {
    _appLinks = AppLinks();

    // Handle deep links when app is already running
    _appLinks.uriLinkStream.listen((Uri? uri) async {
      if (uri != null && uri.toString().contains('reset-password')) {
        await _handleResetPasswordLink(uri);
      }
    });

    // Handle deep links when app is launched by link (cold start)
    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null && initialUri.toString().contains('reset-password')) {
        await _handleResetPasswordLink(initialUri);
      }
    } catch (e) {
      if (AppConfig.enableDebugPrints) {
        AppConfig.debugPrint('Failed to handle initial deep link: $e');
      }
    }
  }

  Future<void> _handleResetPasswordLink(Uri uri) async {
    try {
      final response = await Supabase.instance.client.auth.getSessionFromUrl(uri);
      final session = response.session;

      if (mounted) {
        Navigator.pushNamed(context, '/reset-password', arguments: session);
      } else {
        if (AppConfig.enableDebugPrints) {
          AppConfig.debugPrint('⚠️ No valid session found in reset-password link.');
        }
      }
    } catch (e) {
      if (AppConfig.enableDebugPrints) {
        AppConfig.debugPrint('❌ Error handling reset-password link: $e');
      }
    }
  }

  Future<void> _checkPremiumStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      print("USER ID = ${Supabase.instance.client.auth.currentUser?.id}");

      setState(() {
        _isPremium = prefs.getBool('isPremiumUser') ?? false;
      });
    } catch (e) {
      if (AppConfig.enableDebugPrints) {
        AppConfig.debugPrint('Error checking premium status: $e');
      }
      setState(() {
        _isPremium = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final supabase = Supabase.instance.client;

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: AppConfig.appName,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      initialRoute: _getInitialRoute(supabase),
      routes: {
        '/login': (context) => const LoginPage(),
        '/home': (context) => const HomePage(),
        '/profile': (context) => ProfileScreen(favoriteRecipes: const []),
        '/purchase': (context) => const PremiumPage(),
        '/grocery-list': (context) => const GroceryListPage(),
        '/submit-recipe': (context) => const SubmitRecipePage(),
        '/messages': (context) => MessagesPage(),
        '/search-users': (context) => const SearchUsersPage(),
        '/favorite-recipes': (context) => FavoriteRecipesPage(favoriteRecipes: const []),
        '/contact': (context) => const ContactScreen(),
        // ✅ Feed and Create Post routes commented out since pages are not implemented yet
        // '/create-post': (context) => const CreatePostPage(),
        // '/feed': (context) => const DiscoveryFeedPage(),
      },
      onUnknownRoute: (settings) {
        if (AppConfig.enableDebugPrints) {
          AppConfig.debugPrint('Unknown route: ${settings.name}');
        }
        return MaterialPageRoute(
          builder: (context) => Scaffold(
            appBar: AppBar(title: const Text('Page Not Found')),
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text(
                    'Page Not Found',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'The page "${settings.name}" does not exist.',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => Navigator.pushReplacementNamed(context, '/home'),
                    child: const Text('Go Home'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _getInitialRoute(SupabaseClient supabase) {
    try {
      final user = supabase.auth.currentUser;

      if (user != null) {
        if (AppConfig.enableDebugPrints) {
          AppConfig.debugPrint('User authenticated: ${user.email}');
        }
        return '/home';
      } else {
        if (AppConfig.enableDebugPrints) {
          AppConfig.debugPrint('No authenticated user, redirecting to login');
        }
        return '/login';
      }
    } catch (e) {
      if (AppConfig.enableDebugPrints) {
        AppConfig.debugPrint('Error determining initial route: $e');
      }
      return '/login';
    }
  }
}
