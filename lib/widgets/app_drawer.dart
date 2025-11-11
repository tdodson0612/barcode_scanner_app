// lib/widgets/app_drawer.dart - FIXED: SafeArea to prevent Android nav bar overlap
import 'package:flutter/material.dart';
import '../controllers/premium_gate_controller.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';

class AppDrawer extends StatefulWidget {
  final String currentPage;
  
  const AppDrawer({
    super.key,
    required this.currentPage,
  });

  @override
  State<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends State<AppDrawer> {
  late final PremiumGateController _controller;
  int _unreadCount = 0;

  @override
  void initState() {
    super.initState();
    _controller = PremiumGateController();
    _controller.addListener(_onPremiumStateChanged);
    _loadUnreadCount();
  }

  @override
  void dispose() {
    _controller.removeListener(_onPremiumStateChanged);
    super.dispose();
  }

  void _onPremiumStateChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _loadUnreadCount() async {
    try {
      final count = await DatabaseService.getUnreadMessageCount();
      if (mounted) {
        setState(() => _unreadCount = count);
      }
    } catch (e) {
      print('Error loading unread count: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final userEmail = AuthService.currentUser?.email;

    return Drawer(
      // FIXED: Wrap entire drawer in SafeArea to prevent Android nav bar overlap
      child: SafeArea(
        // Only apply SafeArea to bottom (where nav bar appears)
        top: false, // Let drawer use full height at top
        child: ListView(
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
                    'Liver Food Scanner', // UPDATED from Group A
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
                      color: _controller.isPremium ? Colors.amber : Colors.grey,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _controller.isPremium ? Icons.star : Icons.person,
                          color: Colors.white,
                          size: 16,
                        ),
                        SizedBox(width: 4),
                        Text(
                          _controller.isPremium ? 'Premium' : 'Free Account',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  if (!_controller.isPremium) ...[
                    SizedBox(height: 4),
                    Text(
                      'Scans used: ${_controller.totalScansUsed}/3',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
            
            ListTile(
              leading: Icon(
                Icons.home,
                color: widget.currentPage == 'home' ? Colors.green : null,
              ),
              title: Text(
                'Home',
                style: TextStyle(
                  fontWeight: widget.currentPage == 'home' ? FontWeight.bold : FontWeight.normal,
                  color: widget.currentPage == 'home' ? Colors.green : null,
                ),
              ),
              selected: widget.currentPage == 'home',
              onTap: () {
                Navigator.pop(context);
                if (widget.currentPage != 'home') {
                  Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
                }
              },
            ),
            
            // ADD THIS TO YOUR AppDrawer widget (lib/widgets/app_drawer.dart)
            // Add it right after the Home menu item:

            ListTile(
              leading: Icon(
                Icons.explore,
                color: widget.currentPage == 'feed' ? Colors.green : Colors.grey[700],
              ),
              title: Text(
                'Discovery Feed',
                style: TextStyle(
                  color: widget.currentPage == 'feed' ? Colors.green : Colors.black,
                  fontWeight: widget.currentPage == 'feed' ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              selected: widget.currentPage == 'feed',
              selectedTileColor: Colors.green.withOpacity(0.1),
              onTap: () {
                Navigator.pop(context);
                if (widget.currentPage != 'feed') {
                  Navigator.pushReplacementNamed(context, '/feed');
                }
              },
            ),



            ListTile(
              leading: Icon(
                Icons.person,
                color: widget.currentPage == 'profile' ? Colors.green : null,
              ),
              title: Text(
                'Profile',
                style: TextStyle(
                  fontWeight: widget.currentPage == 'profile' ? FontWeight.bold : FontWeight.normal,
                  color: widget.currentPage == 'profile' ? Colors.green : null,
                ),
              ),
              selected: widget.currentPage == 'profile',
              onTap: () {
                Navigator.pop(context);
                if (widget.currentPage != 'profile') {
                  Navigator.pushNamed(context, '/profile');
                }
              },
            ),
            
            // Messages with badge
            ListTile(
              leading: Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(
                    Icons.chat,
                    color: widget.currentPage == 'messages' ? Colors.green : null,
                  ),
                  if (_unreadCount > 0)
                    Positioned(
                      right: -8,
                      top: -4,
                      child: Container(
                        padding: EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        constraints: BoxConstraints(
                          minWidth: 18,
                          minHeight: 18,
                        ),
                        child: Text(
                          _unreadCount > 99 ? '99+' : '$_unreadCount',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
              title: Text(
                'Messages',
                style: TextStyle(
                  fontWeight: widget.currentPage == 'messages' ? FontWeight.bold : FontWeight.normal,
                  color: widget.currentPage == 'messages' ? Colors.green : null,
                ),
              ),
              trailing: _unreadCount > 0
                  ? Container(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _unreadCount > 99 ? '99+' : '$_unreadCount',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    )
                  : null,
              selected: widget.currentPage == 'messages',
              onTap: () {
                Navigator.pop(context);
                if (widget.currentPage != 'messages') {
                  Navigator.pushNamed(context, '/messages');
                }
              },
            ),
            
            ListTile(
              leading: Icon(
                Icons.person_search,
                color: widget.currentPage == 'find_friends' ? Colors.green : null,
              ),
              title: Text(
                'Find Friends',
                style: TextStyle(
                  fontWeight: widget.currentPage == 'find_friends' ? FontWeight.bold : FontWeight.normal,
                  color: widget.currentPage == 'find_friends' ? Colors.green : null,
                ),
              ),
              selected: widget.currentPage == 'find_friends',
              onTap: () {
                Navigator.pop(context);
                if (widget.currentPage != 'find_friends') {
                  Navigator.pushNamed(context, '/messages');
                }
              },
            ),
            
            if (_controller.isPremium) ...[
              ListTile(
                leading: Icon(
                  Icons.favorite,
                  color: widget.currentPage == 'favorite_recipes' ? Colors.green : null,
                ),
                title: Text(
                  'Favorite Recipes',
                  style: TextStyle(
                    fontWeight: widget.currentPage == 'favorite_recipes' ? FontWeight.bold : FontWeight.normal,
                    color: widget.currentPage == 'favorite_recipes' ? Colors.green : null,
                  ),
                ),
                selected: widget.currentPage == 'favorite_recipes',
                onTap: () {
                  Navigator.pop(context);
                  if (widget.currentPage != 'favorite_recipes') {
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
            
            ListTile(
              leading: Icon(
                Icons.contact_mail,
                color: widget.currentPage == 'contact' ? Colors.green : null,
              ),
              title: Text(
                'Contact Us',
                style: TextStyle(
                  fontWeight: widget.currentPage == 'contact' ? FontWeight.bold : FontWeight.normal,
                  color: widget.currentPage == 'contact' ? Colors.green : null,
                ),
              ),
              selected: widget.currentPage == 'contact',
              onTap: () {
                Navigator.pop(context);
                if (widget.currentPage != 'contact') {
                  Navigator.pushNamed(context, '/contact');
                }
              },
            ),
            
            ListTile(
              leading: Icon(
                Icons.star,
                color: _controller.isPremium ? Colors.amber : Colors.grey,
              ),
              title: Text(
                _controller.isPremium ? 'Premium Active' : 'Upgrade to Premium',
                style: TextStyle(
                  color: _controller.isPremium ? Colors.amber : null,
                  fontWeight: _controller.isPremium ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              trailing: _controller.isPremium 
                  ? Icon(Icons.check_circle, color: Colors.green)
                  : Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, '/purchase');
              },
            ),
            
            Divider(),
            
            // FIXED: Sign Out button now has proper padding from bottom nav bar
            ListTile(
              leading: Icon(Icons.logout, color: Colors.red),
              title: Text(
                'Sign Out',
                style: TextStyle(color: Colors.red),
              ),
              onTap: () => _showSignOutDialog(context),
            ),
            
            // OPTIONAL: Add extra padding at bottom for visual spacing
            SizedBox(height: 8),
          ],
        ),
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
              Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text('Sign Out', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}