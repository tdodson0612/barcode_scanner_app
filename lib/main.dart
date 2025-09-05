import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'home_screen.dart';
import 'login.dart';
import 'pages/premium_page.dart';
import 'pages/grocery_list.dart';
import 'pages/submit_recipe.dart';
// ADD THESE NEW IMPORTS FOR SOCIAL FEATURES:
import 'pages/messages_page.dart';
import 'pages/search_users_page.dart';
import 'pages/chat_page.dart';
import 'pages/user_profile_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: 'https://jmnwyzearnndhlitruyu.supabase.co',
    anonKey: 'sb_publishable_l8QycOjdSgpUwI0vJBkHLw_Zxflwo_w',
  );

  runApp(const MyApp());
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
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isPremium = prefs.getBool('isPremiumUser') ?? false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final supabase = Supabase.instance.client;

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'LiverWise',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      initialRoute: supabase.auth.currentUser != null ? '/home' : '/login',
      routes: {
        '/login': (context) => const LoginPage(),
        '/home': (context) => HomePage(isPremium: _isPremium),
        '/purchase': (context) => const PremiumPage(),
        '/grocery-list': (context) => const GroceryListPage(),
        '/submit-recipe': (context) => const SubmitRecipePage(),
        // ADD THESE NEW ROUTES FOR SOCIAL FEATURES:
        '/messages': (context) => MessagesPage(),
        '/search-users': (context) => const SearchUsersPage(),
      },
    );
  }
}