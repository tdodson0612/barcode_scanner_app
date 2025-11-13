// lib/pages/grocery_list_page.dart - ENHANCED: Added quantity field for each item
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/database_service.dart';
import '../models/grocery_item.dart';

class GroceryListPage extends StatefulWidget {
  final String? initialItem;
  
  const GroceryListPage({super.key, this.initialItem});

  @override
  State<GroceryListPage> createState() => _GroceryListPageState();
}

class _GroceryListPageState extends State<GroceryListPage> {
  // Changed to store both item name and quantity
  List<Map<String, TextEditingController>> itemControllers = [];
  bool isLoading = true;
  bool isSaving = false;

  @override
  void initState() {
    super.initState();
    _initializeUser();
  }

  Future<void> _initializeUser() async {
    setState(() {
      isLoading = true;
    });

    try {
      DatabaseService.ensureUserAuthenticated();
      await _loadGroceryList();
      
      if (widget.initialItem != null && widget.initialItem!.isNotEmpty) {
        _addScannedItem(widget.initialItem!);
      }
    } catch (e) {
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/login');
      }
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  void _addScannedItem(String item) {
    if (mounted) {
      setState(() {
        // Remove the last empty controller pair if it exists
        if (itemControllers.isNotEmpty && 
            itemControllers.last['name']!.text.isEmpty) {
          itemControllers.last['name']!.dispose();
          itemControllers.last['quantity']!.dispose();
          itemControllers.removeLast();
        }
        
        // Add the scanned item with quantity 1
        itemControllers.add({
          'name': TextEditingController(text: item),
          'quantity': TextEditingController(text: '1'),
        });
        
        // Add new empty controller pair at the end
        itemControllers.add({
          'name': TextEditingController(),
          'quantity': TextEditingController(),
        });
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Added "$item" to grocery list'),
          backgroundColor: Colors.green,
          action: SnackBarAction(
            label: 'Save',
            textColor: Colors.white,
            onPressed: _saveGroceryList,
          ),
        ),
      );
    }
  }

  Future<void> _loadGroceryList() async {
    try {
      final List<GroceryItem> groceryItems = await DatabaseService.getGroceryList();
      if (mounted) {
        setState(() {
          itemControllers = groceryItems.map((item) {
            // Parse quantity from item text (format: "quantity x item" or just "item")
            final parts = item.item.split(' x ');
            String itemName;
            String quantity;
            
            if (parts.length == 2) {
              quantity = parts[0];
              itemName = parts[1];
            } else {
              quantity = '';
              itemName = item.item;
            }
            
            return {
              'name': TextEditingController(text: itemName),
              'quantity': TextEditingController(text: quantity),
            };
          }).toList();
          
          if (itemControllers.isEmpty) {
            itemControllers.add({
              'name': TextEditingController(),
              'quantity': TextEditingController(),
            });
          }
          
          itemControllers.add({
            'name': TextEditingController(),
            'quantity': TextEditingController(),
          });
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          itemControllers = [{
            'name': TextEditingController(),
            'quantity': TextEditingController(),
          }];
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading grocery list: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    for (var controllers in itemControllers) {
      controllers['name']!.dispose();
      controllers['quantity']!.dispose();
    }
    super.dispose();
  }

  void _addNewItem() {
    setState(() {
      itemControllers.add({
        'name': TextEditingController(),
        'quantity': TextEditingController(),
      });
    });
  }

  void _removeItem(int index) {
    if (itemControllers.length > 1) {
      setState(() {
        itemControllers[index]['name']!.dispose();
        itemControllers[index]['quantity']!.dispose();
        itemControllers.removeAt(index);
      });
    }
  }

  Future<void> _saveGroceryList() async {
    setState(() {
      isSaving = true;
    });
    try {
      List<String> items = itemControllers
          .where((controllers) => controllers['name']!.text.trim().isNotEmpty)
          .map((controllers) {
            final name = controllers['name']!.text.trim();
            final quantity = controllers['quantity']!.text.trim();
            
            // Format: "quantity x item" or just "item" if no quantity
            if (quantity.isNotEmpty) {
              return '$quantity x $name';
            } else {
              return name;
            }
          })
          .toList();
          
      await DatabaseService.saveGroceryList(items);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Grocery list saved!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving grocery list: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          isSaving = false;
        });
      }
    }
  }

  Future<void> _clearGroceryList() async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Grocery List'),
        content: const Text('Are you sure you want to clear your entire grocery list?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await DatabaseService.clearGroceryList();
                if (mounted) {
                  setState(() {
                    for (var controllers in itemControllers) {
                      controllers['name']!.dispose();
                      controllers['quantity']!.dispose();
                    }
                    itemControllers = [{
                      'name': TextEditingController(),
                      'quantity': TextEditingController(),
                    }];
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Grocery list cleared!'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error clearing grocery list: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Grocery List'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: _clearGroceryList,
            tooltip: 'Clear List',
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                Positioned.fill(
                  child: Image.asset(
                    'assets/background.png',
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(color: Colors.grey[100]);
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
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
                            const SizedBox(width: 12),
                            const Text(
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
                      const SizedBox(height: 16),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white.withAlpha((0.9 * 255).toInt()),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: ListView.builder(
                            itemCount: itemControllers.length,
                            itemBuilder: (context, index) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Row(
                                  children: [
                                    // Item number
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
                                    const SizedBox(width: 12),
                                    
                                    // Quantity field (small)
                                    SizedBox(
                                      width: 60,
                                      child: TextField(
                                        controller: itemControllers[index]['quantity'],
                                        decoration: InputDecoration(
                                          hintText: 'Qty',
                                          hintStyle: TextStyle(fontSize: 12),
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(8),
                                            borderSide: BorderSide(color: Colors.grey.shade300),
                                          ),
                                          focusedBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(8),
                                            borderSide: BorderSide(color: Colors.blue, width: 2),
                                          ),
                                          contentPadding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 8,
                                          ),
                                          filled: true,
                                          fillColor: Colors.grey.shade50,
                                        ),
                                        keyboardType: TextInputType.number,
                                        inputFormatters: [
                                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                                        ],
                                        style: TextStyle(fontSize: 14),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    
                                    // Item name field (expanded)
                                    Expanded(
                                      child: TextField(
                                        controller: itemControllers[index]['name'],
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
                                          contentPadding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 8,
                                          ),
                                          filled: true,
                                          fillColor: Colors.grey.shade50,
                                        ),
                                        onChanged: (text) {
                                          if (index == itemControllers.length - 1 && text.isNotEmpty) {
                                            _addNewItem();
                                          }
                                        },
                                      ),
                                    ),
                                    
                                    // Remove button
                                    if (itemControllers.length > 1)
                                      Padding(
                                        padding: const EdgeInsets.only(left: 8),
                                        child: IconButton(
                                          icon: Icon(
                                            Icons.remove_circle,
                                            color: Colors.red.shade400,
                                          ),
                                          onPressed: () => _removeItem(index),
                                        ),
                                      ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha((0.9 * 255).toInt()),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          children: [
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
                                    : const Icon(Icons.save),
                                label: Text(isSaving ? 'Saving...' : 'Save Grocery List'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              height: 48,
                              child: ElevatedButton.icon(
                                onPressed: _addNewItem,
                                icon: const Icon(Icons.add),
                                label: const Text('Add New Item'),
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