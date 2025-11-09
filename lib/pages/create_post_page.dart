// lib/pages/create_post_page.dart - Create Post with Recipe Tag
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/database_service.dart';
import '../services/error_handling_service.dart';
import '../models/submitted_recipe.dart';

class CreatePostPage extends StatefulWidget {
  const CreatePostPage({super.key});

  @override
  State<CreatePostPage> createState() => _CreatePostPageState();
}

class _CreatePostPageState extends State<CreatePostPage> {
  File? _imageFile;
  final TextEditingController _captionController = TextEditingController();
  List<SubmittedRecipe> _myRecipes = [];
  SubmittedRecipe? _selectedRecipe;
  bool _isLoading = false;
  bool _isLoadingRecipes = false;

  @override
  void initState() {
    super.initState();
    _loadMyRecipes();
  }

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  Future<void> _loadMyRecipes() async {
    setState(() {
      _isLoadingRecipes = true;
    });

    try {
      final recipes = await DatabaseService.getSubmittedRecipes();
      
      if (mounted) {
        setState(() {
          _myRecipes = recipes;
          _isLoadingRecipes = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingRecipes = false;
        });
        
        ErrorHandlingService.showSimpleError(
          context,
          'Unable to load your recipes',
        );
      }
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );

      if (pickedFile != null && mounted) {
        setState(() {
          _imageFile = File(pickedFile.path);
        });
      }
    } catch (e) {
      if (mounted) {
        ErrorHandlingService.showSimpleError(
          context,
          'Failed to pick image',
        );
      }
    }
  }

  void _showImageSourceDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Select Image Source'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.camera_alt, color: Colors.blue),
                title: Text('Take Photo'),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.camera);
                },
              ),
              ListTile(
                leading: Icon(Icons.photo_library, color: Colors.blue),
                title: Text('Choose from Gallery'),
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

  void _showRecipeSelectionDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Select Recipe'),
          content: _isLoadingRecipes
              ? Center(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: CircularProgressIndicator(),
                  ),
                )
              : _myRecipes.isEmpty
                  ? Padding(
                      padding: EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.restaurant_menu, size: 50, color: Colors.grey),
                          SizedBox(height: 16),
                          Text(
                            'No recipes yet',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Submit a recipe first before creating a post',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey),
                          ),
                          SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: () {
                              Navigator.pop(context);
                              Navigator.pushNamed(context, '/submit-recipe');
                            },
                            child: Text('Submit Recipe'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    )
                  : Container(
                      width: double.maxFinite,
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: _myRecipes.length,
                        itemBuilder: (context, index) {
                          final recipe = _myRecipes[index];
                          return ListTile(
                            title: Text(recipe.recipeName),
                            subtitle: Text(
                              _getIngredientPreview(recipe.ingredients),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () {
                              setState(() {
                                _selectedRecipe = recipe;
                              });
                              Navigator.pop(context);
                            },
                          );
                        },
                      ),
                    ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  String _getIngredientPreview(String ingredients) {
    final lines = ingredients.split('\n');
    return lines.isNotEmpty ? lines.first : '';
  }

  Future<void> _submitPost() async {
    if (_imageFile == null) {
      ErrorHandlingService.showSimpleError(
        context,
        'Please select an image',
      );
      return;
    }

    if (_selectedRecipe == null) {
      ErrorHandlingService.showSimpleError(
        context,
        'Please select a recipe',
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      await DatabaseService.createPost(
        recipeId: _selectedRecipe!.id,
        imageFile: _imageFile!,
        caption: _captionController.text.trim(),
      );

      if (mounted) {
        ErrorHandlingService.showSuccess(context, 'Post created successfully!');
        Navigator.pop(context, true); // Return true to refresh feed
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        
        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          category: ErrorHandlingService.databaseError,
          customMessage: 'Failed to create post',
          onRetry: _submitPost,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Create Post'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        actions: [
          if (_isLoading)
            Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
              ),
            )
          else
            TextButton(
              onPressed: _submitPost,
              child: Text(
                'POST',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image preview
            GestureDetector(
              onTap: _showImageSourceDialog,
              child: Container(
                width: double.infinity,
                height: 300,
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: _imageFile == null
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_photo_alternate, size: 60, color: Colors.grey),
                          SizedBox(height: 8),
                          Text(
                            'Tap to add photo',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ],
                      )
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(
                          _imageFile!,
                          fit: BoxFit.cover,
                        ),
                      ),
              ),
            ),

            SizedBox(height: 24),

            // Recipe selection
            Text(
              'Tag Recipe *',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 8),
            InkWell(
              onTap: _showRecipeSelectionDialog,
              child: Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.restaurant_menu, color: Colors.green),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _selectedRecipe?.recipeName ?? 'Select a recipe',
                        style: TextStyle(
                          color: _selectedRecipe == null
                              ? Colors.grey
                              : Colors.black,
                        ),
                      ),
                    ),
                    Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                  ],
                ),
              ),
            ),

            SizedBox(height: 24),

            // Caption
            Text(
              'Caption (Optional)',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 8),
            TextField(
              controller: _captionController,
              decoration: InputDecoration(
                hintText: 'Write a caption...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              maxLines: 4,
              maxLength: 500,
            ),

            SizedBox(height: 24),

            // Submit button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _submitPost,
                icon: _isLoading
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : Icon(Icons.send),
                label: Text(_isLoading ? 'Posting...' : 'Share Post'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(vertical: 16),
                  textStyle: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}