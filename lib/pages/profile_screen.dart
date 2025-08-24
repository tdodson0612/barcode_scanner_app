// lib/pages/profile_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/app_drawer.dart';
import '../widgets/premium_gate.dart';
import '../controllers/premium_gate_controller.dart';

class ProfileScreen extends StatefulWidget {
  final List<String> favoriteRecipes;

  const ProfileScreen({super.key, required this.favoriteRecipes});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  File? _profileImage;
  final TextEditingController _nameController = TextEditingController();
  bool _isEditingName = false;
  String _userName = 'User';

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
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final imagePath = prefs.getString('profile_image_path');
    final savedName = prefs.getString('user_name') ?? 'User';
    
    setState(() {
      _userName = savedName;
      _nameController.text = savedName;
      if (imagePath != null && imagePath.isNotEmpty) {
        _profileImage = File(imagePath);
      }
    });
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
    }
  }

  Future<void> _saveUserName() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_name', _nameController.text);
    
    setState(() {
      _userName = _nameController.text;
      _isEditingName = false;
    });
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated!')),
      );
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

  void _cancelEditName() {
    setState(() {
      _isEditingName = false;
      _nameController.text = _userName;
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
                                'Name:',
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
                                hintText: 'Enter your name',
                              ),
                              autofocus: true,
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                ElevatedButton(
                                  onPressed: _saveUserName,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blue,
                                    foregroundColor: Colors.white,
                                  ),
                                  child: const Text('Save'),
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
                              _userName,
                              style: const TextStyle(
                                fontSize: 16,
                              ),
                            ),
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
                                  Navigator.pushNamed(context, '/premium');
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
                                  // This will be handled by PremiumGate
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
                              'No favorite recipes yet. Start scanning to discover new recipes!',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey.shade600,
                              ),
                            ),
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


