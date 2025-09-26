// main.dart - FIXED: Updated to use Environment system for security
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config/environment.dart'; // ADDED: Import environment system
import 'home_screen.dart';
import 'login.dart';
import 'pages/premium_page.dart';
import 'pages/grocery_list.dart';
import 'pages/submit_recipe.dart';
import 'pages/messages_page.dart';
import 'pages/search_users_page.dart';
import 'pages/profile_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    // ADDED: Initialize environment configuration first
    await Environment.initialize();
    
    // FIXED: Use environment variables instead of hardcoded keys
    await Supabase.initialize(
      url: Environment.supabaseUrl,
      anonKey: Environment.supabaseAnonKey,
    );

    if (Environment.enableDebugLogging) {
      print('✅ App initialization completed successfully');
      Environment.printConfig();
    }

    runApp(const MyApp());
    
  } catch (e) {
    // Handle initialization errors gracefully
    if (Environment.enableDebugLogging) {
      print('❌ App initialization failed: $e');
    }
    
    // Show error app if initialization fails
    runApp(MaterialApp(
      home: Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error, size: 64, color: Colors.red),
              SizedBox(height: 16),
              Text(
                'App Initialization Failed',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Please check your configuration and try again.\n\nError: $e',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ),
              SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  // Restart the app
                  main();
                },
                child: Text('Retry'),
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

  @override
  void initState() {
    super.initState();
    _checkPremiumStatus();
  }

  Future<void> _checkPremiumStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _isPremium = prefs.getBool('isPremiumUser') ?? false;
      });
    } catch (e) {
      if (Environment.enableDebugLogging) {
        print('Error checking premium status: $e');
      }
      // Default to free user if there's an error
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
      title: Environment.appName, // UPDATED: Use environment app name
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      // ENHANCED: Better initial route logic with error handling
      initialRoute: _getInitialRoute(supabase),
      routes: {
        '/login': (context) => const LoginPage(),
        '/home': (context) => HomePage(isPremium: _isPremium),
        '/profile': (context) => ProfileScreen(favoriteRecipes: []),
        '/purchase': (context) => const PremiumPage(),
        '/grocery-list': (context) => const GroceryListPage(),
        '/submit-recipe': (context) => const SubmitRecipePage(),
        '/messages': (context) => MessagesPage(),
        '/search-users': (context) => const SearchUsersPage(),
      },
      // ADDED: Error handling for unknown routes
      onUnknownRoute: (settings) {
        if (Environment.enableDebugLogging) {
          print('Unknown route: ${settings.name}');
        }
        return MaterialPageRoute(
          builder: (context) => Scaffold(
            appBar: AppBar(title: Text('Page Not Found')),
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'Page Not Found',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'The page "${settings.name}" does not exist.',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                  SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => Navigator.pushReplacementNamed(context, '/home'),
                    child: Text('Go Home'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// ADDED: Enhanced initial route logic with error handling
  String _getInitialRoute(SupabaseClient supabase) {
    try {
      // Check if user is authenticated
      final user = supabase.auth.currentUser;
      
      if (user != null) {
        if (Environment.enableDebugLogging) {
          print('User authenticated: ${user.email}');
        }
        return '/home';
      } else {
        if (Environment.enableDebugLogging) {
          print('No authenticated user, redirecting to login');
        }
        return '/login';
      }
    } catch (e) {
      if (Environment.enableDebugLogging) {
        print('Error determining initial route: $e');
      }
      // Default to login on any error
      return '/login';
    }
  }
}