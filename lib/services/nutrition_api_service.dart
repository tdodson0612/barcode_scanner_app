// lib/services/nutrition_api_service.dart
// ✅ FIXED: More lenient search parameters for better results

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:liver_wise/config/app_config.dart';
import 'package:liver_wise/models/nutrition_info.dart';

class NutritionApiService {
  /// Base URL for product-by-barcode lookups.
  /// In AppConfig, this is typically:
  /// "https://world.openfoodfacts.org/api/v0/product"
  static String get _productBaseUrl => AppConfig.openFoodFactsUrl;

  /// Base URL for text search by product/food name.
  static const String _searchBaseUrl =
      'https://world.openfoodfacts.org/cgi/search.pl';

  /// Look up a single product by barcode.
  ///
  /// Returns `NutritionInfo` or `null` if not found / error.
  static Future<NutritionInfo?> fetchByBarcode(String barcode) async {
    if (barcode.trim().isEmpty) return null;

    final url = '$_productBaseUrl/$barcode.json';

    try {
      final response = await http
          .get(
            Uri.parse(url),
            headers: {'User-Agent': 'LiverWiseApp/1.0'},
          )
          .timeout(Duration(seconds: AppConfig.apiTimeoutSeconds));

      if (response.statusCode != 200) return null;

      final data = json.decode(response.body);
      if (data is! Map || data['status'] != 1) return null;

      // Reuse your existing NutritionInfo.fromJson shape:
      // expects { "product": { ... } }
      return NutritionInfo.fromJson(data as Map<String, dynamic>);
    } catch (e) {
      if (AppConfig.enableDebugPrints) {
        print('❌ fetchByBarcode error: $e');
      }
      return null;
    }
  }

  /// Search for products / foods by name.
  ///
  /// ✅ IMPROVED: More lenient search with better filtering
  /// Uses Open Food Facts free search endpoint.
  /// Returns a list of NutritionInfo (may be empty).
  static Future<List<NutritionInfo>> searchByName(
    String query, {
    int pageSize = 50, // 🔥 INCREASED from 20 to 50 for more results
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];

    try {
      // 🔥 NEW: Try multiple search strategies for better results
      final results = <NutritionInfo>[];
      final seenProducts = <String>{};

      // Strategy 1: Standard search
      final standardResults = await _performSearch(
        trimmed,
        pageSize: pageSize,
        useSimpleSearch: true,
      );

      for (final item in standardResults) {
        final key = item.productName.toLowerCase();
        if (!seenProducts.contains(key)) {
          seenProducts.add(key);
          results.add(item);
        }
      }

      // Strategy 2: If few results, try without simple search for more matches
      if (results.length < 5) {
        final advancedResults = await _performSearch(
          trimmed,
          pageSize: pageSize,
          useSimpleSearch: false,
        );

        for (final item in advancedResults) {
          final key = item.productName.toLowerCase();
          if (!seenProducts.contains(key)) {
            seenProducts.add(key);
            results.add(item);
          }
        }
      }

      // 🔥 NEW: Sort by relevance (exact matches first, then contains query)
      results.sort((a, b) {
        final aName = a.productName.toLowerCase();
        final bName = b.productName.toLowerCase();
        final queryLower = trimmed.toLowerCase();

        // Exact match gets highest priority
        final aExact = aName == queryLower;
        final bExact = bName == queryLower;
        if (aExact && !bExact) return -1;
        if (!aExact && bExact) return 1;

        // Starts with query gets second priority
        final aStarts = aName.startsWith(queryLower);
        final bStarts = bName.startsWith(queryLower);
        if (aStarts && !bStarts) return -1;
        if (!aStarts && bStarts) return 1;

        // Contains query gets third priority
        final aContains = aName.contains(queryLower);
        final bContains = bName.contains(queryLower);
        if (aContains && !bContains) return -1;
        if (!aContains && bContains) return 1;

        // Finally sort alphabetically
        return aName.compareTo(bName);
      });

      if (AppConfig.enableDebugPrints) {
        print('✅ searchByName: found ${results.length} results for "$trimmed"');
      }

      return results;
    } catch (e) {
      if (AppConfig.enableDebugPrints) {
        print('❌ searchByName error: $e');
      }
      return [];
    }
  }

  /// Internal helper to perform a single search query
  static Future<List<NutritionInfo>> _performSearch(
    String query, {
    required int pageSize,
    required bool useSimpleSearch,
  }) async {
    try {
      final queryParams = <String, String>{
        'search_terms': query,
        'action': 'process',
        'json': '1',
        'page_size': pageSize.toString(),
        'fields': 'product_name,nutriments,brands,categories', // 🔥 Request specific fields
      };

      if (useSimpleSearch) {
        queryParams['search_simple'] = '1';
      }

      final uri = Uri.parse(_searchBaseUrl).replace(
        queryParameters: queryParams,
      );

      final response = await http
          .get(
            uri,
            headers: {'User-Agent': 'LiverWiseApp/1.0'},
          )
          .timeout(Duration(seconds: AppConfig.apiTimeoutSeconds));

      if (response.statusCode != 200) return [];

      final data = json.decode(response.body);
      if (data is! Map) return [];

      final products = (data['products'] as List?) ?? [];
      final List<NutritionInfo> results = [];

      for (final item in products) {
        if (item is! Map<String, dynamic>) continue;

        // Wrap to match NutritionInfo.fromJson expected shape:
        final wrapped = <String, dynamic>{'product': item};

        try {
          final info = NutritionInfo.fromJson(wrapped);

          // 🔥 IMPROVED: More lenient filtering
          // Accept items with ANY nutrition data OR valid product name
          final hasValidName = info.productName.isNotEmpty &&
              info.productName.toLowerCase() != 'unknown product';

          final hasAnyData = info.calories > 0 ||
              info.fat > 0 ||
              info.sugar > 0 ||
              info.sodium > 0;

          // 🔥 NEW: Even accept zero-nutrition items if they have a valid name
          // (better to show "no data" than to hide valid products)
          if (hasValidName || hasAnyData) {
            results.add(info);
          }
        } catch (e) {
          // Skip items that fail to parse
          if (AppConfig.enableDebugPrints) {
            print('⚠️ Failed to parse product: $e');
          }
          continue;
        }
      }

      return results;
    } catch (e) {
      if (AppConfig.enableDebugPrints) {
        print('❌ _performSearch error: $e');
      }
      return [];
    }
  }
}