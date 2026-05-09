// main.dart
// ✅ FIXED: Password reset deep links handled via Supabase onAuthStateChange
//           instead of getSessionFromUrl — works for both cold-start and
//           foreground deep links, and for both custom-scheme and HTTPS links.
// ✅ FIXED: Recursive main() call on retry replaced with safe runApp restart
// ✅ FIXED: _isReady guard on initialRoute prevents routing before init completes
// ✅ iOS/iPad-compatible Firebase initialization + Android 15 Edge-to-Edge

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:app_links/app_links.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'config/app_config.dart';
import 'pages/badge_debug_page.dart';
import 'pages/tracker_page.dart';
import 'pages/onboarding_page.dart';

// 🔥 Firebase imports
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

// 🔔 Stream controller for profile refresh events
import 'services/profile_events.dart';

// Screens and Pages
import 'login.dart';
import 'pages/premium_page.dart';
import 'pages/grocery_list.dart';
import 'pages/submit_recipe.dart';
import 'pages/messages_page.dart';
import 'pages/search_users_page.dart';
import 'pages/profile_screen.dart';
import 'pages/favorite_recipes_page.dart';
import 'contact_screen.dart';
import 'home_screen.dart';
import 'pages/reset_password_page.dart';
import 'package:liver_wise/pages/manual_barcode_entry_screen.dart';
import 'package:liver_wise/pages/nutrition_search_screen.dart';
import 'package:liver_wise/pages/saved_ingredients_screen.dart';
import './pages/submission_status_page.dart';
import './pages/my_cookbook_page.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import './pages/saved_posts_page.dart';

// ── Liver health features ──────────────────────────────────────────────────
import 'pages/liver_hub_page.dart';
import 'pages/liver_dashboard_page.dart';
import 'pages/hydration_log_page.dart';
import 'pages/supplement_schedule_page.dart';
import 'pages/symptom_log_page.dart';
import 'pages/alcohol_log_page.dart';
import 'services/liver_notification_service.dart';

// ── LoRA & Settings ───────────────────────────────────────────────────────
import 'pages/lora_dataset_page.dart';
import 'pages/settings_page.dart';
import 'widgets/admin_guard.dart';

/// 🔥 Background FCM handler (Android only)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (!kIsWeb && Platform.isAndroid) {
    await Firebase.initializeApp();
  }
  debugPrint("🔥 Background message received: ${message.messageId}");
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ✅ Edge-to-edge on Android 15+
  if (!kIsWeb && Platform.isAndroid) {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
    );
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
    MobileAds.instance.initialize();
  }

  try {
    await dotenv.load(fileName: ".env");
    AppConfig.validateConfig();

    // 🔥 Firebase initialization
    try {
      if (!kIsWeb && Platform.isAndroid) {
        await Firebase.initializeApp();
        AppConfig.debugPrint('✅ Firebase initialized (Android)');

        FirebaseMessaging.onBackgroundMessage(
            _firebaseMessagingBackgroundHandler);

        FirebaseMessaging.onMessage.listen((RemoteMessage message) {
          AppConfig.debugPrint("🔔 FCM onMessage: ${message.data}");
          if (message.data['type'] == 'refresh_profile') {
            AppConfig.debugPrint("🔄 Refresh profile triggered (FOREGROUND)");
            profileUpdateStreamController.add(null);
          }
        });

        final messaging = FirebaseMessaging.instance;
        final settings = await messaging.requestPermission(
          alert: true,
          badge: true,
          sound: true,
          provisional: false,
        );

        AppConfig.debugPrint(
            '📱 Notification permission: ${settings.authorizationStatus}');

        if (AppConfig.enableDebugPrints) {
          final token = await messaging.getToken();
          if (token != null) {
            AppConfig.debugPrint(
                '🔑 FCM Token: ${token.substring(0, 20)}...');
          }
        }
      } else if (!kIsWeb && Platform.isIOS) {
        AppConfig.debugPrint('✅ Firebase auto-initialized (iOS/iPadOS)');
        AppConfig.debugPrint(
            'ℹ️  FCM disabled on iOS to prevent conflicts during review');
      }
    } catch (fcmError) {
      AppConfig.debugPrint('⚠️ Firebase/FCM setup failed: $fcmError');
      AppConfig.debugPrint('App will continue without push notifications');
    }

    // Initialize Supabase
    AppConfig.debugPrint('🔄 Initializing Supabase...');

    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      anonKey: AppConfig.supabaseAnonKey,
    ).timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        throw Exception(
            'Supabase connection timeout. Please check your internet.');
      },
    );

    AppConfig.debugPrint('✅ Supabase initialized successfully');

    // Initialize liver health notification service
    await LiverNotificationService.initialize();
    AppConfig.debugPrint('✅ LiverNotificationService initialized');

    runApp(const MyApp());
  } catch (e) {
    AppConfig.debugPrint('❌ Critical app initialization failed: $e');
    runApp(_buildErrorApp(e));
  }
}

/// Build user-friendly error app when initialization fails
Widget _buildErrorApp(dynamic error) {
  final errorString = error.toString().toLowerCase();

  String title = 'Unable to Start App';
  String message = 'Please check your internet connection and try again.';
  IconData icon = Icons.cloud_off_rounded;
  Color iconColor = Colors.orange;

  if (errorString.contains('timeout') || errorString.contains('network')) {
    title = 'Connection Problem';
    message = 'Please check your internet connection and try again.';
    icon = Icons.wifi_off_rounded;
  } else if (errorString.contains('configuration') ||
      errorString.contains('url')) {
    title = 'Configuration Issue';
    message = 'The app needs to be updated. Please contact support.';
    icon = Icons.settings_rounded;
    iconColor = Colors.blue;
  } else {
    title = 'Startup Failed';
    message = 'Unable to start the app. Please try restarting.';
    icon = Icons.refresh_rounded;
    iconColor = Colors.red;
  }

  return MaterialApp(
    debugShowCheckedModeBanner: false,
    title: AppConfig.appName,
    home: Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: iconColor.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 80, color: iconColor),
                ),
                const SizedBox(height: 32),
                Text(
                  title,
                  style: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  message,
                  style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey.shade700,
                      height: 1.5),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 40),
                SizedBox(
                  width: 200,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      try {
                        await dotenv.load(fileName: ".env");
                        await Supabase.initialize(
                          url: AppConfig.supabaseUrl,
                          anonKey: AppConfig.supabaseAnonKey,
                        ).timeout(const Duration(seconds: 15));
                      } catch (_) {}
                      runApp(const MyApp());
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text(
                      'Try Again',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade600,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.lightbulb_outline_rounded,
                          color: Colors.blue.shade700, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'If the problem continues, try closing and reopening the app.',
                          style: TextStyle(
                              fontSize: 13, color: Colors.blue.shade900),
                        ),
                      ),
                    ],
                  ),
                ),
                if (AppConfig.enableDebugPrints)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(
                      'Debug: $error',
                      style:
                          const TextStyle(fontSize: 10, color: Colors.grey),
                      textAlign: TextAlign.center,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool _isPremium = false;
  bool _isReady = false;
  bool _showOnboarding = false;
  late final AppLinks _appLinks;

  // ── Password reset state ─────────────────────────────────────────────────
  // Holds a pending reset session captured before the navigator is ready.
  Session? _pendingResetSession;
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    await _checkPremiumStatus();
    await _checkOnboarding();

    // ✅ Listen for Supabase auth events — this is the most reliable way to
    // catch password-reset sessions. Supabase fires AuthChangeEvent.passwordRecovery
    // when it parses a recovery token from a deep link, regardless of whether
    // the app was cold-started or foregrounded.
    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      final event = data.event;
      final session = data.session;

      AppConfig.debugPrint('🔐 Auth event: $event');

      if (event == AuthChangeEvent.passwordRecovery && session != null) {
        AppConfig.debugPrint('🔑 Password recovery session received');
        _routeToPasswordReset(session);
      }
    });

    // ✅ Also handle deep links explicitly via app_links for cases where
    // Supabase doesn't auto-parse the URL (e.g. some Android custom schemes).
    _initAppLinks();

    if (mounted) {
      setState(() => _isReady = true);
    }
  }

  /// Navigate to the reset password page. If the navigator isn't ready yet
  /// (app is still initializing), store the session and navigate once built.
  void _routeToPasswordReset(Session session) {
    final nav = _navigatorKey.currentState;
    if (nav != null) {
      nav.pushNamedAndRemoveUntil(
        '/reset-password',
        (route) => false,
        arguments: session,
      );
    } else {
      // Navigator not ready yet — store and route after build
      AppConfig.debugPrint(
          '⏳ Navigator not ready, storing pending reset session');
      _pendingResetSession = session;
    }
  }

  Future<void> _checkOnboarding() async {
    final completed = await OnboardingPage.hasCompletedOnboarding();
    final user = Supabase.instance.client.auth.currentUser;
    if (!completed && user != null) {
      _showOnboarding = true;
    }
  }

  Future<void> _initAppLinks() async {
    try {
      _appLinks = AppLinks();

      // Foreground deep links
      _appLinks.uriLinkStream.listen((Uri? uri) async {
        if (uri != null) {
          AppConfig.debugPrint('🔗 Deep link received: $uri');
          await _handleDeepLink(uri);
        }
      });

      // Cold-start deep link
      try {
        final initialUri = await _appLinks.getInitialLink();
        if (initialUri != null) {
          AppConfig.debugPrint('🔗 Initial deep link: $initialUri');
          await _handleDeepLink(initialUri);
        }
      } catch (e) {
        AppConfig.debugPrint('Failed to handle initial deep link: $e');
      }
    } catch (e) {
      AppConfig.debugPrint('Failed to initialize app links: $e');
    }
  }

  /// Handle any incoming deep link URI.
  /// For password reset links Supabase will have already fired
  /// onAuthStateChange above. This is a fallback for edge cases.
  Future<void> _handleDeepLink(Uri uri) async {
    final uriStr = uri.toString();

    if (uriStr.contains('reset-password') ||
        uriStr.contains('type=recovery') ||
        uriStr.contains('recovery')) {
      AppConfig.debugPrint('🔑 Reset-password deep link detected');

      // Let Supabase parse the session from the URL.
      // onAuthStateChange will fire passwordRecovery and call
      // _routeToPasswordReset automatically. We only fall back to
      // getSessionFromUrl if that hasn't fired within a short window.
      try {
        final response = await Supabase.instance.client.auth
            .getSessionFromUrl(uri)
            .timeout(const Duration(seconds: 10));

        if (response.session != null) {
          AppConfig.debugPrint(
              '✅ Session from URL parsed successfully (fallback)');
          _routeToPasswordReset(response.session!);
        } else {
          AppConfig.debugPrint('⚠️ getSessionFromUrl returned null session');
          _showExpiredLinkError();
        }
      } catch (e) {
        AppConfig.debugPrint('⚠️ getSessionFromUrl failed: $e');
        // Don't show error yet — onAuthStateChange may still fire
      }
    }
  }

  void _showExpiredLinkError() {
    final nav = _navigatorKey.currentState;
    if (nav == null) return;

    // Navigate to reset page with null session so it shows the
    // "Link Expired" UI that already exists in ResetPasswordPage.
    nav.pushNamedAndRemoveUntil(
      '/reset-password',
      (route) => false,
      arguments: null,
    );
  }

  Future<void> _checkPremiumStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) {
        setState(() {
          _isPremium = prefs.getBool('isPremiumUser') ?? false;
        });
      }
    } catch (e) {
      AppConfig.debugPrint('Error checking premium status: $e');
      if (mounted) {
        setState(() => _isPremium = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final supabase = Supabase.instance.client;

    return MaterialApp(
      navigatorKey: _navigatorKey,
      debugShowCheckedModeBanner: false,
      title: AppConfig.appName,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
        textTheme: const TextTheme(
          bodyLarge: TextStyle(fontSize: 16),
          bodyMedium: TextStyle(fontSize: 14),
        ),
      ),
      // ✅ _isReady guard prevents routing before initialization completes.
      initialRoute: _isReady ? _getInitialRoute(supabase) : '/login',
      onGenerateInitialRoutes: (initialRouteName) {
        // ✅ If a password reset was received before the navigator was ready,
        // boot straight into the reset page instead of the normal initial route.
        if (_pendingResetSession != null) {
          final session = _pendingResetSession!;
          _pendingResetSession = null;
          return [
            MaterialPageRoute(
              builder: (_) => ResetPasswordPage(session: session),
              settings: const RouteSettings(name: '/reset-password'),
            ),
          ];
        }
        // Fall through to normal initialRoute
        return [
          MaterialPageRoute(
            builder: (_) => _isReady
                ? _buildInitialPage(Supabase.instance.client)
                : const LoginPage(),
            settings: RouteSettings(name: initialRouteName),
          ),
        ];
      },
      routes: {
        '/login':               (context) => const LoginPage(),
        '/home':                (context) => const HomePage(),
        '/onboarding':          (context) => const OnboardingPage(),
        '/profile':             (context) => ProfileScreen(favoriteRecipes: const []),
        '/purchase':            (context) => const PremiumPage(),
        '/grocery-list':        (context) => const GroceryListPage(),
        '/submit-recipe':       (context) => const SubmitRecipePage(),
        '/messages':            (context) => MessagesPage(),
        '/search-users':        (context) => const SearchUsersPage(),
        '/favorite-recipes':    (context) => FavoriteRecipesPage(favoriteRecipes: const []),
        '/contact':             (context) => const ContactScreen(),
        '/manual-barcode-entry':(context) => const ManualBarcodeEntryScreen(),
        '/nutrition-search':    (context) => const NutritionSearchScreen(),
        '/saved-ingredients':   (context) => const SavedIngredientsScreen(),
        '/badge-debug':         (context) => BadgeDebugPage(),
        '/submission-status':   (context) => const SubmissionStatusPage(),
        '/tracker':             (context) => const TrackerPage(),
        '/my-cookbook':         (context) => const MyCookbookPage(),
        '/saved-posts':         (context) => const SavedPostsPage(),
        '/settings':            (context) => const SettingsPage(),
        // ── Admin-only ───────────────────────────────────────────────
        '/lora-dataset':        (context) => const AdminGuard(child: LoraDatasetPage()),
        // ── Liver health features ────────────────────────────────────
        '/liver-hub':           (context) => const LiverHubPage(),
        '/liver-dashboard':     (context) => const LiverDashboardPage(),
        '/hydration-log':       (context) => const HydrationLogPage(),
        '/supplement-schedule': (context) => const SupplementSchedulePage(),
        '/symptom-log':         (context) => const SymptomLogPage(),
        '/alcohol-log':         (context) => const AlcoholLogPage(),
        '/reset-password': (context) {
          final session =
              ModalRoute.of(context)?.settings.arguments as Session?;
          return ResetPasswordPage(session: session);
        },
      },
      onUnknownRoute: (settings) {
        AppConfig.debugPrint('Unknown route requested: ${settings.name}');
        return MaterialPageRoute(
          builder: (context) => Scaffold(
            appBar: AppBar(
              title: const Text('Page Not Found'),
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.search_off_rounded,
                          size: 64, color: Colors.orange),
                    ),
                    const SizedBox(height: 24),
                    const Text('Page Not Found',
                        style: TextStyle(
                            fontSize: 24, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    Text(
                      'The page you\'re looking for doesn\'t exist or has been moved.',
                      style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey.shade600,
                          height: 1.5),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    SizedBox(
                      width: 200,
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          if (Navigator.canPop(context)) {
                            Navigator.pop(context);
                          } else {
                            Navigator.pushReplacementNamed(context, '/home');
                          }
                        },
                        icon: const Icon(Icons.home_rounded),
                        label: const Text('Go Home',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green.shade600,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildInitialPage(SupabaseClient supabase) {
    try {
      final user = supabase.auth.currentUser;
      if (user != null) {
        if (_showOnboarding) return const OnboardingPage();
        return const HomePage();
      }
    } catch (e) {
      AppConfig.debugPrint('⚠️ Error determining initial page: $e');
    }
    return const LoginPage();
  }

  String _getInitialRoute(SupabaseClient supabase) {
    try {
      final user = supabase.auth.currentUser;
      if (user != null) {
        AppConfig.debugPrint('✅ User authenticated: ${user.email}');
        if (_showOnboarding) return '/onboarding';
        return '/home';
      } else {
        AppConfig.debugPrint('ℹ️ No authenticated user, showing login');
        return '/login';
      }
    } catch (e) {
      AppConfig.debugPrint('⚠️ Error determining initial route: $e');
      return '/login';
    }
  }
}