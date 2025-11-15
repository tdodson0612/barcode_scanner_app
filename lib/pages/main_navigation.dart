// // lib/pages/main_navigation.dart - Main navigation wrapper with bottom bar
// import 'package:flutter/material.dart';
// import '../home_screen.dart';
// // import 'discovery_feed_page.dart'; // COMMENTED OUT - Feed feature removed
// // import 'create_post_page.dart'; // COMMENTED OUT - Post creation feature removed
// import 'profile_screen.dart';
// import 'messages_page.dart';

// class MainNavigation extends StatefulWidget {
//   final bool isPremium;
  
//   const MainNavigation({
//     super.key,
//     this.isPremium = false,
//   });

//   @override
//   State<MainNavigation> createState() => _MainNavigationState();
// }

// class _MainNavigationState extends State<MainNavigation> {
//   int _currentIndex = 0;
//   late List<Widget> _pages;

//   @override
//   void initState() {
//     super.initState();
//     _pages = [
//       HomePage(isPremium: widget.isPremium),
//       // const DiscoveryFeedPage(), // COMMENTED OUT - Feed feature removed
//       const Placeholder(), // Placeholder for future feature
//       // const Placeholder(), // COMMENTED OUT - Was create post placeholder
//       MessagesPage(),
//       ProfileScreen(favoriteRecipes: const []),
//     ];
//   }

//   void _onTabTapped(int index) {
//     // COMMENTED OUT - Create Post functionality removed
//     // // Handle middle button (Create Post) separately
//     // if (index == 2) {
//     //   Navigator.push(
//     //     context,
//     //     MaterialPageRoute(
//     //       builder: (context) => const CreatePostPage(),
//     //     ),
//     //   ).then((result) {
//     //     // If post was created, refresh feed
//     //     if (result == true && _currentIndex == 1) {
//     //       setState(() {
//     //         // Trigger rebuild of feed page
//     //         _pages[1] = const DiscoveryFeedPage();
//     //       });
//     //     }
//     //   });
//     //   return;
//     // }

//     setState(() {
//       _currentIndex = index;
//     });
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       body: IndexedStack(
//         index: _currentIndex, // UPDATED - Removed create post special handling
//         children: _pages,
//       ),
//       bottomNavigationBar: Container(
//         decoration: BoxDecoration(
//           boxShadow: [
//             BoxShadow(
//               color: Colors.black.withOpacity(0.1),
//               blurRadius: 10,
//               offset: const Offset(0, -5),
//             ),
//           ],
//         ),
//         child: BottomNavigationBar(
//           currentIndex: _currentIndex, // UPDATED - Removed create post special handling
//           onTap: _onTabTapped,
//           type: BottomNavigationBarType.fixed,
//           backgroundColor: Colors.white,
//           selectedItemColor: Colors.green,
//           unselectedItemColor: Colors.grey,
//           selectedFontSize: 12,
//           unselectedFontSize: 12,
//           items: [
//             const BottomNavigationBarItem(
//               icon: Icon(Icons.home),
//               activeIcon: Icon(Icons.home, size: 28),
//               label: 'Home',
//             ),
//             // COMMENTED OUT - Feed tab removed
//             // const BottomNavigationBarItem(
//             //   icon: Icon(Icons.explore),
//             //   activeIcon: Icon(Icons.explore, size: 28),
//             //   label: 'Feed',
//             // ),
//             const BottomNavigationBarItem(
//               icon: Icon(Icons.info), // Placeholder icon
//               activeIcon: Icon(Icons.info, size: 28),
//               label: 'Info', // Placeholder for future feature
//             ),
//             // COMMENTED OUT - Create Post tab removed
//             // BottomNavigationBarItem(
//             //   icon: Container(
//             //     padding: const EdgeInsets.all(8),
//             //     decoration: BoxDecoration(
//             //       color: Colors.green,
//             //       shape: BoxShape.circle,
//             //     ),
//             //     child: const Icon(Icons.add, color: Colors.white, size: 24),
//             //   ),
//             //   label: 'Post',
//             // ),
//             const BottomNavigationBarItem(
//               icon: Icon(Icons.message),
//               activeIcon: Icon(Icons.message, size: 28),
//               label: 'Messages',
//             ),
//             const BottomNavigationBarItem(
//               icon: Icon(Icons.person),
//               activeIcon: Icon(Icons.person, size: 28),
//               label: 'Profile',
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }