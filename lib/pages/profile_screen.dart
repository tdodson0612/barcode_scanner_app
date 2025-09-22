// lib/pages/profile_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/app_drawer.dart';
import '../widgets/premium_gate.dart';
import '../controllers/premium_gate_controller.dart';
import '../services/database_service.dart';
import '../services/auth_service.dart';
import '../pages/user_profile_page.dart';
import 'dart:async';

class ProfileScreen extends StatefulWidget {
  final List<String> favoriteRecipes;

  const ProfileScreen({super.key, required this.favoriteRecipes});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  File? _profileImage;
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  bool _isEditingName = false;
  bool _isEditingEmail = false;
  String _userName = 'User';
  String _userEmail = '';
  bool _isLoading = false;
  
  // Add these variables for friends functionality
  List<Map<String, dynamic>> _friends = [];
  bool _friendsListVisible = true;
  bool _isLoadingFriends = false;

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

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadFriends(); // Add this line
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  // Add these methods for friends functionality
  Future<void> _loadFriends() async {
    setState(() {
      _isLoadingFriends = true;
    });

    try {
      final friends = await DatabaseService.getUserFriends(AuthService.currentUserId!);
      final visibility = await DatabaseService.getFriendsListVisibility();
      
      setState(() {
        _friends = friends;
        _friendsListVisible = visibility;
        _isLoadingFriends = false;
      });
    } catch (e) {
      debugPrint('Error loading friends: $e');
      setState(() {
        _isLoadingFriends = false;
      });
    }
  }

  Future<void> _toggleFriendsVisibility(bool isVisible) async {
    try {
      await DatabaseService.updateFriendsListVisibility(isVisible);
      setState(() {
        _friendsListVisible = isVisible;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isVisible 
              ? 'Friends list is now visible to others' 
              : 'Friends list is now hidden from others'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error updating privacy setting'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _loadProfile() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Load from SharedPreferences first (for offline access)
      final prefs = await SharedPreferences.getInstance();
      final imagePath = prefs.getString('profile_image_path');
      final savedName = prefs.getString('user_name') ?? 'User';
      final savedEmail = prefs.getString('user_email') ?? '';
      
      setState(() {
        _userName = savedName;
        _userEmail = savedEmail;
        _nameController.text = savedName;
        _emailController.text = savedEmail;
        if (imagePath != null && imagePath.isNotEmpty) {
          _profileImage = File(imagePath);
        }
      });

      // Then try to load from Supabase (for most up-to-date data)
      final profile = await DatabaseService.getCurrentUserProfile();
      if (profile != null) {
        final userName = profile['username'] ?? savedName;
        final userEmail = profile['email'] ?? savedEmail;
        
        // Update local storage with Supabase data
        await prefs.setString('user_name', userName);
        await prefs.setString('user_email', userEmail);
        
        setState(() {
          _userName = userName;
          _userEmail = userEmail;
          _nameController.text = userName;
          _emailController.text = userEmail;
        });
      }
    } catch (e) {
      debugPrint('Error loading profile: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading profile: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: source);

    if (pickedFile != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('profile_image_path', pickedFile.path);
      
      setState(() {
        _profileImage = File(pickedFile.path);
      });

      // TODO: Upload image to Supabase storage if needed
      // For now, we're just saving locally
    }
  }

  Future<void> _saveUserName() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name cannot be empty')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Save to Supabase first
      await DatabaseService.updateProfile(username: _nameController.text.trim());
      
      // Then save to SharedPreferences as backup
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_name', _nameController.text.trim());
      
      setState(() {
        _userName = _nameController.text.trim();
        _isEditingName = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Name updated successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error saving username: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating name: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _saveUserEmail() async {
    if (_emailController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Email cannot be empty')),
      );
      return;
    }

    // Basic email validation
    if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(_emailController.text.trim())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid email address')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Save to Supabase first
      await DatabaseService.updateProfile(email: _emailController.text.trim());
      
      // Then save to SharedPreferences as backup
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_email', _emailController.text.trim());
      
      setState(() {
        _userEmail = _emailController.text.trim();
        _isEditingEmail = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Email updated successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error saving email: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating email: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
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

  @override
  Widget build(BuildContext context) {
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
          if (_isLoading)
            Center(
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
      drawer: AppDrawer(currentPage: 'profile'),
      body: Stack(
        children: [
          // Background Image
          Positioned.fill(
            child: Image.asset(
              'assets/background.png',
              fit: BoxFit.cover,
            ),
          ),
          
          // Content
          AnimatedBuilder(
            animation: PremiumGateController(),
            builder: (context, _) {
              final controller = PremiumGateController();
              
              return SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    // Profile Picture Section (ALWAYS AVAILABLE)
                    Center(
                      child: Stack(
                        children: [
                          CircleAvatar(
                            radius: 80,
                            backgroundColor: Colors.grey[300],
                            backgroundImage: _profileImage != null
                                ? FileImage(_profileImage!)
                                : null,
                            child: _profileImage == null
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

                    // Name Section (ALWAYS AVAILABLE)
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
                                      ? SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
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
                              style: const TextStyle(
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Email Section (ALWAYS AVAILABLE)
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
                                      ? SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
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
                              style: const TextStyle(
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Friends Section
                    _sectionContainer(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Friends (${_friends.length})',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              PopupMenuButton<String>(
                                icon: Icon(Icons.more_vert, size: 20),
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
                                          _friendsListVisible ? Icons.visibility_off : Icons.visibility,
                                          size: 20,
                                        ),
                                        SizedBox(width: 8),
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
                          SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(
                                _friendsListVisible ? Icons.visibility : Icons.visibility_off,
                                size: 16,
                                color: Colors.grey.shade600,
                              ),
                              SizedBox(width: 4),
                              Text(
                                _friendsListVisible ? 'Visible to others' : 'Hidden from others',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 16),
                          
                          if (_isLoadingFriends) ...[
                            Center(child: CircularProgressIndicator()),
                          ] else if (_friends.isEmpty) ...[
                            Text(
                              'No friends yet. Start by finding and adding friends!',
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 14,
                              ),
                            ),
                            SizedBox(height: 12),
                            ElevatedButton.icon(
                              onPressed: () {
                                Navigator.pushNamed(context, '/search-users');
                              },
                              icon: Icon(Icons.person_search),
                              label: Text('Find Friends'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ] else ...[
                            // Friends grid
                            GridView.builder(
                              shrinkWrap: true,
                              physics: NeverScrollableScrollPhysics(),
                              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                childAspectRatio: 0.8,
                                crossAxisSpacing: 8,
                                mainAxisSpacing: 8,
                              ),
                              itemCount: _friends.length > 6 ? 6 : _friends.length,
                              itemBuilder: (context, index) {
                                if (index == 5 && _friends.length > 6) {
                                  // Show "View All" card
                                  return GestureDetector(
                                    onTap: () {
                                      // Navigate to full friends list
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Full friends list coming soon!')),
                                      );
                                    },
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade100,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: Colors.grey.shade300),
                                      ),
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.more_horiz, size: 30, color: Colors.grey.shade600),
                                          SizedBox(height: 4),
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
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => UserProfilePage(userId: friend['id']),
                                      ),
                                    );
                                  },
                                  child: Column(
                                    children: [
                                      CircleAvatar(
                                        radius: 25,
                                        backgroundImage: friend['avatar_url'] != null
                                            ? NetworkImage(friend['avatar_url'])
                                            : null,
                                        child: friend['avatar_url'] == null
                                            ? Text(
                                                (friend['username'] ?? friend['first_name'] ?? friend['email'] ?? 'U')[0].toUpperCase(),
                                                style: TextStyle(
                                                  fontSize: 20,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              )
                                            : null,
                                      ),
                                      SizedBox(height: 4),
                                      Expanded(
                                        child: Text(
                                          friend['first_name'] != null && friend['last_name'] != null
                                              ? '${friend['first_name']} ${friend['last_name']}'
                                              : friend['username'] ?? 'Unknown',
                                          style: TextStyle(
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
                              SizedBox(height: 12),
                              TextButton(
                                onPressed: () {
                                  // Navigate to full friends list
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Full friends list coming soon!')),
                                  );
                                },
                                child: Text('View All ${_friends.length} Friends'),
                              ),
                            ],
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Premium Status Display
                    _sectionContainer(
                      child: Column(
                        children: [
                          if (controller.isPremium) ...[
                            Row(
                              children: [
                                Icon(Icons.star, color: Colors.amber, size: 24),
                                SizedBox(width: 8),
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
                            SizedBox(height: 8),
                            Text(
                              'You have access to all premium features!',
                              style: TextStyle(color: Colors.grey.shade600),
                            ),
                          ] else ...[
                            Row(
                              children: [
                                Icon(Icons.person, color: Colors.grey, size: 24),
                                SizedBox(width: 8),
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
                            SizedBox(height: 8),
                            Text(
                              'Daily scans used: ${controller.totalScansUsed}/3',
                              style: TextStyle(
                                color: controller.hasUsedAllFreeScans 
                                    ? Colors.red.shade600 
                                    : Colors.grey.shade600,
                                fontWeight: controller.hasUsedAllFreeScans 
                                    ? FontWeight.w600 
                                    : FontWeight.normal,
                              ),
                            ),
                            SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  Navigator.pushNamed(context, '/purchase');
                                },
                                icon: Icon(Icons.star),
                                label: Text('Upgrade to Premium'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.amber,
                                  foregroundColor: Colors.white,
                                  padding: EdgeInsets.symmetric(vertical: 12),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Premium Features (BLOCKED for free users)
                    PremiumGate(
                      feature: PremiumFeature.submitRecipes,
                      featureName: 'Recipe Submission',
                      featureDescription: 'Share your favorite recipes with the community.',
                      child: _sectionContainer(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Recipe Features',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  Navigator.pushNamed(context, '/submit-recipe');
                                },
                                icon: Icon(Icons.add),
                                label: Text('Submit Your Own Recipe'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                  padding: EdgeInsets.symmetric(vertical: 12),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Favorite Recipes (BLOCKED for free users)
                    PremiumGate(
                      feature: PremiumFeature.favoriteRecipes,
                      featureName: 'Favorite Recipes',
                      featureDescription: 'Save and organize your favorite recipes.',
                      showSoftPreview: true,
                      child: _sectionContainer(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Favorite Recipes',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(height: 10),
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
                              SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: () {
                                    // Navigation handled by AppDrawer
                                  },
                                  icon: Icon(Icons.favorite),
                                  label: Text('View Favorite Recipes'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red,
                                    foregroundColor: Colors.white,
                                    padding: EdgeInsets.symmetric(vertical: 12),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}