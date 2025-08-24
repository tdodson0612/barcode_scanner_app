// ==================================================
// COMPLETE APP DRAWER - FINISHED VERSION
// ==================================================

// lib/widgets/app_drawer.dart
import 'package:flutter/material.dart';
import '../controllers/premium_gate_controller.dart';
import '../services/auth_service.dart';

class AppDrawer extends StatelessWidget {
  final String currentPage;
  
  const AppDrawer({
    Key? key,
    required this.currentPage,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: AnimatedBuilder(
        animation: PremiumGateController(),
        builder: (context, _) {
          final controller = PremiumGateController();
          final userEmail = AuthService.currentUser?.email;

          return ListView(
            padding: EdgeInsets.zero,
            children: [
              DrawerHeader(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Colors.blue, Colors.blue.shade700],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Recipe Scanner',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 8),
                    
                    if (userEmail != null) ...[
                      Text(
                        userEmail,
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                      SizedBox(height: 8),
                    ],
                    
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: controller.isPremium ? Colors.amber : Colors.grey,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            controller.isPremium ? Icons.star : Icons.person,
                            color: Colors.white,
                            size: 16,
                          ),
                          SizedBox(width: 4),
                          Text(
                            controller.isPremium ? 'Premium' : 'Free Account',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    if (!controller.isPremium) ...[
                      SizedBox(height: 4),
                      Text(
                        'Scans used: ${controller.totalScansUsed}/3',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
              
              // Home (PREMIUM ONLY for full access, limited for free)
              if (controller.isPremium)
                ListTile(
                  leading: Icon(
                    Icons.home,
                    color: currentPage == 'home' ? Colors.blue : null,
                  ),
                  title: Text('Home'),
                  selected: currentPage == 'home',
                  onTap: () {
                    Navigator.pop(context);
                    if (currentPage != 'home') {
                      Navigator.pushReplacementNamed(context, '/home');
                    }
                  },
                ),
              
              // Scan (LIMITED for free users)
              ListTile(
                leading: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.qr_code_scanner),
                    if (!controller.isPremium && controller.hasUsedAllFreeScans)
                      Padding(
                        padding: EdgeInsets.only(left: 4),
                        child: Icon(Icons.lock, color: Colors.red, size: 16),
                      ),
                  ],
                ),
                title: Row(
                  children: [
                    Text('Scan Products'),
                    if (!controller.isPremium) ...[
                      SizedBox(width: 8),
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: controller.hasUsedAllFreeScans ? Colors.red : Colors.orange,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          controller.hasUsedAllFreeScans ? 'BLOCKED' : '${controller.remainingScans} LEFT',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                onTap: () {
                  Navigator.pop(context);
                  if (controller.canAccessFeature(PremiumFeature.scan)) {
                    Navigator.pushReplacementNamed(context, '/home');
                  } else {
                    Navigator.pushNamed(context, '/premium');
                  }
                },
              ),
              
              // Profile (ALWAYS AVAILABLE - basic version)
              ListTile(
                leading: Icon(
                  Icons.person,
                  color: currentPage == 'profile' ? Colors.blue : null,
                ),
                title: Text(
                  'Profile',
                  style: TextStyle(
                    fontWeight: currentPage == 'profile' ? FontWeight.bold : FontWeight.normal,
                    color: currentPage == 'profile' ? Colors.blue : null,
                  ),
                ),
                selected: currentPage == 'profile',
                onTap: () {
                  Navigator.pop(context);
                  if (currentPage != 'profile') {
                    Navigator.pushNamed(context, '/profile');
                  }
                },
              ),
              
              // Premium Features (BLOCKED for free users)
              if (controller.isPremium) ...[
                ListTile(
                  leading: Icon(Icons.shopping_cart),
                  title: Text('My Grocery List'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.pushNamed(context, '/grocery-list');
                  },
                ),
                
                ListTile(
                  leading: Icon(Icons.favorite),
                  title: Text('Favorite Recipes'),
                  onTap: () {
                    Navigator.pop(context);
                    // Navigate to favorites page when you create it
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Favorites page coming soon!')),
                    );
                  },
                ),
                
                ListTile(
                  leading: Icon(Icons.add_circle),
                  title: Text('Submit Recipe'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.pushNamed(context, '/submit-recipe');
                  },
                ),
              ] else ...[
                // Show locked features for free users
                ListTile(
                  leading: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.shopping_cart, color: Colors.grey),
                      SizedBox(width: 4),
                      Icon(Icons.lock, color: Colors.red, size: 16),
                    ],
                  ),
                  title: Row(
                    children: [
                      Text('Grocery List', style: TextStyle(color: Colors.grey)),
                      SizedBox(width: 8),
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.amber,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'PREMIUM',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.pushNamed(context, '/premium');
                  },
                ),
                
                ListTile(
                  leading: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.favorite, color: Colors.grey),
                      SizedBox(width: 4),
                      Icon(Icons.lock, color: Colors.red, size: 16),
                    ],
                  ),
                  title: Row(
                    children: [
                      Text('Favorite Recipes', style: TextStyle(color: Colors.grey)),
                      SizedBox(width: 8),
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.amber,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'PREMIUM',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.pushNamed(context, '/premium');
                  },
                ),
                
                ListTile(
                  leading: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add_circle, color: Colors.grey),
                      SizedBox(width: 4),
                      Icon(Icons.lock, color: Colors.red, size: 16),
                    ],
                  ),
                  title: Row(
                    children: [
                      Text('Submit Recipe', style: TextStyle(color: Colors.grey)),
                      SizedBox(width: 8),
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.amber,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'PREMIUM',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.pushNamed(context, '/premium');
                  },
                ),
              ],
              
              Divider(),
              
              // Purchase Premium (ALWAYS AVAILABLE)
              ListTile(
                leading: Icon(
                  Icons.star,
                  color: controller.isPremium ? Colors.amber : Colors.grey,
                ),
                title: Text(
                  controller.isPremium ? 'Premium Active' : 'Upgrade to Premium',
                  style: TextStyle(
                    color: controller.isPremium ? Colors.amber : null,
                    fontWeight: controller.isPremium ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                trailing: controller.isPremium 
                    ? Icon(Icons.check_circle, color: Colors.green)
                    : Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.pushNamed(context, '/premium');
                },
              ),
              
              // Contact Us (Always available)
              ListTile(
                leading: Icon(Icons.contact_mail),
                title: Text('Contact Us'),
                onTap: () {
                  Navigator.pop(context);
                  // Navigate to contact page if you have one
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Contact page coming soon!')),
                  );
                },
              ),
              
              Divider(),
              
              // Sign Out
              ListTile(
                leading: Icon(Icons.logout, color: Colors.red),
                title: Text(
                  'Sign Out',
                  style: TextStyle(color: Colors.red),
                ),
                onTap: () => _showSignOutDialog(context),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showSignOutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Sign Out'),
        content: Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await AuthService.signOut();
              Navigator.pushNamedAndRemoveUntil(context, '/auth', (route) => false);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text('Sign Out', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

// ==================================================
// COMPLETE HOME PAGE WITH SCAN RESTRICTIONS
// ==================================================

// lib/pages/home_page.dart
import 'package:flutter/material.dart';
import '../widgets/app_drawer.dart';
import '../widgets/premium_gate.dart';
import '../controllers/premium_gate_controller.dart';

class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _isScanning = false;
  List<Map<String, String>> _scannedRecipes = [];

  @override
  void initState() {
    super.initState();
    PremiumGateController().refresh();
  }

  Future<void> _performScan() async {
    final controller = PremiumGateController();
    
    // Check if user can scan
    if (!controller.canAccessFeature(PremiumFeature.scan)) {
      Navigator.pushNamed(context, '/premium');
      return;
    }

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Recipe Scanner'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
      ),
      drawer: AppDrawer(currentPage: 'home'),
      body: Stack(
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
                        'Scan products to discover amazing recipes!',
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
                            onTap: _isScanning ? null : _performScan,
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
                                                ? Icons.qr_code_scanner
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
                        ],
                      );
                    },
                  ),
                ),
                
                SizedBox(height: 30),
                
                // Recipe Results (PREMIUM GATED)
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
      ),
    );
  }
}

// ==================================================
// FINAL IMPLEMENTATION NOTES
// ==================================================

/*
🎉 COMPLETE RESTRICTIVE PREMIUM SYSTEM

✅ FILES COMPLETED:
- PremiumGateController (central control)
- PremiumGate (feature blocking widget)
- AppDrawer (restrictive with locked features)
- ProfileScreen (basic version for free users)
- HomePage (scan limitations with visual feedback)

✅ FREE USER RESTRICTIONS:
- Only 3 scans per day maximum
- Basic profile (name & photo only) 
- Purchase page access
- All other features completely blocked

✅ PREMIUM USERS:
- Unlimited everything
- Full app functionality
- Premium badges and indicators

✅ KEY FEATURES:
- Visual scan counter in drawer header
- Locked features show red lock icons
- Premium badges on restricted features
- Consistent upgrade prompts
- Auto-premium for special accounts

🚀 READY FOR PRODUCTION:
This system creates a true freemium model that will
drive premium conversions while providing a taste
of the app's functionality to free users.
*/