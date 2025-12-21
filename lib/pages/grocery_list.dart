// lib/pages/grocery_list.dart - COMPLETE UPDATED VERSION
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

import '../services/auth_service.dart';
import '../services/grocery_service.dart';
import '../models/grocery_item.dart';
import '../services/error_handling_service.dart';

class GroceryListPage extends StatefulWidget {
  final String? initialItem;
  
  const GroceryListPage({super.key, this.initialItem});

  @override
  State<GroceryListPage> createState() => _GroceryListPageState();
}

class _GroceryListPageState extends State<GroceryListPage> {
  List<Map<String, TextEditingController>> itemControllers = [];
  bool isLoading = true;
  bool isSaving = false;

  // Cache configuration
  static const Duration _listCacheDuration = Duration(minutes: 5);

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
      AuthService.ensureUserAuthenticated();
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
        // Remove last empty row if exists
        if (itemControllers.isNotEmpty && 
            itemControllers.last['name']!.text.isEmpty) {
          itemControllers.last['name']!.dispose();
          itemControllers.last['quantity']!.dispose();
          itemControllers.last['measurement']!.dispose();
          itemControllers.removeLast();
        }
        
        // Parse the scanned item to extract quantity, measurement, and name
        final parsed = _parseItemText(item);
        
        itemControllers.add({
          'quantity': TextEditingController(text: parsed['quantity']!.isEmpty ? '1' : parsed['quantity']),
          'measurement': TextEditingController(text: parsed['measurement']),
          'name': TextEditingController(text: parsed['name']),
        });
        
        // Add empty row for next item
        itemControllers.add({
          'quantity': TextEditingController(),
          'measurement': TextEditingController(),
          'name': TextEditingController(),
        });
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Added "$item" to grocery list'),
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

  Future<List<GroceryItem>?> _getCachedGroceryList() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString('grocery_list');
      
      if (cached == null) return null;
      
      final data = json.decode(cached);
      final timestamp = data['_cached_at'] as int?;
      
      if (timestamp == null) return null;
      
      final age = DateTime.now().millisecondsSinceEpoch - timestamp;
      if (age > _listCacheDuration.inMilliseconds) return null;
      
      final items = (data['items'] as List)
          .map((e) => GroceryItem.fromJson(e))
          .toList();
      
      print('📦 Using cached grocery list (${items.length} items)');
      return items;
    } catch (e) {
      print('⚠️ Error loading cached grocery list: $e');
      return null;
    }
  }

  Future<void> _cacheGroceryList(List<GroceryItem> items) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheData = {
        'items': items.map((item) => item.toJson()).toList(),
        '_cached_at': DateTime.now().millisecondsSinceEpoch,
      };
      await prefs.setString('grocery_list', json.encode(cacheData));
      print('💾 Cached ${items.length} grocery items');
    } catch (e) {
      print('⚠️ Error caching grocery list: $e');
    }
  }

  Future<void> _invalidateGroceryListCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('grocery_list');
      print('🗑️ Invalidated grocery list cache');
    } catch (e) {
      print('⚠️ Error invalidating grocery list cache: $e');
    }
  }

  // ========== PARSE ITEM TEXT INTO 3 PARTS ==========
  Map<String, String> _parseItemText(String itemText) {
    // Expected format: "1 lb Ground Turkey" or "1 x Ground Turkey" or just "Ground Turkey"
    String quantity = '';
    String measurement = '';
    String name = itemText;

    // Try to parse "quantity measurement name" format
    final parts = itemText.trim().split(RegExp(r'\s+'));
    
    if (parts.length >= 3) {
      // Check if first part is a number
      if (RegExp(r'^[\d.]+$').hasMatch(parts[0])) {
        quantity = parts[0];
        measurement = parts[1];
        name = parts.sublist(2).join(' ');
      }
    } else if (parts.length == 2) {
      // Check if format is "quantity x name" or "quantity name"
      if (parts[1].toLowerCase() == 'x' || RegExp(r'^[\d.]+$').hasMatch(parts[0])) {
        final quantityMatch = RegExp(r'^([\d.]+)\s*x?\s*(.+)$').firstMatch(itemText);
        if (quantityMatch != null) {
          quantity = quantityMatch.group(1) ?? '';
          name = quantityMatch.group(2) ?? itemText;
        }
      }
    }

    return {
      'quantity': quantity,
      'measurement': measurement,
      'name': name,
    };
  }

  // ========== LOAD FUNCTION WITH CACHING ==========
  Future<void> _loadGroceryList({bool forceRefresh = false}) async {
    try {
      // Try cache first unless force refresh
      if (!forceRefresh) {
        final cachedItems = await _getCachedGroceryList();
        
        if (cachedItems != null) {
          if (mounted) {
            setState(() {
              itemControllers = cachedItems.map((item) {
                final parsed = _parseItemText(item.item);
                
                return {
                  'quantity': TextEditingController(text: parsed['quantity']),
                  'measurement': TextEditingController(text: parsed['measurement']),
                  'name': TextEditingController(text: parsed['name']),
                };
              }).toList();
              
              if (itemControllers.isEmpty) {
                itemControllers.add({
                  'quantity': TextEditingController(),
                  'measurement': TextEditingController(),
                  'name': TextEditingController(),
                });
              }
              
              // Always add empty row at end
              itemControllers.add({
                'quantity': TextEditingController(),
                'measurement': TextEditingController(),
                'name': TextEditingController(),
              });
            });
          }
          return;
        }
      }

      // Cache miss or force refresh, fetch from service
      final List<GroceryItem> groceryItems = await GroceryService.getGroceryList();
      
      // Cache the results
      await _cacheGroceryList(groceryItems);
      
      if (mounted) {
        setState(() {
          itemControllers = groceryItems.map((item) {
            final parsed = _parseItemText(item.item);
            
            return {
              'quantity': TextEditingController(text: parsed['quantity']),
              'measurement': TextEditingController(text: parsed['measurement']),
              'name': TextEditingController(text: parsed['name']),
            };
          }).toList();
          
          if (itemControllers.isEmpty) {
            itemControllers.add({
              'quantity': TextEditingController(),
              'measurement': TextEditingController(),
              'name': TextEditingController(),
            });
          }
          
          // Always add empty row at end
          itemControllers.add({
            'quantity': TextEditingController(),
            'measurement': TextEditingController(),
            'name': TextEditingController(),
          });
        });
      }
    } catch (e) {
      if (mounted) {
        // Try to use stale cache on error
        final staleItems = await _getCachedGroceryList();
        if (staleItems != null) {
          setState(() {
            itemControllers = staleItems.map((item) {
              final parsed = _parseItemText(item.item);
              
              return {
                'quantity': TextEditingController(text: parsed['quantity']),
                'measurement': TextEditingController(text: parsed['measurement']),
                'name': TextEditingController(text: parsed['name']),
              };
            }).toList();
            
            if (itemControllers.isEmpty) {
              itemControllers.add({
                'quantity': TextEditingController(),
                'measurement': TextEditingController(),
                'name': TextEditingController(),
              });
            }
            
            itemControllers.add({
              'quantity': TextEditingController(),
              'measurement': TextEditingController(),
              'name': TextEditingController(),
            });
          });
          return;
        }

        setState(() {
          itemControllers = [{
            'quantity': TextEditingController(),
            'measurement': TextEditingController(),
            'name': TextEditingController(),
          }];
        });
        
        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          category: ErrorHandlingService.databaseError,
          customMessage: 'Error loading grocery list',
        );
      }
    }
  }

  @override
  void dispose() {
    for (var controllers in itemControllers) {
      controllers['name']!.dispose();
      controllers['quantity']!.dispose();
      controllers['measurement']!.dispose();
    }
    super.dispose();
  }

  void _addNewItem() {
    setState(() {
      itemControllers.add({
        'quantity': TextEditingController(),
        'measurement': TextEditingController(),
        'name': TextEditingController(),
      });
    });
  }

  void _removeItem(int index) {
    if (itemControllers.length > 1) {
      setState(() {
        itemControllers[index]['name']!.dispose();
        itemControllers[index]['quantity']!.dispose();
        itemControllers[index]['measurement']!.dispose();
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
            final measurement = controllers['measurement']!.text.trim();
            
            // Build item string: "quantity measurement name"
            List<String> parts = [];
            if (quantity.isNotEmpty) parts.add(quantity);
            if (measurement.isNotEmpty) parts.add(measurement);
            parts.add(name);
            
            return parts.join(' ');
          })
          .toList();
      
      if (items.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('⚠️ Add at least one item to save'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }
          
      // Save to database
      await GroceryService.saveGroceryList(items);
      
      // Invalidate old cache
      await _invalidateGroceryListCache();
      
      // Fetch fresh data from database to cache it properly
      final freshItems = await GroceryService.getGroceryList();
      await _cacheGroceryList(freshItems);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Saved ${items.length} item${items.length == 1 ? '' : 's'}!'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          category: ErrorHandlingService.databaseError,
          customMessage: 'Error saving grocery list',
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear Grocery List'),
        content: const Text('Are you sure you want to clear your entire grocery list?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      // Clear from database first
      await GroceryService.clearGroceryList();
      
      // Invalidate cache
      await _invalidateGroceryListCache();
      
      if (mounted) {
        // Dispose all existing controllers
        for (var controllers in itemControllers) {
          controllers['name']!.dispose();
          controllers['quantity']!.dispose();
          controllers['measurement']!.dispose();
        }
        
        // Reset to single empty row
        setState(() {
          itemControllers = [
            {
              'quantity': TextEditingController(),
              'measurement': TextEditingController(),
              'name': TextEditingController(),
            }
          ];
        });
        
        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🗑️ Grocery list cleared!'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          category: ErrorHandlingService.databaseError,
          customMessage: 'Error clearing grocery list',
        );
      }
    }
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
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              await _loadGroceryList(forceRefresh: true);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('🔄 Grocery list refreshed'),
                    backgroundColor: Colors.blue,
                    duration: Duration(seconds: 1),
                  ),
                );
              }
            },
            tooltip: 'Refresh',
          ),
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
                RefreshIndicator(
                  onRefresh: () => _loadGroceryList(forceRefresh: true),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        // Header
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
                              Expanded(
                                child: const Text(
                                  'My Grocery List',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black87,
                                  ),
                                ),
                              ),
                              // Item count badge
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.green.shade100,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: Colors.green.shade300,
                                    width: 1,
                                  ),
                                ),
                                child: Text(
                                  '${itemControllers.where((c) => c['name']!.text.trim().isNotEmpty).length} items',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green.shade700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        
                        // List
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white.withAlpha((0.9 * 255).toInt()),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: itemControllers.isEmpty
                                ? const Center(
                                    child: Text(
                                      'No items yet. Start adding groceries!',
                                      style: TextStyle(
                                        fontSize: 16,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  )
                                : ListView.builder(
                                    itemCount: itemControllers.length,
                                    itemBuilder: (context, index) {
                                      return Padding(
                                        padding: const EdgeInsets.only(bottom: 12),
                                        child: Row(
                                          children: [
                                            // Row number
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
                                            
                                            // Quantity field
                                            SizedBox(
                                              width: 50,
                                              child: TextField(
                                                controller: itemControllers[index]['quantity'],
                                                decoration: InputDecoration(
                                                  hintText: 'Qty',
                                                  hintStyle: const TextStyle(fontSize: 11),
                                                  border: OutlineInputBorder(
                                                    borderRadius: BorderRadius.circular(8),
                                                    borderSide: BorderSide(color: Colors.grey.shade300),
                                                  ),
                                                  focusedBorder: OutlineInputBorder(
                                                    borderRadius: BorderRadius.circular(8),
                                                    borderSide: const BorderSide(color: Colors.blue, width: 2),
                                                  ),
                                                  contentPadding: const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 8,
                                                  ),
                                                  filled: true,
                                                  fillColor: Colors.grey.shade50,
                                                ),
                                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                                inputFormatters: [
                                                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                                                ],
                                                style: const TextStyle(fontSize: 13),
                                                textAlign: TextAlign.center,
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            
                                            // Measurement field (lb, oz, kg, etc.)
                                            SizedBox(
                                              width: 55,
                                              child: TextField(
                                                controller: itemControllers[index]['measurement'],
                                                decoration: InputDecoration(
                                                  hintText: 'Unit',
                                                  hintStyle: const TextStyle(fontSize: 11),
                                                  border: OutlineInputBorder(
                                                    borderRadius: BorderRadius.circular(8),
                                                    borderSide: BorderSide(color: Colors.grey.shade300),
                                                  ),
                                                  focusedBorder: OutlineInputBorder(
                                                    borderRadius: BorderRadius.circular(8),
                                                    borderSide: const BorderSide(color: Colors.blue, width: 2),
                                                  ),
                                                  contentPadding: const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 8,
                                                  ),
                                                  filled: true,
                                                  fillColor: Colors.grey.shade50,
                                                ),
                                                style: const TextStyle(fontSize: 13),
                                                textAlign: TextAlign.center,
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            
                                            // Item name field
                                            Expanded(
                                              child: TextField(
                                                controller: itemControllers[index]['name'],
                                                decoration: InputDecoration(
                                                  hintText: 'Enter item name...',
                                                  border: OutlineInputBorder(
                                                    borderRadius: BorderRadius.circular(8),
                                                    borderSide: BorderSide(color: Colors.grey.shade300),
                                                  ),
                                                  focusedBorder: OutlineInputBorder(
                                                    borderRadius: BorderRadius.circular(8),
                                                    borderSide: const BorderSide(color: Colors.blue, width: 2),
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
                                                padding: const EdgeInsets.only(left: 6),
                                                child: IconButton(
                                                  icon: Icon(
                                                    Icons.remove_circle,
                                                    color: Colors.red.shade400,
                                                    size: 22,
                                                  ),
                                                  padding: EdgeInsets.zero,
                                                  constraints: const BoxConstraints(),
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
                        
                        // Buttons
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
                                      ? const SizedBox(
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
                ),
              ],
            ),
    );
  }
}