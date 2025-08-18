import 'package:flutter/material.dart';
// Uncomment when you create the database service
import '../services/database_service.dart';

class SubmitRecipePage extends StatefulWidget {
  @override
  _SubmitRecipePageState createState() => _SubmitRecipePageState();
}

class _SubmitRecipePageState extends State<SubmitRecipePage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _ingredientsController = TextEditingController();
  final TextEditingController _directionsController = TextEditingController();
  bool isSubmitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _ingredientsController.dispose();
    _directionsController.dispose();
    super.dispose();
  }

  Future<void> _submitRecipe() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      isSubmitting = true;
    });

    try {
      // Uncomment when you add DatabaseService
      await DatabaseService.submitRecipe(
        _nameController.text.trim(),
        _ingredientsController.text.trim(),
        _directionsController.text.trim(),
      );

      // Temporary - simulate submission
      await Future.delayed(Duration(seconds: 2));

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Recipe submitted successfully!'),
          backgroundColor: Colors.green,
        ),
      );

      // Clear form
      _nameController.clear();
      _ingredientsController.clear();
      _directionsController.clear();

      // Return true to indicate success
      Navigator.pop(context, true);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error submitting recipe: $e')),
      );
    } finally {
      setState(() {
        isSubmitting = false;
      });
    }
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    int maxLines = 1,
    required String? Function(String?) validator,
  }) {
    return Container(
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
              Icon(
                _getIconForField(label),
                color: Colors.green,
                size: 20,
              ),
              SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          TextFormField(
            controller: controller,
            maxLines: maxLines,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(color: Colors.grey.shade600),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.green, width: 2),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.red, width: 2),
              ),
              contentPadding: EdgeInsets.all(12),
              filled: true,
              fillColor: Colors.grey.shade50,
            ),
            validator: validator,
          ),
        ],
      ),
    );
  }

  IconData _getIconForField(String label) {
    switch (label) {
      case 'Recipe Name':
        return Icons.restaurant;
      case 'Ingredients':
        return Icons.list_alt;
      case 'Directions':
        return Icons.description;
      default:
        return Icons.edit;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Submit Your Recipe'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          // Background Image (matching your app's style)
          Positioned.fill(
            child: Image.asset(
              'assets/background.png',
              fit: BoxFit.cover,
            ),
          ),
          
          // Content
          SingleChildScrollView(
            padding: EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  // Header Section
                  Container(
                    padding: EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha((0.9 * 255).toInt()),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.add_circle_outline,
                          size: 48,
                          color: Colors.green,
                        ),
                        SizedBox(height: 12),
                        Text(
                          'Share Your Recipe',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Fill out the form below to share your favorite recipe with others!',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                  
                  SizedBox(height: 20),
                  
                  // Recipe Name Field
                  _buildTextField(
                    controller: _nameController,
                    label: 'Recipe Name',
                    hint: 'Enter the name of your recipe',
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter a recipe name';
                      }
                      if (value.trim().length < 3) {
                        return 'Recipe name must be at least 3 characters';
                      }
                      return null;
                    },
                  ),
                  
                  SizedBox(height: 20),
                  
                  // Ingredients Field
                  _buildTextField(
                    controller: _ingredientsController,
                    label: 'Ingredients',
                    hint: 'List all ingredients needed for this recipe\n\nExample:\n• 2 cups flour\n• 1 tsp salt\n• 3 eggs',
                    maxLines: 8,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter the ingredients';
                      }
                      if (value.trim().length < 10) {
                        return 'Please provide more detailed ingredients';
                      }
                      return null;
                    },
                  ),
                  
                  SizedBox(height: 20),
                  
                  // Directions Field
                  _buildTextField(
                    controller: _directionsController,
                    label: 'Directions',
                    hint: 'Provide step-by-step instructions\n\nExample:\n1. Preheat oven to 350°F\n2. Mix dry ingredients...\n3. Add wet ingredients...',
                    maxLines: 10,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter the directions';
                      }
                      if (value.trim().length < 20) {
                        return 'Please provide more detailed directions';
                      }
                      return null;
                    },
                  ),
                  
                  SizedBox(height: 30),
                  
                  // Submit Button
                  Container(
                    padding: EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha((0.9 * 255).toInt()),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      children: [
                        SizedBox(
                          width: double.infinity,
                          height: 54,
                          child: ElevatedButton.icon(
                            onPressed: isSubmitting ? null : _submitRecipe,
                            icon: isSubmitting 
                                ? SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                    ),
                                  )
                                : Icon(Icons.send, size: 20),
                            label: Text(
                              isSubmitting ? 'Submitting Recipe...' : 'Submit Recipe',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              elevation: 2,
                            ),
                          ),
                        ),
                        
                        SizedBox(height: 12),
                        
                        // Cancel Button
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: TextButton.icon(
                            onPressed: isSubmitting ? null : () {
                              // Show confirmation if form has content
                              if (_nameController.text.isNotEmpty || 
                                  _ingredientsController.text.isNotEmpty || 
                                  _directionsController.text.isNotEmpty) {
                                showDialog(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: Text('Discard Recipe?'),
                                    content: Text('Are you sure you want to discard your recipe? All changes will be lost.'),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(context),
                                        child: Text('Keep Writing'),
                                      ),
                                      TextButton(
                                        onPressed: () {
                                          Navigator.pop(context);
                                          Navigator.pop(context);
                                        },
                                        child: Text('Discard'),
                                      ),
                                    ],
                                  ),
                                );
                              } else {
                                Navigator.pop(context);
                              }
                            },
                            icon: Icon(Icons.cancel_outlined),
                            label: Text('Cancel'),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.grey.shade600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}