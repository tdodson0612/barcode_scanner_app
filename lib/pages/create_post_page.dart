// lib/pages/create_post_page.dart - Create Post with Photo or Video
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
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
  File? _videoFile;
  File? _thumbnailFile;
  VideoPlayerController? _videoController;
  final TextEditingController _captionController = TextEditingController();
  List<SubmittedRecipe> _myRecipes = [];
  SubmittedRecipe? _selectedRecipe;
  bool _isLoading = false;
  bool _isLoadingRecipes = false;
  String _mediaType = 'none'; // 'none', 'photo', 'video'

  @override
  void initState() {
    super.initState();
    _loadMyRecipes();
  }

  @override
  void dispose() {
    _captionController.dispose();
    _videoController?.dispose();
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
          _videoFile = null;
          _thumbnailFile = null;
          _mediaType = 'photo';
        });
        
        _videoController?.dispose();
        _videoController = null;
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

  Future<void> _pickVideo(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickVideo(
        source: source,
        maxDuration: const Duration(minutes: 3), // 3 minute max
      );

      if (pickedFile != null && mounted) {
        final videoFile = File(pickedFile.path);
        
        // Initialize video controller
        final controller = VideoPlayerController.file(videoFile);
        await controller.initialize();
        
        // Generate thumbnail from first frame
        await controller.seekTo(Duration.zero);
        
        setState(() {
          _videoFile = videoFile;
          _imageFile = null;
          _mediaType = 'video';
          _videoController = controller;
        });
        
        // Create thumbnail file (you'll need to implement this or use video_thumbnail package)
        await _generateThumbnail();
      }
    } catch (e) {
      if (mounted) {
        ErrorHandlingService.showSimpleError(
          context,
          'Failed to pick video',
        );
      }
    }
  }

  Future<void> _generateThumbnail() async {
    if (_videoFile == null) return;
    
    try {
      // For now, we'll require user to take a photo as thumbnail
      // You can use video_thumbnail package for automatic generation
      final picker = ImagePicker();
      final thumbnailPicked = await picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );
      
      if (thumbnailPicked != null && mounted) {
        setState(() {
          _thumbnailFile = File(thumbnailPicked.path);
        });
      }
    } catch (e) {
      if (mounted) {
        ErrorHandlingService.showSimpleError(
          context,
          'Failed to capture thumbnail',
        );
      }
    }
  }

  void _showMediaPickerDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Select Media Type'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library, color: Colors.blue),
                title: const Text('Photo'),
                subtitle: const Text('Take or choose a photo'),
                onTap: () {
                  Navigator.pop(context);
                  _showPhotoSourceDialog();
                },
              ),
              ListTile(
                leading: const Icon(Icons.videocam, color: Colors.red),
                title: const Text('Video'),
                subtitle: const Text('Record or choose a video (max 3 min)'),
                onTap: () {
                  Navigator.pop(context);
                  _showVideoSourceDialog();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showPhotoSourceDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Select Photo Source'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt, color: Colors.blue),
                title: const Text('Take Photo'),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library, color: Colors.blue),
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

  void _showVideoSourceDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Select Video Source'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.videocam, color: Colors.red),
                title: const Text('Record Video'),
                onTap: () {
                  Navigator.pop(context);
                  _pickVideo(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.video_library, color: Colors.red),
                title: const Text('Choose from Gallery'),
                onTap: () {
                  Navigator.pop(context);
                  _pickVideo(ImageSource.gallery);
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
          title: const Text('Select Recipe'),
          content: _isLoadingRecipes
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: CircularProgressIndicator(),
                  ),
                )
              : _myRecipes.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.restaurant_menu, size: 50, color: Colors.grey),
                          const SizedBox(height: 16),
                          const Text(
                            'No recipes yet',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Submit a recipe first before creating a post',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: () {
                              Navigator.pop(context);
                              Navigator.pushNamed(context, '/submit-recipe');
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('Submit Recipe'),
                          ),
                        ],
                      ),
                    )
                  : SizedBox(
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
              child: const Text('Cancel'),
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
    if (_imageFile == null && _videoFile == null) {
      ErrorHandlingService.showSimpleError(
        context,
        'Please select a photo or video',
      );
      return;
    }

    if (_videoFile != null && _thumbnailFile == null) {
      ErrorHandlingService.showSimpleError(
        context,
        'Please capture a thumbnail for your video',
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
        recipeId: _selectedRecipe!.id!,
        imageFile: _imageFile,
        videoFile: _videoFile,
        thumbnailFile: _thumbnailFile,
        caption: _captionController.text.trim(),
      );

      if (mounted) {
        ErrorHandlingService.showSuccess(context, 'Post created successfully!');
        Navigator.pop(context, true);
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
        title: const Text('Create Post'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        actions: [
          if (_isLoading)
            const Center(
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
              child: const Text(
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
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Media preview
            GestureDetector(
              onTap: _showMediaPickerDialog,
              child: Container(
                width: double.infinity,
                height: 300,
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: _mediaType == 'none'
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.add_photo_alternate, size: 60, color: Colors.grey),
                          const SizedBox(height: 8),
                          const Text(
                            'Tap to add photo or video',
                            style: TextStyle(color: Colors.grey),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.photo, size: 20, color: Colors.grey.shade600),
                              const SizedBox(width: 4),
                              Text('Photo', style: TextStyle(color: Colors.grey.shade600)),
                              const SizedBox(width: 16),
                              Icon(Icons.videocam, size: 20, color: Colors.grey.shade600),
                              const SizedBox(width: 4),
                              Text('Video (max 3min)', style: TextStyle(color: Colors.grey.shade600)),
                            ],
                          ),
                        ],
                      )
                    : _mediaType == 'photo' && _imageFile != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.file(
                              _imageFile!,
                              fit: BoxFit.cover,
                            ),
                          )
                        : _mediaType == 'video' && _videoController != null
                            ? Stack(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: AspectRatio(
                                      aspectRatio: _videoController!.value.aspectRatio,
                                      child: VideoPlayer(_videoController!),
                                    ),
                                  ),
                                  Positioned.fill(
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Colors.black.withOpacity(0.3),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Center(
                                        child: Icon(
                                          Icons.play_circle_outline,
                                          size: 80,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    top: 8,
                                    right: 8,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withOpacity(0.7),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Row(
                                        children: [
                                          Icon(Icons.videocam, size: 16, color: Colors.white),
                                          SizedBox(width: 4),
                                          Text(
                                            'VIDEO',
                                            style: TextStyle(color: Colors.white, fontSize: 12),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : Container(),
              ),
            ),

            if (_mediaType == 'video' && _thumbnailFile == null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.shade300),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber, color: Colors.orange.shade700),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Please capture a thumbnail photo for your video',
                          style: TextStyle(fontSize: 14),
                        ),
                      ),
                      TextButton(
                        onPressed: _generateThumbnail,
                        child: const Text('Capture'),
                      ),
                    ],
                  ),
                ),
              ),

            const SizedBox(height: 24),

            // Recipe selection
            const Text(
              'Tag Recipe *',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            InkWell(
              onTap: _showRecipeSelectionDialog,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.restaurant_menu, color: Colors.green),
                    const SizedBox(width: 12),
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
                    const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Caption
            const Text(
              'Caption (Optional)',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
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

            const SizedBox(height: 24),

            // Submit button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _submitPost,
                icon: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Icon(Icons.send),
                label: Text(_isLoading ? 'Posting...' : 'Share Post'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: const TextStyle(
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