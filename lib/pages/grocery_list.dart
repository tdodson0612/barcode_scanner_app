import 'package:flutter/material.dart';
import '../services/database_service.dart';
import '../models/grocery_item.dart';

class GroceryListPage extends StatefulWidget {
  const GroceryListPage({super.key});

  @override
  State<GroceryListPage> createState() => _GroceryListPageState();
}

class _GroceryListPageState extends State<GroceryListPage> {
  List<TextEditingController> controllers = [];
  bool isLoading = true;
  bool isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadGroceryList();
  }

  Future<void> _loadGroceryList() async {
    try {
      // Use real database calls
      final List<GroceryItem> groceryItems = await DatabaseService.getGroceryList();
      setState(() {
        controllers = groceryItems.map((item) => 
          TextEditingController(text: item.item)).toList();
        
        // Add empty controllers if list is empty or add one more for new entries
        if (controllers.isEmpty) {
          controllers.add(TextEditingController());
        }
        controllers.add(TextEditingController()); // Always have one empty at the end
        
        isLoading = false;
      });
      
      // REMOVED: Temporary code that was overriding the real database calls
    } catch (e) {
      setState(() {
        isLoading = false;
        controllers = [TextEditingController()];
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading grocery list: $e')),
      );
    }
  }

  @override
  void dispose() {
    for (var controller in controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _addNewItem() {
    setState(() {
      controllers.add(TextEditingController());
    });
  }

  void _removeItem(int index) {
    if (controllers.length > 1) {
      setState(() {
        controllers[index].dispose();
        controllers.removeAt(index);
      });
    }
  }

  Future<void> _saveGroceryList() async {
    setState(() {
      isSaving = true;
    });

    try {
      List<String> items = controllers
          .map((controller) => controller.text.trim())
          .where((text) => text.isNotEmpty)
          .toList();

      // Use real database calls
      await DatabaseService.saveGroceryList(items);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Grocery list saved!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving grocery list: $e')),
      );
    } finally {
      setState(() {
        isSaving = false;
      });
    }
  }

  Future<void> _clearGroceryList() async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Clear Grocery List'),
        content: Text('Are you sure you want to clear your entire grocery list?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                // Use real database calls
                await DatabaseService.clearGroceryList();
                
                // Clear all controllers
                setState(() {
                  for (var controller in controllers) {
                    controller.dispose();
                  }
                  controllers = [TextEditingController()];
                });
                
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Grocery list cleared!'),
                    backgroundColor: Colors.orange,
                  ),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error clearing grocery list: $e')),
                );
              }
            },
            child: Text('Clear'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('My Grocery List'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(Icons.delete_outline),
            onPressed: _clearGroceryList,
            tooltip: 'Clear List',
          ),
        ],
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
          isLoading
              ? Center(child: CircularProgressIndicator())
              : Padding(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    children: [
                      // Title Section
                      Container(
                        padding: EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha((0.9 * 255).toInt()),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.shopping_cart,
                              size: 28,
                              color: Colors.green,
                            ),
                            SizedBox(width: 12),
                            Text(
                              'My Grocery List',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      SizedBox(height: 16),
                      
                      // List Items
                      Expanded(
                        child: Container(
                          padding: EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white.withAlpha((0.9 * 255).toInt()),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Column(
                            children: [
                              Expanded(
                                child: ListView.builder(
                                  itemCount: controllers.length,
                                  itemBuilder: (context, index) {
                                    return Padding(
                                      padding: EdgeInsets.only(bottom: 12),
                                      child: Row(
                                        children: [
                                          // Number
                                          Container(
                                            width: 35,
                                            height: 35,
                                            decoration: BoxDecoration(
                                              color: Colors.blue.shade100,
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                color: Colors.blue.shade300,
                                                width: 1,
                                              ),
                                            ),
                                            child: Center(
                                              child: Text(
                                                '${index + 1}',
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.blue.shade700,
                                                ),
                                              ),
                                            ),
                                          ),
                                          SizedBox(width: 12),
                                          
                                          // Text Field
                                          Expanded(
                                            child: TextField(
                                              controller: controllers[index],
                                              decoration: InputDecoration(
                                                hintText: 'Enter grocery item...',
                                                border: OutlineInputBorder(
                                                  borderRadius: BorderRadius.circular(8),
                                                  borderSide: BorderSide(color: Colors.grey.shade300),
                                                ),
                                                focusedBorder: OutlineInputBorder(
                                                  borderRadius: BorderRadius.circular(8),
                                                  borderSide: BorderSide(color: Colors.blue, width: 2),
                                                ),
                                                contentPadding: EdgeInsets.symmetric(
                                                  horizontal: 12,
                                                  vertical: 8,
                                                ),
                                                filled: true,
                                                fillColor: Colors.grey.shade50,
                                              ),
                                              onChanged: (text) {
                                                // Add a new empty field if this is the last one and has text
                                                if (index == controllers.length - 1 && text.isNotEmpty) {
                                                  _addNewItem();
                                                }
                                              },
                                            ),
                                          ),
                                          
                                          // Remove Button
                                          if (controllers.length > 1)
                                            Padding(
                                              padding: EdgeInsets.only(left: 8),
                                              child: IconButton(
                                                icon: Icon(
                                                  Icons.remove_circle,
                                                  color: Colors.red.shade400,
                                                ),
                                                onPressed: () => _removeItem(index),
                                                tooltip: 'Remove item',
                                              ),
                                            ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      
                      SizedBox(height: 16),
                      
                      // Action Buttons
                      Container(
                        padding: EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha((0.9 * 255).toInt()),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          children: [
                            // Save Button
                            SizedBox(
                              width: double.infinity,
                              height: 48,
                              child: ElevatedButton.icon(
                                onPressed: isSaving ? null : _saveGroceryList,
                                icon: isSaving 
                                    ? SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                        ),
                                      )
                                    : Icon(Icons.save),
                                label: Text(
                                  isSaving ? 'Saving...' : 'Save Grocery List',
                                  style: TextStyle(fontSize: 16),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                            ),
                            
                            SizedBox(height: 12),
                            
                            // Add Item Button
                            SizedBox(
                              width: double.infinity,
                              height: 48,
                              child: ElevatedButton.icon(
                                onPressed: _addNewItem,
                                icon: Icon(Icons.add),
                                label: Text(
                                  'Add New Item',
                                  style: TextStyle(fontSize: 16),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                            ),
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