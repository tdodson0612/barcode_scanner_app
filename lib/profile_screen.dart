import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'contact_screen.dart';
import 'services/database_service.dart';
import 'models/favorite_recipe.dart';
import 'models/submitted_recipe.dart';
import 'pages/grocery_list.dart';
import 'pages/submit_recipe.dart';

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
  
  // Use the actual model types
  List<FavoriteRecipe> _favoriteRecipes = [];
  List<SubmittedRecipe> _submittedRecipes = [];
  bool _isLoadingFavorites = true;
  bool _isLoadingSubmitted = true;

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
    _loadFavoriteRecipes();
    _loadSubmittedRecipes();
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

  Future<void> _loadFavoriteRecipes() async {
    try {
      // Use the actual database call
      final List<FavoriteRecipe> recipes = await DatabaseService.getFavoriteRecipes();
      setState(() {
        _favoriteRecipes = recipes;
        _isLoadingFavorites = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingFavorites = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading favorite recipes: $e')),
      );
    }
  }

  Future<void> _loadSubmittedRecipes() async {
    try {
      // Use the actual database call
      final List<SubmittedRecipe> recipes = await DatabaseService.getSubmittedRecipes();
      setState(() {
        _submittedRecipes = recipes;
        _isLoadingSubmitted = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingSubmitted = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading submitted recipes: $e')),
      );
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

  Future<void> _navigateToSubmitRecipe() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => SubmitRecipePage()),
    );
    
    if (result == true) {
      _loadSubmittedRecipes();
    }
  }

  Widget _buildRecipeExpansionTile({
    required String recipeName,
    required String ingredients,
    required String directions,
    required VoidCallback onDelete,
    String deleteTitle = 'Delete Recipe',
    String deleteMessage = 'Are you sure you want to delete this recipe?',
  }) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ExpansionTile(
        title: Text(
          recipeName,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text(deleteTitle),
                    content: Text('$deleteMessage "$recipeName"?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.pop(context);
                          onDelete();
                        },
                        child: const Text('Delete'),
                      ),
                    ],
                  ),
                );
              },
            ),
            const Icon(Icons.expand_more),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Ingredients:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                Text(ingredients),
                const SizedBox(height: 16),
                const Text(
                  'Directions:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                Text(directions),
              ],
            ),
          ),
        ],
      ),
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
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const DrawerHeader(
              decoration: BoxDecoration(
                color: Colors.blue,
              ),
              child: Text(
                'Menu',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.home),
              title: const Text('Home'),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushReplacementNamed(context, '/');
              },
            ),
            ListTile(
              leading: const Icon(Icons.person),
              title: const Text('Profile'),
              onTap: () {
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.shopping_cart),
              title: const Text('My Grocery List'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const GroceryListPage()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.contact_mail),
              title: const Text('Contact Us'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const ContactScreen()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.star),
              title: const Text('Purchase Premium'),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, '/premium');
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.arrow_back),
              title: const Text('Back'),
              onTap: () {
                Navigator.pop(context);
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/background.png',
              fit: BoxFit.cover,
            ),
          ),
          
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Profile Picture Section
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

                // Name Section
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

                // Submit Recipe Button
                _sectionContainer(
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _navigateToSubmitRecipe,
                      icon: const Icon(Icons.add),
                      label: const Text('Submit Your Own Recipe'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // Favorite Recipes Section
                _sectionContainer(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Favorite Recipes:',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 10),
                      
                      if (_isLoadingFavorites)
                        const Center(child: CircularProgressIndicator())
                      else if (_favoriteRecipes.isEmpty && widget.favoriteRecipes.isEmpty)
                        const Text(
                          'No favorite recipes yet. Start scanning products to get recipe suggestions!',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey,
                          ),
                        )
                      else ...[
                        // Show old favorite recipes (just names) for now
                        if (widget.favoriteRecipes.isNotEmpty) ...[
                          ...widget.favoriteRecipes.map((recipe) => 
                            Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.blue.shade200),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.favorite,
                                    color: Colors.red,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      recipe,
                                      style: const TextStyle(fontSize: 14),
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: () {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Recipe details coming soon!')),
                                      );
                                    },
                                    child: const Text('View Details'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                        
                        // Show Supabase favorite recipes (with full details)
                        ..._favoriteRecipes.map((recipe) => _buildRecipeExpansionTile(
                          recipeName: recipe.recipeName,
                          ingredients: recipe.ingredients,
                          directions: recipe.directions,
                          onDelete: () async {
                            await DatabaseService.removeFavoriteRecipe(recipe.id!);
                            _loadFavoriteRecipes();
                          },
                          deleteTitle: 'Remove Favorite',
                          deleteMessage: 'Remove from favorites?',
                        )),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // My Submitted Recipes Section
                _sectionContainer(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'My Submitted Recipes:',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 10),
                      
                      if (_isLoadingSubmitted)
                        const Center(child: CircularProgressIndicator())
                      else if (_submittedRecipes.isEmpty)
                        const Text(
                          'No submitted recipes yet. Use the "Submit Your Own Recipe" button above to add your first recipe!',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey,
                          ),
                        )
                      else ...[
                        // Show submitted recipes
                        ..._submittedRecipes.map((recipe) => _buildRecipeExpansionTile(
                          recipeName: recipe.recipeName,
                          ingredients: recipe.ingredients,
                          directions: recipe.directions,
                          onDelete: () async {
                            await DatabaseService.deleteSubmittedRecipe(recipe.id!);
                            _loadSubmittedRecipes();
                          },
                        )),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}