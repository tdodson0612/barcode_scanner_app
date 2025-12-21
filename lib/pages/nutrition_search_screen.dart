// lib/pages/nutrition_search_screen.dart
// Fixed version with proper item selection handling

import 'package:flutter/material.dart';
import 'package:liver_wise/models/nutrition_info.dart';
import 'package:liver_wise/services/nutrition_api_service.dart';
import 'package:liver_wise/widgets/nutrition_display.dart';
import 'package:liver_wise/services/error_handling_service.dart';
import 'package:liver_wise/services/search_history_service.dart';
import 'package:liver_wise/liverhealthbar.dart';

class NutritionSearchScreen extends StatefulWidget {
  const NutritionSearchScreen({super.key});

  @override
  State<NutritionSearchScreen> createState() => _NutritionSearchScreenState();
}

class _NutritionSearchScreenState extends State<NutritionSearchScreen> {
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = false;
  List<NutritionInfo> _results = [];
  NutritionInfo? _selectedItem;

  List<String> _searchHistory = [];

  static const String disclaimer =
      "These are average nutritional values and may vary depending on brand or source. "
      "For more accurate details, try scanning the barcode.";

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final history = await SearchHistoryService.loadHistory();
    setState(() => _searchHistory = history);
  }

  Future<void> _performSearch() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      ErrorHandlingService.showSimpleError(
        context,
        "Enter a food name to search.",
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _results = [];
      _selectedItem = null; // Clear any previous selection
    });

    try {
      // Save search history
      await SearchHistoryService.addToHistory(query);
      await _loadHistory();

      // Call API
      final items = await NutritionApiService.searchByName(query);

      if (items.isEmpty) {
        ErrorHandlingService.showSimpleError(
          context,
          "No results found.",
        );
      }

      setState(() => _results = items);
    } catch (e) {
      ErrorHandlingService.handleError(
        context: context,
        error: e,
        customMessage: "Error searching for food.",
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _selectItem(NutritionInfo item) {
    setState(() {
      _selectedItem = item;
    });
    
    // Scroll to show the nutrition display
    // Small delay to ensure the widget is built first
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        Scrollable.ensureVisible(
          context,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedItem = null;
    });
  }

  Widget _buildHistorySection() {
    if (_searchHistory.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Recent Searches",
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _searchHistory.map((term) {
            return ActionChip(
              label: Text(term),
              onPressed: () {
                _searchController.text = term;
                _performSearch();
              },
            );
          }).toList(),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildResultsList() {
    if (_results.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              "Results:",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (_selectedItem != null)
              TextButton.icon(
                onPressed: _clearSelection,
                icon: const Icon(Icons.close, size: 18),
                label: const Text("Clear Selection"),
              ),
          ],
        ),
        const SizedBox(height: 12),
        ..._results.map((item) {
          final isSelected = _selectedItem?.productName == item.productName;
          
          return Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: isSelected
                  ? const BorderSide(color: Colors.green, width: 2)
                  : BorderSide.none,
            ),
            color: isSelected ? Colors.green.shade50 : null,
            child: ListTile(
              title: Text(
                item.productName,
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              subtitle: isSelected
                  ? const Text(
                      "Selected - View details below",
                      style: TextStyle(
                        color: Colors.green,
                        fontSize: 12,
                      ),
                    )
                  : null,
              trailing: Icon(
                isSelected ? Icons.check_circle : Icons.chevron_right,
                color: isSelected ? Colors.green : null,
              ),
              onTap: () => _selectItem(item),
            ),
          );
        }),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Search Nutrition"),
        backgroundColor: Colors.green,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // SEARCH BAR
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: "Search food name",
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                prefixIcon: const Icon(Icons.search),
              ),
              onSubmitted: (_) => _performSearch(),
            ),

            const SizedBox(height: 16),

            // SEARCH BUTTON
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _performSearch,
                icon: const Icon(Icons.search),
                label: Text(
                  _isLoading ? "Searching..." : "Search",
                  style: const TextStyle(fontSize: 18),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // LOADING INDICATOR
            if (_isLoading)
              const Center(child: CircularProgressIndicator()),

            // SEARCH HISTORY
            if (!_isLoading) _buildHistorySection(),

            // RESULTS LIST
            if (!_isLoading) _buildResultsList(),

            const SizedBox(height: 20),

            // SELECTED NUTRITION DISPLAY
            if (_selectedItem != null) ...[
              const Divider(thickness: 2),
              const SizedBox(height: 12),
              const Text(
                "Nutrition Information",
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              NutritionDisplay(
                nutrition: _selectedItem!,
                liverScore: LiverHealthCalculator.calculate(
                  fat: _selectedItem!.fat,
                  sodium: _selectedItem!.sodium,
                  sugar: _selectedItem!.sugar,
                  calories: _selectedItem!.calories,
                ),
                disclaimer: disclaimer,
              ),
            ],
          ],
        ),
      ),
    );
  }
}