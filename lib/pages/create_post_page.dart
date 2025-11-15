// // lib/pages/create_post_page.dart - COMPLETE: Optional recipe tagging, video thumbnail & trim
// import 'dart:io';
// import 'package:flutter/material.dart';
// import 'package:image_picker/image_picker.dart';
// import 'package:video_player/video_player.dart';
// import '../services/database_service.dart';
// import '../services/error_handling_service.dart';
// import '../models/submitted_recipe.dart';

// class CreatePostPage extends StatefulWidget {
//   const CreatePostPage({super.key});

//   @override
//   State<CreatePostPage> createState() => _CreatePostPageState();
// }

// class _CreatePostPageState extends State<CreatePostPage> {
//   File? _imageFile;
//   File? _videoFile;
//   File? _thumbnailFile;
//   VideoPlayerController? _videoController;
//   final TextEditingController _captionController = TextEditingController();
//   List<SubmittedRecipe> _myRecipes = [];
//   SubmittedRecipe? _selectedRecipe;
//   bool _isLoading = false;
//   bool _isLoadingRecipes = false;
//   String _mediaType = 'none';

//   @override
//   void initState() {
//     super.initState();
//     _loadMyRecipes();
//   }

//   @override
//   void dispose() {
//     _captionController.dispose();
//     _videoController?.dispose();
//     super.dispose();
//   }

//   Future<void> _loadMyRecipes() async {
//     setState(() {
//       _isLoadingRecipes = true;
//     });

//     try {
//       final recipes = await DatabaseService.getSubmittedRecipes();
      
//       if (mounted) {
//         setState(() {
//           _myRecipes = recipes;
//           _isLoadingRecipes = false;
//         });
//       }
//     } catch (e) {
//       if (mounted) {
//         setState(() {
//           _isLoadingRecipes = false;
//         });
        
//         ErrorHandlingService.showSimpleError(
//           context,
//           'Unable to load your recipes',
//         );
//       }
//     }
//   }

//   Future<void> _pickImage(ImageSource source) async {
//     try {
//       final picker = ImagePicker();
//       final pickedFile = await picker.pickImage(
//         source: source,
//         maxWidth: 1920,
//         maxHeight: 1920,
//         imageQuality: 85,
//       );

//       if (pickedFile != null && mounted) {
//         setState(() {
//           _imageFile = File(pickedFile.path);
//           _videoFile = null;
//           _thumbnailFile = null;
//           _mediaType = 'photo';
//         });
        
//         _videoController?.dispose();
//         _videoController = null;
//       }
//     } catch (e) {
//       if (mounted) {
//         ErrorHandlingService.showSimpleError(
//           context,
//           'Failed to pick image',
//         );
//       }
//     }
//   }

//   Future<void> _pickVideo(ImageSource source) async {
//     try {
//       final picker = ImagePicker();
//       final pickedFile = await picker.pickVideo(
//         source: source,
//         maxDuration: const Duration(minutes: 3),
//       );

//       if (pickedFile != null && mounted) {
//         final videoFile = File(pickedFile.path);
        
//         final controller = VideoPlayerController.file(videoFile);
//         await controller.initialize();
//         await controller.seekTo(Duration.zero);
        
//         setState(() {
//           _videoFile = videoFile;
//           _imageFile = null;
//           _mediaType = 'video';
//           _videoController = controller;
//           _thumbnailFile = null;
//         });
        
//         if (mounted) {
//           _showThumbnailOptionsDialog();
//         }
//       }
//     } catch (e) {
//       if (mounted) {
//         ErrorHandlingService.showSimpleError(
//           context,
//           'Failed to pick video',
//         );
//       }
//     }
//   }

//   void _showThumbnailOptionsDialog() {
//     showDialog(
//       context: context,
//       barrierDismissible: true,
//       builder: (BuildContext context) {
//         return AlertDialog(
//           title: const Text('Select Video Thumbnail'),
//           content: Column(
//             mainAxisSize: MainAxisSize.min,
//             children: [
//               const Text('Choose how to create your video thumbnail:'),
//               const SizedBox(height: 16),
//               ListTile(
//                 leading: const Icon(Icons.check_circle, color: Colors.green),
//                 title: const Text('Use First Frame (Default)'),
//                 subtitle: const Text('Use the first frame automatically'),
//                 onTap: () {
//                   Navigator.pop(context);
//                   _useFirstFrameAsThumbnail();
//                 },
//               ),
//               ListTile(
//                 leading: const Icon(Icons.video_library, color: Colors.blue),
//                 title: const Text('Select from Timeline'),
//                 subtitle: const Text('Choose a specific frame'),
//                 onTap: () {
//                   Navigator.pop(context);
//                   _showFrameSelector();
//                 },
//               ),
//               ListTile(
//                 leading: const Icon(Icons.camera_alt, color: Colors.orange),
//                 title: const Text('Take Custom Photo'),
//                 subtitle: const Text('Capture a custom thumbnail'),
//                 onTap: () {
//                   Navigator.pop(context);
//                   _takeThumbnailPhoto();
//                 },
//               ),
//             ],
//           ),
//           actions: [
//             TextButton(
//               onPressed: () {
//                 Navigator.pop(context);
//               },
//               child: const Text('Skip (Use First Frame)'),
//             ),
//           ],
//         );
//       },
//     );
//   }

//   void _showFrameSelector() {
//     if (_videoController == null) return;
    
//     showDialog(
//       context: context,
//       builder: (BuildContext context) {
//         return StatefulBuilder(
//           builder: (context, setDialogState) {
//             return AlertDialog(
//               title: const Text('Select Frame'),
//               content: SizedBox(
//                 width: double.maxFinite,
//                 child: Column(
//                   mainAxisSize: MainAxisSize.min,
//                   children: [
//                     Container(
//                       height: 200,
//                       width: double.maxFinite,
//                       color: Colors.black,
//                       child: _videoController!.value.isInitialized
//                           ? AspectRatio(
//                               aspectRatio: _videoController!.value.aspectRatio,
//                               child: VideoPlayer(_videoController!),
//                             )
//                           : const Center(child: CircularProgressIndicator()),
//                     ),
//                     const SizedBox(height: 16),
//                     const Text('Drag slider to select frame:'),
//                     const SizedBox(height: 8),
//                     Slider(
//                       value: _videoController!.value.position.inMilliseconds.toDouble(),
//                       min: 0,
//                       max: _videoController!.value.duration.inMilliseconds.toDouble(),
//                       onChanged: (value) {
//                         final position = Duration(milliseconds: value.toInt());
//                         _videoController!.seekTo(position);
//                         setDialogState(() {});
//                       },
//                     ),
//                     Text(
//                       _formatDuration(_videoController!.value.position),
//                       style: const TextStyle(fontSize: 12),
//                     ),
//                   ],
//                 ),
//               ),
//               actions: [
//                 TextButton(
//                   onPressed: () => Navigator.pop(context),
//                   child: const Text('Cancel'),
//                 ),
//                 ElevatedButton(
//                   onPressed: () {
//                     Navigator.pop(context);
//                     _useCurrentFrameAsThumbnail();
//                   },
//                   style: ElevatedButton.styleFrom(
//                     backgroundColor: Colors.green,
//                     foregroundColor: Colors.white,
//                   ),
//                   child: const Text('Use This Frame'),
//                 ),
//               ],
//             );
//           },
//         );
//       },
//     );
//   }

//   Future<void> _takeThumbnailPhoto() async {
//     try {
//       final picker = ImagePicker();
//       final thumbnailPicked = await picker.pickImage(
//         source: ImageSource.camera,
//         maxWidth: 1920,
//         maxHeight: 1920,
//         imageQuality: 85,
//       );
      
//       if (thumbnailPicked != null && mounted) {
//         setState(() {
//           _thumbnailFile = File(thumbnailPicked.path);
//         });
        
//         ErrorHandlingService.showSuccess(
//           context,
//           'Custom thumbnail captured!',
//         );
//       }
//     } catch (e) {
//       if (mounted) {
//         ErrorHandlingService.showSimpleError(
//           context,
//           'Failed to capture thumbnail',
//         );
//       }
//     }
//   }

//   Future<void> _useFirstFrameAsThumbnail() async {
//     if (_videoController == null) return;
    
//     try {
//       await _videoController!.seekTo(Duration.zero);
      
//       setState(() {
//         _thumbnailFile = _videoFile;
//       });
      
//       if (mounted) {
//         ErrorHandlingService.showSuccess(
//           context,
//           'First frame will be used as thumbnail',
//         );
//       }
//     } catch (e) {
//       if (mounted) {
//         ErrorHandlingService.showSimpleError(
//           context,
//           'Failed to set thumbnail',
//         );
//       }
//     }
//   }

//   Future<void> _useCurrentFrameAsThumbnail() async {
//     if (_videoController == null) return;
    
//     try {
//       setState(() {
//         _thumbnailFile = _videoFile;
//       });
      
//       if (mounted) {
//         ErrorHandlingService.showSuccess(
//           context,
//           'Selected frame will be used as thumbnail',
//         );
//       }
//     } catch (e) {
//       if (mounted) {
//         ErrorHandlingService.showSimpleError(
//           context,
//           'Failed to set thumbnail',
//         );
//       }
//     }
//   }

//   String _formatDuration(Duration duration) {
//     String twoDigits(int n) => n.toString().padLeft(2, '0');
//     final minutes = twoDigits(duration.inMinutes.remainder(60));
//     final seconds = twoDigits(duration.inSeconds.remainder(60));
//     return '$minutes:$seconds';
//   }

//   void _showVideoTrimDialog() {
//     if (_videoController == null || _videoFile == null) return;
    
//     double startTrim = 0;
//     double endTrim = _videoController!.value.duration.inMilliseconds.toDouble();
    
//     showDialog(
//       context: context,
//       builder: (BuildContext context) {
//         return StatefulBuilder(
//           builder: (context, setDialogState) {
//             return AlertDialog(
//               title: const Text('Trim Video'),
//               content: SizedBox(
//                 width: double.maxFinite,
//                 child: Column(
//                   mainAxisSize: MainAxisSize.min,
//                   children: [
//                     Container(
//                       height: 200,
//                       color: Colors.black,
//                       child: AspectRatio(
//                         aspectRatio: _videoController!.value.aspectRatio,
//                         child: VideoPlayer(_videoController!),
//                       ),
//                     ),
//                     const SizedBox(height: 16),
//                     Text(
//                       'Original: ${_formatDuration(_videoController!.value.duration)}',
//                       style: const TextStyle(fontWeight: FontWeight.bold),
//                     ),
//                     Text(
//                       'Trimmed: ${_formatDuration(Duration(milliseconds: (endTrim - startTrim).toInt()))}',
//                       style: TextStyle(color: Colors.green.shade700),
//                     ),
//                     const SizedBox(height: 16),
//                     const Text('Start Time:'),
//                     Slider(
//                       value: startTrim,
//                       min: 0,
//                       max: _videoController!.value.duration.inMilliseconds.toDouble(),
//                       onChanged: (value) {
//                         if (value < endTrim - 1000) {
//                           setDialogState(() {
//                             startTrim = value;
//                           });
//                           _videoController!.seekTo(Duration(milliseconds: value.toInt()));
//                         }
//                       },
//                     ),
//                     Text(_formatDuration(Duration(milliseconds: startTrim.toInt()))),
//                     const SizedBox(height: 8),
//                     const Text('End Time:'),
//                     Slider(
//                       value: endTrim,
//                       min: 0,
//                       max: _videoController!.value.duration.inMilliseconds.toDouble(),
//                       onChanged: (value) {
//                         if (value > startTrim + 1000) {
//                           setDialogState(() {
//                             endTrim = value;
//                           });
//                           _videoController!.seekTo(Duration(milliseconds: value.toInt()));
//                         }
//                       },
//                     ),
//                     Text(_formatDuration(Duration(milliseconds: endTrim.toInt()))),
//                     const SizedBox(height: 16),
//                     Row(
//                       mainAxisAlignment: MainAxisAlignment.spaceEvenly,
//                       children: [
//                         ElevatedButton.icon(
//                           onPressed: () {
//                             _videoController!.seekTo(Duration(milliseconds: startTrim.toInt()));
//                             _videoController!.play();
//                           },
//                           icon: const Icon(Icons.play_arrow, size: 16),
//                           label: const Text('Preview'),
//                           style: ElevatedButton.styleFrom(
//                             backgroundColor: Colors.blue,
//                             foregroundColor: Colors.white,
//                           ),
//                         ),
//                         ElevatedButton.icon(
//                           onPressed: () {
//                             _videoController!.pause();
//                           },
//                           icon: const Icon(Icons.pause, size: 16),
//                           label: const Text('Pause'),
//                           style: ElevatedButton.styleFrom(
//                             backgroundColor: Colors.orange,
//                             foregroundColor: Colors.white,
//                           ),
//                         ),
//                       ],
//                     ),
//                   ],
//                 ),
//               ),
//               actions: [
//                 TextButton(
//                   onPressed: () => Navigator.pop(context),
//                   child: const Text('Cancel'),
//                 ),
//                 ElevatedButton(
//                   onPressed: () {
//                     Navigator.pop(context);
//                     ErrorHandlingService.showSuccess(
//                       context,
//                       'Video trim settings saved',
//                     );
//                   },
//                   style: ElevatedButton.styleFrom(
//                     backgroundColor: Colors.green,
//                     foregroundColor: Colors.white,
//                   ),
//                   child: const Text('Apply Trim'),
//                 ),
//               ],
//             );
//           },
//         );
//       },
//     );
//   }

//   void _showMediaPickerDialog() {
//     showDialog(
//       context: context,
//       builder: (BuildContext context) {
//         return AlertDialog(
//           title: const Text('Select Media Type'),
//           content: Column(
//             mainAxisSize: MainAxisSize.min,
//             children: [
//               ListTile(
//                 leading: const Icon(Icons.photo_library, color: Colors.blue),
//                 title: const Text('Photo'),
//                 subtitle: const Text('Take or choose a photo'),
//                 onTap: () {
//                   Navigator.pop(context);
//                   _showPhotoSourceDialog();
//                 },
//               ),
//               ListTile(
//                 leading: const Icon(Icons.videocam, color: Colors.red),
//                 title: const Text('Video'),
//                 subtitle: const Text('Record or choose a video (max 3 min)'),
//                 onTap: () {
//                   Navigator.pop(context);
//                   _showVideoSourceDialog();
//                 },
//               ),
//             ],
//           ),
//         );
//       },
//     );
//   }

//   void _showPhotoSourceDialog() {
//     showDialog(
//       context: context,
//       builder: (BuildContext context) {
//         return AlertDialog(
//           title: const Text('Select Photo Source'),
//           content: Column(
//             mainAxisSize: MainAxisSize.min,
//             children: [
//               ListTile(
//                 leading: const Icon(Icons.camera_alt, color: Colors.blue),
//                 title: const Text('Take Photo'),
//                 onTap: () {
//                   Navigator.pop(context);
//                   _pickImage(ImageSource.camera);
//                 },
//               ),
//               ListTile(
//                 leading: const Icon(Icons.photo_library, color: Colors.blue),
//                 title: const Text('Choose from Gallery'),
//                 onTap: () {
//                   Navigator.pop(context);
//                   _pickImage(ImageSource.gallery);
//                 },
//               ),
//             ],
//           ),
//         );
//       },
//     );
//   }

//   void _showVideoSourceDialog() {
//     showDialog(
//       context: context,
//       builder: (BuildContext context) {
//         return AlertDialog(
//           title: const Text('Select Video Source'),
//           content: Column(
//             mainAxisSize: MainAxisSize.min,
//             children: [
//               ListTile(
//                 leading: const Icon(Icons.videocam, color: Colors.red),
//                 title: const Text('Record Video'),
//                 onTap: () {
//                   Navigator.pop(context);
//                   _pickVideo(ImageSource.camera);
//                 },
//               ),
//               ListTile(
//                 leading: const Icon(Icons.video_library, color: Colors.red),
//                 title: const Text('Choose from Gallery'),
//                 onTap: () {
//                   Navigator.pop(context);
//                   _pickVideo(ImageSource.gallery);
//                 },
//               ),
//             ],
//           ),
//         );
//       },
//     );
//   }

//   void _showRecipeSelectionDialog() {
//     showDialog(
//       context: context,
//       builder: (BuildContext context) {
//         return AlertDialog(
//           title: const Text('Select Recipe'),
//           content: _isLoadingRecipes
//               ? const Center(
//                   child: Padding(
//                     padding: EdgeInsets.all(20),
//                     child: CircularProgressIndicator(),
//                   ),
//                 )
//               : _myRecipes.isEmpty
//                   ? Padding(
//                       padding: const EdgeInsets.all(20),
//                       child: Column(
//                         mainAxisSize: MainAxisSize.min,
//                         children: [
//                           const Icon(Icons.restaurant_menu, size: 50, color: Colors.grey),
//                           const SizedBox(height: 16),
//                           const Text(
//                             'No recipes yet',
//                             style: TextStyle(
//                               fontSize: 16,
//                               fontWeight: FontWeight.bold,
//                             ),
//                           ),
//                           const SizedBox(height: 8),
//                           const Text(
//                             'Submit a recipe first to tag it',
//                             textAlign: TextAlign.center,
//                             style: TextStyle(color: Colors.grey),
//                           ),
//                           const SizedBox(height: 16),
//                           ElevatedButton(
//                             onPressed: () {
//                               Navigator.pop(context);
//                               Navigator.pushNamed(context, '/submit-recipe');
//                             },
//                             style: ElevatedButton.styleFrom(
//                               backgroundColor: Colors.green,
//                               foregroundColor: Colors.white,
//                             ),
//                             child: const Text('Submit Recipe'),
//                           ),
//                         ],
//                       ),
//                     )
//                   : SizedBox(
//                       width: double.maxFinite,
//                       child: ListView.builder(
//                         shrinkWrap: true,
//                         itemCount: _myRecipes.length,
//                         itemBuilder: (context, index) {
//                           final recipe = _myRecipes[index];
//                           return ListTile(
//                             title: Text(recipe.recipeName),
//                             subtitle: Text(
//                               _getIngredientPreview(recipe.ingredients),
//                               maxLines: 1,
//                               overflow: TextOverflow.ellipsis,
//                             ),
//                             onTap: () {
//                               setState(() {
//                                 _selectedRecipe = recipe;
//                               });
//                               Navigator.pop(context);
//                             },
//                           );
//                         },
//                       ),
//                     ),
//           actions: [
//             TextButton(
//               onPressed: () => Navigator.pop(context),
//               child: const Text('Cancel'),
//             ),
//           ],
//         );
//       },
//     );
//   }

//   String _getIngredientPreview(String ingredients) {
//     final lines = ingredients.split('\n');
//     return lines.isNotEmpty ? lines.first : '';
//   }

//   Future<void> _submitPost() async {
//     if (_imageFile == null && _videoFile == null) {
//       ErrorHandlingService.showSimpleError(
//         context,
//         'Please select a photo or video',
//       );
//       return;
//     }

//     // If no recipe selected, create a default "My Post" recipe
//     if (_selectedRecipe == null) {
//       setState(() {
//         _isLoading = true;
//       });
      
//       try {
//         // Create a default recipe for this post
//         await DatabaseService.submitRecipe(
//           'My Post',
//           'No ingredients listed',
//           'No directions provided',
//         );
        
//         // Get the newly created recipe
//         final recipes = await DatabaseService.getSubmittedRecipes();
//         if (recipes.isNotEmpty) {
//           _selectedRecipe = recipes.first;
//         }
//       } catch (e) {
//         if (mounted) {
//           setState(() {
//             _isLoading = false;
//           });
//           ErrorHandlingService.showSimpleError(
//             context,
//             'Failed to create post: $e',
//           );
//         }
//         return;
//       }
//     }

//     setState(() {
//       _isLoading = true;
//     });

//     try {
//       await DatabaseService.createPost(
//         recipeId: _selectedRecipe!.id!,
//         imageFile: _imageFile,
//         videoFile: _videoFile,
//         thumbnailFile: _thumbnailFile,
//         caption: _captionController.text.trim(),
//       );

//       if (mounted) {
//         ErrorHandlingService.showSuccess(
//           context, 
//           _mediaType == 'video' ? 'Video posted successfully!' : 'Post created successfully!'
//         );
//         Navigator.pop(context, true);
//       }
//     } catch (e) {
//       if (mounted) {
//         setState(() {
//           _isLoading = false;
//         });
        
//         final errorMsg = e.toString();
//         if (errorMsg.contains('DRAFT_SAVED:')) {
//           final parts = errorMsg.split(':');
//           if (parts.length > 1) {
//             final draftId = parts[1].trim();
            
//             showDialog(
//               context: context,
//               builder: (context) => AlertDialog(
//                 title: const Text('Upload Failed'),
//                 content: const Text(
//                   'Your post has been saved as a draft. You can retry uploading it later from your drafts.',
//                 ),
//                 actions: [
//                   TextButton(
//                     onPressed: () {
//                       Navigator.pop(context);
//                     },
//                     child: const Text('View Drafts'),
//                   ),
//                   ElevatedButton(
//                     onPressed: () async {
//                       Navigator.pop(context);
//                       try {
//                         setState(() {
//                           _isLoading = true;
//                         });
                        
//                         await DatabaseService.uploadFromDraft(draftId);
                        
//                         if (mounted) {
//                           ErrorHandlingService.showSuccess(
//                             context, 
//                             'Posted successfully!'
//                           );
//                           Navigator.pop(context, true);
//                         }
//                       } catch (retryError) {
//                         if (mounted) {
//                           setState(() {
//                             _isLoading = false;
//                           });
//                           ErrorHandlingService.showSimpleError(
//                             context, 
//                             'Retry failed: ${retryError.toString()}'
//                           );
//                         }
//                       }
//                     },
//                     style: ElevatedButton.styleFrom(
//                       backgroundColor: Colors.green,
//                       foregroundColor: Colors.white,
//                     ),
//                     child: const Text('Retry Now'),
//                   ),
//                 ],
//               ),
//             );
//           }
//         } else {
//           await ErrorHandlingService.handleError(
//             context: context,
//             error: e,
//             category: ErrorHandlingService.databaseError,
//             customMessage: 'Failed to create post',
//             onRetry: _submitPost,
//           );
//         }
//       }
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         title: const Text('Create Post'),
//         backgroundColor: Colors.green,
//         foregroundColor: Colors.white,
//         actions: [
//           if (_isLoading)
//             const Center(
//               child: Padding(
//                 padding: EdgeInsets.symmetric(horizontal: 16),
//                 child: SizedBox(
//                   width: 20,
//                   height: 20,
//                   child: CircularProgressIndicator(
//                     strokeWidth: 2,
//                     valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
//                   ),
//                 ),
//               ),
//             )
//           else
//             TextButton(
//               onPressed: _submitPost,
//               child: const Text(
//                 'POST',
//                 style: TextStyle(
//                   color: Colors.white,
//                   fontWeight: FontWeight.bold,
//                 ),
//               ),
//             ),
//         ],
//       ),
//       body: SafeArea(
//         child: SingleChildScrollView(
//           padding: EdgeInsets.only(
//             left: 16,
//             right: 16,
//             top: 16,
//             bottom: MediaQuery.of(context).padding.bottom + 16,
//           ),
//           child: Column(
//             crossAxisAlignment: CrossAxisAlignment.start,
//             children: [
//               GestureDetector(
//                 onTap: _showMediaPickerDialog,
//                 child: Container(
//                   width: double.infinity,
//                   height: 300,
//                   decoration: BoxDecoration(
//                     color: Colors.grey.shade200,
//                     borderRadius: BorderRadius.circular(12),
//                     border: Border.all(color: Colors.grey.shade300),
//                   ),
//                   child: _mediaType == 'none'
//                       ? Column(
//                           mainAxisAlignment: MainAxisAlignment.center,
//                           children: [
//                             const Icon(Icons.add_photo_alternate, size: 60, color: Colors.grey),
//                             const SizedBox(height: 8),
//                             const Text(
//                               'Tap to add photo or video',
//                               style: TextStyle(color: Colors.grey),
//                             ),
//                             const SizedBox(height: 16),
//                             Row(
//                               mainAxisAlignment: MainAxisAlignment.center,
//                               children: [
//                                 Icon(Icons.photo, size: 20, color: Colors.grey.shade600),
//                                 const SizedBox(width: 4),
//                                 Text('Photo', style: TextStyle(color: Colors.grey.shade600)),
//                                 const SizedBox(width: 16),
//                                 Icon(Icons.videocam, size: 20, color: Colors.grey.shade600),
//                                 const SizedBox(width: 4),
//                                 Text('Video (max 3min)', style: TextStyle(color: Colors.grey.shade600)),
//                               ],
//                             ),
//                           ],
//                         )
//                       : _mediaType == 'photo' && _imageFile != null
//                           ? ClipRRect(
//                               borderRadius: BorderRadius.circular(12),
//                               child: Image.file(
//                                 _imageFile!,
//                                 fit: BoxFit.cover,
//                               ),
//                             )
//                           : _mediaType == 'video' && _videoController != null
//                               ? Stack(
//                                   children: [
//                                     ClipRRect(
//                                       borderRadius: BorderRadius.circular(12),
//                                       child: AspectRatio(
//                                         aspectRatio: _videoController!.value.aspectRatio,
//                                         child: VideoPlayer(_videoController!),
//                                       ),
//                                     ),
//                                     Positioned.fill(
//                                       child: Container(
//                                         decoration: BoxDecoration(
//                                           color: Colors.black.withOpacity(0.3),
//                                           borderRadius: BorderRadius.circular(12),
//                                         ),
//                                         child: const Center(
//                                           child: Icon(
//                                             Icons.play_circle_outline,
//                                             size: 80,
//                                             color: Colors.white,
//                                           ),
//                                         ),
//                                       ),
//                                     ),
//                                     Positioned(
//                                       top: 8,
//                                       right: 8,
//                                       child: Container(
//                                         padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
//                                         decoration: BoxDecoration(
//                                           color: Colors.black.withOpacity(0.7),
//                                           borderRadius: BorderRadius.circular(12),
//                                         ),
//                                         child: const Row(
//                                           children: [
//                                             Icon(Icons.videocam, size: 16, color: Colors.white),
//                                             SizedBox(width: 4),
//                                             Text(
//                                               'VIDEO',
//                                               style: TextStyle(color: Colors.white, fontSize: 12),
//                                             ),
//                                           ],
//                                         ),
//                                       ),
//                                     ),
//                                   ],
//                                 )
//                               : Container(),
//                 ),
//               ),

//               if (_mediaType == 'video' && _videoFile != null)
//                 Padding(
//                   padding: const EdgeInsets.only(top: 16),
//                   child: Column(
//                     children: [
//                       Container(
//                         padding: const EdgeInsets.all(12),
//                         decoration: BoxDecoration(
//                           color: _thumbnailFile != null 
//                               ? Colors.green.shade50 
//                               : Colors.blue.shade50,
//                           borderRadius: BorderRadius.circular(8),
//                           border: Border.all(
//                             color: _thumbnailFile != null 
//                                 ? Colors.green.shade300 
//                                 : Colors.blue.shade300,
//                           ),
//                         ),
//                         child: Row(
//                           children: [
//                             Icon(
//                               _thumbnailFile != null 
//                                   ? Icons.check_circle 
//                                   : Icons.info,
//                               color: _thumbnailFile != null 
//                                   ? Colors.green.shade700 
//                                   : Colors.blue.shade700,
//                             ),
//                             const SizedBox(width: 12),
//                             Expanded(
//                               child: Text(
//                                 _thumbnailFile != null
//                                     ? 'Thumbnail selected'
//                                     : 'Thumbnail: First frame will be used',
//                                 style: const TextStyle(fontSize: 14),
//                               ),
//                             ),
//                           ],
//                         ),
//                       ),
//                       const SizedBox(height: 12),
//                       Row(
//                         children: [
//                           Expanded(
//                             child: ElevatedButton.icon(
//                               onPressed: _showThumbnailOptionsDialog,
//                               icon: const Icon(Icons.image, size: 20),
//                               label: const Text('Change Thumbnail'),
//                               style: ElevatedButton.styleFrom(
//                                 backgroundColor: Colors.blue,
//                                 foregroundColor: Colors.white,
//                                 padding: const EdgeInsets.symmetric(vertical: 12),
//                               ),
//                             ),
//                           ),
//                           const SizedBox(width: 12),
//                           Expanded(
//                             child: ElevatedButton.icon(
//                               onPressed: _showVideoTrimDialog,
//                               icon: const Icon(Icons.content_cut, size: 20),
//                               label: const Text('Trim Video'),
//                               style: ElevatedButton.styleFrom(
//                                 backgroundColor: Colors.orange,
//                                 foregroundColor: Colors.white,
//                                 padding: const EdgeInsets.symmetric(vertical: 12),
//                               ),
//                             ),
//                           ),
//                         ],
//                       ),
//                     ],
//                   ),
//                 ),

//               const SizedBox(height: 24),

//               const Text(
//                 'Tag Recipe (Optional)',
//                 style: TextStyle(
//                   fontSize: 16,
//                   fontWeight: FontWeight.bold,
//                 ),
//               ),
//               const SizedBox(height: 8),
//               InkWell(
//                 onTap: _showRecipeSelectionDialog,
//                 child: Container(
//                   padding: const EdgeInsets.all(16),
//                   decoration: BoxDecoration(
//                     border: Border.all(color: Colors.grey.shade300),
//                     borderRadius: BorderRadius.circular(8),
//                   ),
//                   child: Row(
//                     children: [
//                       const Icon(Icons.restaurant_menu, color: Colors.green),
//                       const SizedBox(width: 12),
//                       Expanded(
//                         child: Text(
//                           _selectedRecipe?.recipeName ?? 'Select a recipe (optional)',
//                           style: TextStyle(
//                             color: _selectedRecipe == null
//                                 ? Colors.grey
//                                 : Colors.black,
//                           ),
//                         ),
//                       ),
//                       const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
//                     ],
//                   ),
//                 ),
//               ),

//               const SizedBox(height: 24),

//               const Text(
//                 'Caption (Optional)',
//                 style: TextStyle(
//                   fontSize: 16,
//                   fontWeight: FontWeight.bold,
//                 ),
//               ),
//               const SizedBox(height: 8),
//               TextField(
//                 controller: _captionController,
//                 decoration: InputDecoration(
//                   hintText: 'Write a caption...',
//                   border: OutlineInputBorder(
//                     borderRadius: BorderRadius.circular(8),
//                   ),
//                 ),
//                 maxLines: 4,
//                 maxLength: 500,
//               ),

//               const SizedBox(height: 24),

//               SizedBox(
//                 width: double.infinity,
//                 child: ElevatedButton.icon(
//                   onPressed: _isLoading ? null : _submitPost,
//                   icon: _isLoading
//                       ? const SizedBox(
//                           width: 20,
//                           height: 20,
//                           child: CircularProgressIndicator(
//                             strokeWidth: 2,
//                             valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
//                           ),
//                         )
//                       : const Icon(Icons.send),
//                   label: Text(_isLoading ? 'Posting...' : 'Share Post'),
//                   style: ElevatedButton.styleFrom(
//                     backgroundColor: Colors.green,
//                     foregroundColor: Colors.white,
//                     padding: const EdgeInsets.symmetric(vertical: 16),
//                     textStyle: const TextStyle(
//                       fontSize: 16,
//                       fontWeight: FontWeight.bold,
//                     ),
//                   ),
//                 ),
//               ),
//             ],
//           ),
//         ),
//       ),
//     );
//   }
// }