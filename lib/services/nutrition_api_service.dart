// lib/services/nutrition_api_service.dart
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
  /// Uses Open Food Facts free search endpoint.
  /// Returns a list of NutritionInfo (may be empty).
  static Future<List<NutritionInfo>> searchByName(
    String query, {
    int pageSize = 20,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];

    try {
      final uri = Uri.parse(_searchBaseUrl).replace(
        queryParameters: {
          'search_terms': trimmed,
          'search_simple': '1',
          'action': 'process',
          'json': '1',
          'page_size': pageSize.toString(),
        },
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

        final info = NutritionInfo.fromJson(wrapped);

        // Optional: skip items that have basically no nutrition data
        final hasAnyMacro = info.calories > 0 ||
            info.fat > 0 ||
            info.sugar > 0 ||
            info.sodium > 0;

        if (hasAnyMacro) {
          results.add(info);
        }
      }

      return results;
    } catch (e) {
      if (AppConfig.enableDebugPrints) {
        print('❌ searchByName error: $e');
      }
      return [];
    }
  }
}
