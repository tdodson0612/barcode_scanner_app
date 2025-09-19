// lib/widgets/app_drawer.dart
import 'package:flutter/material.dart';
import '../controllers/premium_gate_controller.dart';
import '../services/auth_service.dart';

class AppDrawer extends StatelessWidget {
  final String currentPage;
  
  const AppDrawer({
    super.key,
    required this.currentPage,
  });

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
                    colors: [Colors.green, Colors.green.shade700],
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
              
              // Home (ALWAYS AVAILABLE)
              ListTile(
                leading: Icon(
                  Icons.home,
                  color: currentPage == 'home' ? Colors.green : null,
                ),
                title: Text(
                  'Home',
                  style: TextStyle(
                    fontWeight: currentPage == 'home' ? FontWeight.bold : FontWeight.normal,
                    color: currentPage == 'home' ? Colors.green : null,
                  ),
                ),
                selected: currentPage == 'home',
                onTap: () {
                  Navigator.pop(context);
                  if (currentPage != 'home') {
                    Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
                  }
                },
              ),
              
              // Profile (ALWAYS AVAILABLE)
              ListTile(
                leading: Icon(
                  Icons.person,
                  color: currentPage == 'profile' ? Colors.green : null,
                ),
                title: Text(
                  'Profile',
                  style: TextStyle(
                    fontWeight: currentPage == 'profile' ? FontWeight.bold : FontWeight.normal,
                    color: currentPage == 'profile' ? Colors.green : null,
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
              
              // Messages (ALWAYS AVAILABLE)
              ListTile(
                leading: Icon(
                  Icons.chat,
                  color: currentPage == 'messages' ? Colors.green : null,
                ),
                title: Text(
                  'Messages',
                  style: TextStyle(
                    fontWeight: currentPage == 'messages' ? FontWeight.bold : FontWeight.normal,
                    color: currentPage == 'messages' ? Colors.green : null,
                  ),
                ),
                selected: currentPage == 'messages',
                onTap: () {
                  Navigator.pop(context);
                  if (currentPage != 'messages') {
                    Navigator.pushNamed(context, '/messages');
                  }
                },
              ),
              
              // Find Friends (ALWAYS AVAILABLE)
              ListTile(
                leading: Icon(
                  Icons.person_search,
                  color: currentPage == 'find_friends' ? Colors.green : null,
                ),
                title: Text(
                  'Find Friends',
                  style: TextStyle(
                    fontWeight: currentPage == 'find_friends' ? FontWeight.bold : FontWeight.normal,
                    color: currentPage == 'find_friends' ? Colors.green : null,
                  ),
                ),
                selected: currentPage == 'find_friends',
                onTap: () {
                  Navigator.pop(context);
                  if (currentPage != 'find_friends') {
                    Navigator.pushNamed(context, '/search-users');
                  }
                },
              ),
              
              // Favorite Recipes (PREMIUM GATED)
              if (controller.isPremium) ...[
                ListTile(
                  leading: Icon(
                    Icons.favorite,
                    color: currentPage == 'favorite_recipes' ? Colors.green : null,
                  ),
                  title: Text(
                    'Favorite Recipes',
                    style: TextStyle(
                      fontWeight: currentPage == 'favorite_recipes' ? FontWeight.bold : FontWeight.normal,
                      color: currentPage == 'favorite_recipes' ? Colors.green : null,
                    ),
                  ),
                  selected: currentPage == 'favorite_recipes',
                  onTap: () {
                    Navigator.pop(context);
                    if (currentPage != 'favorite_recipes') {
                      Navigator.pushNamed(context, '/favorite-recipes');
                    }
                  },
                ),
                
                ListTile(
                  leading: Icon(Icons.shopping_cart),
                  title: Text('My Grocery List'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.pushNamed(context, '/grocery-list');
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
                    Navigator.pushNamed(context, '/purchase');
                  },
                ),
                
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
                    Navigator.pushNamed(context, '/purchase');
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
                    Navigator.pushNamed(context, '/purchase');
                  },
                ),
              ],
              
              Divider(),
              
              // Contact Us (ALWAYS AVAILABLE)
              ListTile(
                leading: Icon(
                  Icons.contact_mail,
                  color: currentPage == 'contact' ? Colors.green : null,
                ),
                title: Text(
                  'Contact Us',
                  style: TextStyle(
                    fontWeight: currentPage == 'contact' ? FontWeight.bold : FontWeight.normal,
                    color: currentPage == 'contact' ? Colors.green : null,
                  ),
                ),
                selected: currentPage == 'contact',
                onTap: () {
                  Navigator.pop(context);
                  if (currentPage != 'contact') {
                    Navigator.pushNamed(context, '/contact');
                  }
                },
              ),
              
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
                  Navigator.pushNamed(context, '/purchase');
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