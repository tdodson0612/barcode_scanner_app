// lib/services/food_classifier_service.dart
// PATCHED FOR LORA INTEGRATION
//
// Changes from original:
//   1. LoraInferenceService.tryClassifyWord() inserted as FIRST step
//      in isWordFood() — before _tryGroq(), _tryGemini(), _tryOllama().
//      When LoRA is disabled (_loraEnabled = false), tryClassifyWord()
//      returns null immediately and falls through to existing Groq chain.
//      ZERO behavior change until LoRA is explicitly enabled.
//
//   2. IngredientMatrix.isKnownFood() replaces the _knownFoodWords set
//      fast-path check, giving structured liver metadata alongside classification.
//      The _knownFoodWords set is kept as fallback for backward compatibility.
//
// All other logic unchanged. Original comments preserved.

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
// LORA_INTEGRATION_POINT: New imports
import 'package:liver_wise/services/lora_inference_service.dart';
import 'package:liver_wise/models/ingredient_matrix_entry.dart';

class FoodClassifierService {
  static String get _groqApiKey => dotenv.env['GROQ_API_KEY'] ?? '';
  static String get _geminiApiKey => dotenv.env['GEMINI_API_KEY'] ?? '';
  static String get _ollamaEndpoint =>
      dotenv.env['OLLAMA_ENDPOINT'] ?? 'http://localhost:11434';

  static const String _cacheKey = 'food_classification_cache';
  static const int _cacheExpiryDays = 30;

  // Original hardcoded sets — kept for backward compat
  static final Set<String> _knownNonFoodWords = {
    'oz', 'ounce', 'ounces', 'lb', 'lbs', 'pound', 'pounds',
    'kg', 'kilogram', 'kilograms', 'gram', 'grams', 'g', 'ml',
    'milliliter', 'milliliters', 'liter', 'liters', 'l', 'gallon',
    'gallons', 'quart', 'quarts', 'pint', 'pints', 'cup', 'cups',
    'tbsp', 'tsp', 'tablespoon', 'tablespoons', 'teaspoon', 'teaspoons',
    'fl', 'fluid', 'can', 'canned', 'jar', 'bottle', 'bottled', 'box',
    'boxed', 'bag', 'bagged', 'pack', 'package', 'packaged', 'carton',
    'container', 'pouch', 'tube', 'tin', 'organic', 'natural', 'fresh',
    'frozen', 'dried', 'raw', 'cooked', 'prepared', 'whole', 'sliced',
    'diced', 'chopped', 'minced', 'crushed', 'ground', 'reduced', 'low',
    'high', 'fat', 'free', 'sodium', 'sugar', 'calorie', 'diet', 'light',
    'lite', 'extra', 'pure', 'premium', 'grade', 'quality', 'red',
    'green', 'yellow', 'white', 'black', 'brown', 'blue', 'style',
    'flavored', 'flavour', 'seasoned', 'unseasoned', 'salted', 'unsalted',
    'sweetened', 'unsweetened', 'plain', 'original', 'peeled', 'unpeeled',
    'pitted', 'unpitted', 'seeded', 'unseeded', 'bone-in', 'boneless',
    'skin-on', 'skinless', 'roasted', 'the', 'a', 'an', 'great', 'value',
    'brand', 'best', 'choice', 'select', 'market', 'store',
  };

  static final Set<String> _knownFoodWords = {
    'apple', 'banana', 'orange', 'tomato', 'tomatoes', 'potato',
    'potatoes', 'chicken', 'beef', 'pork', 'fish', 'salmon', 'tuna',
    'shrimp', 'cheese', 'milk', 'butter', 'yogurt', 'egg', 'eggs',
    'bread', 'rice', 'pasta', 'noodles', 'cereal', 'carrot', 'carrots',
    'broccoli', 'spinach', 'lettuce', 'onion', 'onions', 'garlic',
    'pepper', 'peppers', 'flour', 'sugar', 'salt', 'oil', 'vinegar',
    'wheat', 'corn', 'beans', 'peas', 'lentils',
  };

  // ── Main classification method ─────────────────────────────────────────
  static Future<List<String>> extractFoodWords(String productName) async {
    if (productName.trim().isEmpty) return [];

    String processed = productName.toLowerCase().trim();
    processed = processed.replaceAll(RegExp(r'[^\w\s-]'), ' ');
    List<String> words = processed
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty && word.length > 2)
        .toList();

    List<String> foodWords = [];
    for (String word in words) {
      bool isFood = await isWordFood(word);
      if (isFood) foodWords.add(word);
    }
    return foodWords;
  }

  // ── LORA_INTEGRATION_POINT: LoRA inserted as step 0 ────────────────────
  // Fallback chain:  LoRA (Model C) → Groq → Gemini → Ollama → false
  // When _loraEnabled = false:  tryClassifyWord() returns null instantly,
  // no latency penalty, existing behavior preserved exactly.
  static Future<bool> isWordFood(String word) async {
    word = word.toLowerCase().trim();

    // Step 1: Fast local non-food check (unchanged)
    if (_knownNonFoodWords.contains(word)) return false;

    // Step 2: LORA_INTEGRATION_POINT — IngredientMatrix fast-path
    // Replaces original _knownFoodWords check with structured matrix lookup.
    // Falls back to _knownFoodWords set for words not yet in the matrix.
    if (IngredientMatrix.isKnownFood(word)) return true;
    if (_knownFoodWords.contains(word)) return true;
    if (word.length <= 2) return false;

    // Step 3: Cache check (unchanged)
    final cachedResult = await _getCachedResult(word);
    if (cachedResult != null) return cachedResult;

    // ── LORA_INTEGRATION_POINT: LoRA Model C — step 0 in LLM chain ─────
    // Insert BEFORE _tryGroq(). tryClassifyWord() returns null when disabled.
    bool? result;

    result = await LoraInferenceService.tryClassifyWord(word);
    if (result != null) {
      await _cacheResult(word, result);
      return result;
    }
    // ── End LoRA insert ──────────────────────────────────────────────────

    // Existing chain: Groq → Gemini → Ollama (unchanged)
    result = await _tryGroq(word);
    if (result != null) {
      await _cacheResult(word, result);
      return result;
    }

    result = await _tryGemini(word);
    if (result != null) {
      await _cacheResult(word, result);
      return result;
    }

    result = await _tryOllama(word);
    if (result != null) {
      await _cacheResult(word, result);
      return result;
    }

    print('⚠️ All LLM APIs failed for word: $word');
    return false;
  }

  // ── Groq (unchanged) ────────────────────────────────────────────────────
  static Future<bool?> _tryGroq(String word) async {
    try {
      print('🟢 Trying Groq for: $word');
      final response = await http.post(
        Uri.parse('https://api.groq.com/openai/v1/chat/completions'),
        headers: {
          'Authorization': 'Bearer $_groqApiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': 'llama-3.3-70b-versatile',
          'messages': [
            {
              'role': 'system',
              'content':
                  'You are a food classifier. Only respond with "yes" or "no". '
                  'Answer whether the word is a food item, ingredient, or edible product.'
            },
            {'role': 'user', 'content': 'Is "$word" a food?'}
          ],
          'max_tokens': 5,
          'temperature': 0,
        }),
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final answer = data['choices'][0]['message']['content']
            .toLowerCase()
            .trim();
        final isFood = answer.contains('yes');
        print('✅ Groq result for "$word": $isFood');
        return isFood;
      } else if (response.statusCode == 429) {
        print('⚠️ Groq rate limit reached');
        return null;
      } else {
        print('⚠️ Groq error: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('⚠️ Groq exception: $e');
      return null;
    }
  }

  // ── Gemini (unchanged) ───────────────────────────────────────────────────
  static Future<bool?> _tryGemini(String word) async {
    try {
      print('🔵 Trying Gemini for: $word');
      final response = await http.post(
        Uri.parse(
            'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=$_geminiApiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [
            {
              'parts': [
                {
                  'text':
                      'Answer only "yes" or "no": Is "$word" a food, ingredient, or edible product?'
                }
              ]
            }
          ],
          'generationConfig': {'maxOutputTokens': 5, 'temperature': 0}
        }),
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final answer =
            data['candidates'][0]['content']['parts'][0]['text']
                .toLowerCase()
                .trim();
        final isFood = answer.contains('yes');
        print('✅ Gemini result for "$word": $isFood');
        return isFood;
      } else if (response.statusCode == 429) {
        print('⚠️ Gemini rate limit reached');
        return null;
      } else {
        print('⚠️ Gemini error: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('⚠️ Gemini exception: $e');
      return null;
    }
  }

  // ── Ollama (unchanged) ───────────────────────────────────────────────────
  static Future<bool?> _tryOllama(String word) async {
    try {
      print('🟣 Trying Ollama for: $word');
      final response = await http.post(
        Uri.parse('$_ollamaEndpoint/v1/chat/completions'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'model': 'llama3.2:1b',
          'messages': [
            {
              'role': 'system',
              'content':
                  'You are a food classifier. Only respond with "yes" or "no".'
            },
            {'role': 'user', 'content': 'Is "$word" a food?'}
          ],
          'max_tokens': 5,
          'temperature': 0,
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final answer = data['choices'][0]['message']['content']
            .toLowerCase()
            .trim();
        final isFood = answer.contains('yes');
        print('✅ Ollama result for "$word": $isFood');
        return isFood;
      } else {
        print('⚠️ Ollama error: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('⚠️ Ollama exception: $e');
      return null;
    }
  }

  // ── Cache (unchanged) ─────────────────────────────────────────────────────
  static Future<bool?> _getCachedResult(String word) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheJson = prefs.getString(_cacheKey);
      if (cacheJson == null) return null;

      final cache = jsonDecode(cacheJson) as Map<String, dynamic>;
      final entry = cache[word];
      if (entry == null) return null;

      final timestamp = DateTime.parse(entry['timestamp']);
      final expiryDate =
          timestamp.add(Duration(days: _cacheExpiryDays));
      if (DateTime.now().isAfter(expiryDate)) return null;

      print('💾 Cache hit for: $word');
      return entry['isFood'] as bool;
    } catch (e) {
      print('⚠️ Cache read error: $e');
      return null;
    }
  }

  static Future<void> _cacheResult(String word, bool isFood) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheJson = prefs.getString(_cacheKey);
      Map<String, dynamic> cache = {};
      if (cacheJson != null) {
        cache = jsonDecode(cacheJson) as Map<String, dynamic>;
      }
      cache[word] = {
        'isFood': isFood,
        'timestamp': DateTime.now().toIso8601String(),
      };
      await prefs.setString(_cacheKey, jsonEncode(cache));
      print('💾 Cached result for: $word = $isFood');
    } catch (e) {
      print('⚠️ Cache write error: $e');
    }
  }

  static Future<void> clearCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cacheKey);
    print('🗑️ Cache cleared');
  }

  static Future<Map<String, dynamic>> getCacheStats() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheJson = prefs.getString(_cacheKey);
      if (cacheJson == null) {
        return {'totalEntries': 0, 'foodWords': 0, 'nonFoodWords': 0};
      }
      final cache = jsonDecode(cacheJson) as Map<String, dynamic>;
      int foodCount = 0, nonFoodCount = 0;
      cache.forEach((key, value) {
        if (value['isFood'] == true) {
          foodCount++;
        } else {
          nonFoodCount++;
        }
      });
      return {
        'totalEntries': cache.length,
        'foodWords': foodCount,
        'nonFoodWords': nonFoodCount,
        // LORA_INTEGRATION_POINT: add matrix coverage stat
        'matrixEntries': IngredientMatrix.entries.length,
        'loraEnabled': LoraInferenceService.isLoraEnabled,
      };
    } catch (e) {
      return {'error': e.toString()};
    }
  }
}