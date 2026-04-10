// lib/models/ingredient_matrix_entry.dart
// Formalized ingredient matrix for LoRA training dataset.
// Replaces / extends the hardcoded _knownFoodWords / _knownNonFoodWords sets
// in FoodClassifierService with structured, liver-aware metadata.
//
// LORA_INTEGRATION_POINT: This matrix is the ground-truth source for
// Model C (food classifier) training data AND informs Model A (recipe
// generator) about which ingredients to prefer / avoid per disease type.

class IngredientMatrixEntry {
  final String name; // lowercase, canonical form
  final List<String> aliases; // other common names / spellings
  final IngredientCategory category;
  final LiverImpact liverImpact;
  final List<String> liverFlags; // e.g. ["high_omega3", "high_fiber"]
  final List<String> typicalMeasurements; // from IngredientRow measurements list
  final List<String> avoidFor; // disease type strings
  final List<String> preferredFor; // disease type strings
  final double? sodiumMgPer100g; // for compliance pre-check
  final double? sugarGPer100g;
  final double? fatGPer100g;

  const IngredientMatrixEntry({
    required this.name,
    this.aliases = const [],
    required this.category,
    required this.liverImpact,
    this.liverFlags = const [],
    this.typicalMeasurements = const ['cup', 'oz', 'g'],
    this.avoidFor = const [],
    this.preferredFor = const [],
    this.sodiumMgPer100g,
    this.sugarGPer100g,
    this.fatGPer100g,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'aliases': aliases,
        'category': category.name,
        'liver_impact': liverImpact.name,
        'liver_flags': liverFlags,
        'typical_measurements': typicalMeasurements,
        'avoid_for': avoidFor,
        'preferred_for': preferredFor,
        if (sodiumMgPer100g != null) 'sodium_mg_per_100g': sodiumMgPer100g,
        if (sugarGPer100g != null) 'sugar_g_per_100g': sugarGPer100g,
        if (fatGPer100g != null) 'fat_g_per_100g': fatGPer100g,
      };

  factory IngredientMatrixEntry.fromJson(Map<String, dynamic> json) =>
      IngredientMatrixEntry(
        name: json['name'] as String,
        aliases: (json['aliases'] as List?)?.cast<String>() ?? [],
        category:
            IngredientCategory.values.byName(json['category'] as String),
        liverImpact:
            LiverImpact.values.byName(json['liver_impact'] as String),
        liverFlags: (json['liver_flags'] as List?)?.cast<String>() ?? [],
        typicalMeasurements:
            (json['typical_measurements'] as List?)?.cast<String>() ??
                ['cup', 'oz', 'g'],
        avoidFor: (json['avoid_for'] as List?)?.cast<String>() ?? [],
        preferredFor:
            (json['preferred_for'] as List?)?.cast<String>() ?? [],
        sodiumMgPer100g:
            (json['sodium_mg_per_100g'] as num?)?.toDouble(),
        sugarGPer100g: (json['sugar_g_per_100g'] as num?)?.toDouble(),
        fatGPer100g: (json['fat_g_per_100g'] as num?)?.toDouble(),
      );
}

enum IngredientCategory {
  protein,
  vegetable,
  fruit,
  grain,
  dairy,
  legume,
  fat,
  spice,
  liquid,
  condiment,
  other,
}

enum LiverImpact {
  beneficial, // actively supports liver health
  neutral, // safe, no special benefit
  caution, // safe in moderation
  avoid, // should be avoided for liver conditions
}

// ─────────────────────────────────────────────
// MASTER INGREDIENT MATRIX
// Seeded from:
//   1. FoodClassifierService._knownFoodWords
//   2. SuggestedRecipesPage fallback recipe ingredients
//   3. LiverDashboardPage disease profiles
// Expand to 300+ entries before Phase 1C training
// ─────────────────────────────────────────────

class IngredientMatrix {
  static const List<IngredientMatrixEntry> entries = [
    // ── PROTEINS ──────────────────────────────
    IngredientMatrixEntry(
      name: 'salmon',
      aliases: ['salmon fillet', 'fresh salmon', 'wild salmon'],
      category: IngredientCategory.protein,
      liverImpact: LiverImpact.beneficial,
      liverFlags: ['high_omega3', 'high_protein', 'anti_inflammatory'],
      typicalMeasurements: ['oz', 'g', 'lb'],
      preferredFor: ['NAFLD', 'cirrhosis', 'fatty_liver'],
      fatGPer100g: 13.0,
      sodiumMgPer100g: 59.0,
    ),
    IngredientMatrixEntry(
      name: 'chicken breast',
      aliases: ['chicken', 'boneless chicken', 'skinless chicken breast'],
      category: IngredientCategory.protein,
      liverImpact: LiverImpact.beneficial,
      liverFlags: ['high_protein', 'low_fat', 'lean'],
      typicalMeasurements: ['oz', 'g', 'lb', 'piece'],
      preferredFor: ['NAFLD', 'fatty_liver'],
      fatGPer100g: 3.6,
      sodiumMgPer100g: 74.0,
    ),
    IngredientMatrixEntry(
      name: 'tuna',
      aliases: ['canned tuna', 'tuna fillet'],
      category: IngredientCategory.protein,
      liverImpact: LiverImpact.beneficial,
      liverFlags: ['high_protein', 'high_omega3'],
      typicalMeasurements: ['oz', 'g', 'can'],
      preferredFor: ['NAFLD'],
      sodiumMgPer100g: 300.0, // canned — note high sodium
    ),
    IngredientMatrixEntry(
      name: 'beef',
      aliases: ['beef strips', 'ground beef', 'lean beef'],
      category: IngredientCategory.protein,
      liverImpact: LiverImpact.caution,
      liverFlags: ['high_protein', 'high_saturated_fat'],
      typicalMeasurements: ['oz', 'g', 'lb'],
      avoidFor: ['cirrhosis'],
      fatGPer100g: 20.0,
    ),
    IngredientMatrixEntry(
      name: 'pork',
      aliases: ['pork loin', 'pork chop'],
      category: IngredientCategory.protein,
      liverImpact: LiverImpact.caution,
      liverFlags: ['high_protein', 'moderate_fat'],
      typicalMeasurements: ['oz', 'g', 'lb'],
      avoidFor: ['cirrhosis'],
    ),
    IngredientMatrixEntry(
      name: 'eggs',
      aliases: ['egg', 'large egg', 'whole egg'],
      category: IngredientCategory.protein,
      liverImpact: LiverImpact.neutral,
      liverFlags: ['high_protein', 'contains_choline'],
      typicalMeasurements: ['piece', 'pieces'],
      sodiumMgPer100g: 142.0,
    ),
    IngredientMatrixEntry(
      name: 'shrimp',
      aliases: ['prawns'],
      category: IngredientCategory.protein,
      liverImpact: LiverImpact.beneficial,
      liverFlags: ['high_protein', 'low_fat', 'low_calorie'],
      typicalMeasurements: ['oz', 'g', 'pieces'],
      preferredFor: ['NAFLD'],
    ),
    IngredientMatrixEntry(
      name: 'tofu',
      aliases: ['firm tofu', 'silken tofu'],
      category: IngredientCategory.protein,
      liverImpact: LiverImpact.beneficial,
      liverFlags: ['plant_protein', 'low_saturated_fat', 'isoflavones'],
      typicalMeasurements: ['oz', 'g', 'cup'],
      preferredFor: ['NAFLD', 'fatty_liver'],
    ),

    // ── VEGETABLES ────────────────────────────
    IngredientMatrixEntry(
      name: 'broccoli',
      aliases: ['broccoli florets'],
      category: IngredientCategory.vegetable,
      liverImpact: LiverImpact.beneficial,
      liverFlags: ['high_fiber', 'antioxidant', 'sulforaphane', 'low_calorie'],
      typicalMeasurements: ['cup', 'cups', 'g', 'oz'],
      preferredFor: ['NAFLD', 'cirrhosis', 'fatty_liver'],
      sodiumMgPer100g: 33.0,
    ),
    IngredientMatrixEntry(
      name: 'spinach',
      aliases: ['fresh spinach', 'baby spinach'],
      category: IngredientCategory.vegetable,
      liverImpact: LiverImpact.beneficial,
      liverFlags: ['high_iron', 'antioxidant', 'folate', 'low_calorie'],
      typicalMeasurements: ['cup', 'cups', 'oz'],
      preferredFor: ['NAFLD', 'cirrhosis'],
    ),
    IngredientMatrixEntry(
      name: 'carrot',
      aliases: ['carrots', 'baby carrots'],
      category: IngredientCategory.vegetable,
      liverImpact: LiverImpact.beneficial,
      liverFlags: ['beta_carotene', 'high_fiber', 'antioxidant'],
      typicalMeasurements: ['cup', 'cups', 'piece', 'pieces', 'oz'],
      preferredFor: ['NAFLD'],
    ),
    IngredientMatrixEntry(
      name: 'celery',
      aliases: ['celery stalks'],
      category: IngredientCategory.vegetable,
      liverImpact: LiverImpact.beneficial,
      liverFlags: ['low_calorie', 'high_water', 'anti_inflammatory'],
      typicalMeasurements: ['cup', 'piece', 'pieces'],
    ),
    IngredientMatrixEntry(
      name: 'onion',
      aliases: ['onions', 'yellow onion', 'white onion', 'red onion'],
      category: IngredientCategory.vegetable,
      liverImpact: LiverImpact.beneficial,
      liverFlags: ['quercetin', 'anti_inflammatory', 'antioxidant'],
      typicalMeasurements: ['cup', 'cups', 'piece', 'pieces'],
    ),
    IngredientMatrixEntry(
      name: 'garlic',
      aliases: ['garlic cloves', 'minced garlic', 'fresh garlic'],
      category: IngredientCategory.vegetable,
      liverImpact: LiverImpact.beneficial,
      liverFlags: ['allicin', 'anti_inflammatory', 'liver_protective'],
      typicalMeasurements: ['tsp', 'tbsp', 'piece', 'pieces'],
      preferredFor: ['NAFLD', 'fatty_liver'],
    ),
    IngredientMatrixEntry(
      name: 'sweet potato',
      aliases: ['sweet potatoes', 'yam'],
      category: IngredientCategory.vegetable,
      liverImpact: LiverImpact.beneficial,
      liverFlags: ['beta_carotene', 'high_fiber', 'complex_carbs'],
      typicalMeasurements: ['cup', 'piece', 'pieces', 'oz'],
      preferredFor: ['NAFLD'],
    ),
    IngredientMatrixEntry(
      name: 'zucchini',
      aliases: ['courgette'],
      category: IngredientCategory.vegetable,
      liverImpact: LiverImpact.beneficial,
      liverFlags: ['low_calorie', 'high_water', 'antioxidant'],
      typicalMeasurements: ['cup', 'piece', 'pieces'],
    ),
    IngredientMatrixEntry(
      name: 'bell pepper',
      aliases: ['peppers', 'red pepper', 'green pepper', 'yellow pepper'],
      category: IngredientCategory.vegetable,
      liverImpact: LiverImpact.beneficial,
      liverFlags: ['vitamin_c', 'antioxidant', 'low_calorie'],
      typicalMeasurements: ['cup', 'piece', 'pieces'],
    ),
    IngredientMatrixEntry(
      name: 'lettuce',
      aliases: ['romaine', 'mixed greens', 'salad greens'],
      category: IngredientCategory.vegetable,
      liverImpact: LiverImpact.beneficial,
      liverFlags: ['low_calorie', 'high_water'],
      typicalMeasurements: ['cup', 'cups', 'oz'],
    ),
    IngredientMatrixEntry(
      name: 'tomato',
      aliases: ['tomatoes', 'cherry tomatoes', 'roma tomatoes'],
      category: IngredientCategory.vegetable,
      liverImpact: LiverImpact.beneficial,
      liverFlags: ['lycopene', 'antioxidant', 'low_calorie'],
      typicalMeasurements: ['cup', 'piece', 'pieces', 'oz'],
    ),
    IngredientMatrixEntry(
      name: 'ginger',
      aliases: ['fresh ginger', 'ginger root'],
      category: IngredientCategory.spice,
      liverImpact: LiverImpact.beneficial,
      liverFlags: ['anti_inflammatory', 'liver_protective', 'gingerols'],
      typicalMeasurements: ['tsp', 'tbsp', 'piece'],
      preferredFor: ['NAFLD', 'fatty_liver'],
    ),

    // ── GRAINS ────────────────────────────────
    IngredientMatrixEntry(
      name: 'brown rice',
      aliases: ['whole grain rice'],
      category: IngredientCategory.grain,
      liverImpact: LiverImpact.beneficial,
      liverFlags: ['high_fiber', 'complex_carbs', 'low_glycemic'],
      typicalMeasurements: ['cup', 'cups'],
      preferredFor: ['NAFLD'],
    ),
    IngredientMatrixEntry(
      name: 'oats',
      aliases: ['oatmeal', 'rolled oats', 'steel cut oats'],
      category: IngredientCategory.grain,
      liverImpact: LiverImpact.beneficial,
      liverFlags: ['beta_glucan', 'high_fiber', 'reduces_liver_fat'],
      typicalMeasurements: ['cup', 'cups'],
      preferredFor: ['NAFLD', 'fatty_liver'],
    ),
    IngredientMatrixEntry(
      name: 'quinoa',
      aliases: ['cooked quinoa'],
      category: IngredientCategory.grain,
      liverImpact: LiverImpact.beneficial,
      liverFlags: ['complete_protein', 'high_fiber', 'low_glycemic'],
      typicalMeasurements: ['cup', 'cups'],
      preferredFor: ['NAFLD'],
    ),
    IngredientMatrixEntry(
      name: 'white rice',
      aliases: ['cooked rice'],
      category: IngredientCategory.grain,
      liverImpact: LiverImpact.neutral,
      liverFlags: ['refined_carbs', 'high_glycemic'],
      typicalMeasurements: ['cup', 'cups'],
    ),
    IngredientMatrixEntry(
      name: 'flour',
      aliases: ['all-purpose flour', 'wheat flour'],
      category: IngredientCategory.grain,
      liverImpact: LiverImpact.neutral,
      liverFlags: ['refined_carbs'],
      typicalMeasurements: ['cup', 'cups', 'tbsp'],
    ),

    // ── LEGUMES ───────────────────────────────
    IngredientMatrixEntry(
      name: 'lentils',
      aliases: ['red lentils', 'green lentils', 'brown lentils'],
      category: IngredientCategory.legume,
      liverImpact: LiverImpact.beneficial,
      liverFlags: ['high_fiber', 'plant_protein', 'low_fat', 'folate'],
      typicalMeasurements: ['cup', 'cups'],
      preferredFor: ['NAFLD', 'cirrhosis', 'fatty_liver'],
    ),
    IngredientMatrixEntry(
      name: 'chickpeas',
      aliases: ['garbanzo beans', 'canned chickpeas'],
      category: IngredientCategory.legume,
      liverImpact: LiverImpact.beneficial,
      liverFlags: ['high_fiber', 'plant_protein', 'low_glycemic'],
      typicalMeasurements: ['cup', 'cups', 'oz'],
      preferredFor: ['NAFLD'],
    ),
    IngredientMatrixEntry(
      name: 'beans',
      aliases: ['black beans', 'kidney beans', 'navy beans', 'peas'],
      category: IngredientCategory.legume,
      liverImpact: LiverImpact.beneficial,
      liverFlags: ['high_fiber', 'plant_protein'],
      typicalMeasurements: ['cup', 'cups', 'oz'],
      preferredFor: ['NAFLD'],
    ),

    // ── DAIRY ─────────────────────────────────
    IngredientMatrixEntry(
      name: 'greek yogurt',
      aliases: ['plain greek yogurt', 'low-fat greek yogurt'],
      category: IngredientCategory.dairy,
      liverImpact: LiverImpact.neutral,
      liverFlags: ['high_protein', 'probiotics', 'low_fat'],
      typicalMeasurements: ['cup', 'tbsp', 'oz'],
    ),
    IngredientMatrixEntry(
      name: 'milk',
      aliases: ['skim milk', 'low-fat milk', 'whole milk'],
      category: IngredientCategory.dairy,
      liverImpact: LiverImpact.neutral,
      liverFlags: ['calcium', 'vitamin_d'],
      typicalMeasurements: ['cup', 'cups', 'ml'],
    ),
    IngredientMatrixEntry(
      name: 'butter',
      aliases: ['unsalted butter'],
      category: IngredientCategory.dairy,
      liverImpact: LiverImpact.caution,
      liverFlags: ['high_saturated_fat'],
      typicalMeasurements: ['tbsp', 'tsp', 'oz'],
      avoidFor: ['cirrhosis', 'NAFLD'],
    ),
    IngredientMatrixEntry(
      name: 'cheese',
      aliases: ['cheddar', 'mozzarella', 'parmesan'],
      category: IngredientCategory.dairy,
      liverImpact: LiverImpact.caution,
      liverFlags: ['high_saturated_fat', 'high_sodium'],
      typicalMeasurements: ['oz', 'cup', 'tbsp'],
      sodiumMgPer100g: 600.0,
    ),

    // ── FATS & OILS ───────────────────────────
    IngredientMatrixEntry(
      name: 'olive oil',
      aliases: ['extra virgin olive oil', 'evoo'],
      category: IngredientCategory.fat,
      liverImpact: LiverImpact.beneficial,
      liverFlags: ['monounsaturated_fat', 'anti_inflammatory', 'polyphenols'],
      typicalMeasurements: ['tbsp', 'tsp', 'ml'],
      preferredFor: ['NAFLD', 'fatty_liver'],
    ),
    IngredientMatrixEntry(
      name: 'avocado',
      aliases: ['avocados'],
      category: IngredientCategory.fat,
      liverImpact: LiverImpact.beneficial,
      liverFlags: ['monounsaturated_fat', 'high_fiber', 'glutathione'],
      typicalMeasurements: ['piece', 'cup', 'tbsp'],
      preferredFor: ['NAFLD'],
    ),

    // ── FRUITS ────────────────────────────────
    IngredientMatrixEntry(
      name: 'apple',
      aliases: ['apples', 'green apple', 'red apple'],
      category: IngredientCategory.fruit,
      liverImpact: LiverImpact.beneficial,
      liverFlags: ['high_fiber', 'pectin', 'antioxidant'],
      typicalMeasurements: ['piece', 'cup', 'cups'],
      sugarGPer100g: 10.0,
    ),
    IngredientMatrixEntry(
      name: 'lemon',
      aliases: ['lemon juice', 'lemon zest'],
      category: IngredientCategory.fruit,
      liverImpact: LiverImpact.beneficial,
      liverFlags: ['vitamin_c', 'liver_detox', 'citric_acid'],
      typicalMeasurements: ['piece', 'tbsp', 'tsp'],
      preferredFor: ['NAFLD', 'fatty_liver'],
    ),
    IngredientMatrixEntry(
      name: 'blueberries',
      aliases: ['blueberry', 'mixed berries'],
      category: IngredientCategory.fruit,
      liverImpact: LiverImpact.beneficial,
      liverFlags: ['anthocyanins', 'antioxidant', 'anti_inflammatory'],
      typicalMeasurements: ['cup', 'cups', 'oz'],
      preferredFor: ['NAFLD'],
    ),
    IngredientMatrixEntry(
      name: 'banana',
      aliases: ['bananas'],
      category: IngredientCategory.fruit,
      liverImpact: LiverImpact.neutral,
      liverFlags: ['high_potassium', 'moderate_sugar'],
      typicalMeasurements: ['piece', 'cup'],
      sugarGPer100g: 12.0,
    ),

    // ── SPICES / SEASONINGS ───────────────────
    IngredientMatrixEntry(
      name: 'turmeric',
      aliases: ['ground turmeric', 'turmeric powder'],
      category: IngredientCategory.spice,
      liverImpact: LiverImpact.beneficial,
      liverFlags: ['curcumin', 'anti_inflammatory', 'liver_protective'],
      typicalMeasurements: ['tsp', 'pinch'],
      preferredFor: ['NAFLD', 'cirrhosis', 'fatty_liver'],
    ),
    IngredientMatrixEntry(
      name: 'salt',
      aliases: ['sea salt', 'table salt'],
      category: IngredientCategory.spice,
      liverImpact: LiverImpact.caution,
      liverFlags: ['high_sodium'],
      typicalMeasurements: ['tsp', 'pinch', 'to taste'],
      avoidFor: ['cirrhosis'], // cirrhosis requires strict sodium restriction
      sodiumMgPer100g: 38758.0,
    ),
    IngredientMatrixEntry(
      name: 'soy sauce',
      aliases: ['low-sodium soy sauce', 'tamari'],
      category: IngredientCategory.condiment,
      liverImpact: LiverImpact.caution,
      liverFlags: ['very_high_sodium'],
      typicalMeasurements: ['tbsp', 'tsp'],
      avoidFor: ['cirrhosis'],
      sodiumMgPer100g: 5720.0,
    ),

    // ── LIQUIDS ───────────────────────────────
    IngredientMatrixEntry(
      name: 'water',
      aliases: ['filtered water'],
      category: IngredientCategory.liquid,
      liverImpact: LiverImpact.beneficial,
      liverFlags: ['hydration', 'liver_flush'],
      typicalMeasurements: ['cup', 'cups', 'ml', 'l'],
      preferredFor: ['NAFLD', 'cirrhosis', 'fatty_liver'],
    ),
    IngredientMatrixEntry(
      name: 'vegetable broth',
      aliases: ['low-sodium vegetable broth', 'chicken broth'],
      category: IngredientCategory.liquid,
      liverImpact: LiverImpact.neutral,
      liverFlags: ['moderate_sodium'],
      typicalMeasurements: ['cup', 'cups', 'ml'],
      sodiumMgPer100g: 200.0,
    ),

    // ── SUGARS / SWEETENERS ───────────────────
    IngredientMatrixEntry(
      name: 'sugar',
      aliases: ['white sugar', 'granulated sugar'],
      category: IngredientCategory.condiment,
      liverImpact: LiverImpact.caution,
      liverFlags: ['high_sugar', 'liver_fat_precursor'],
      typicalMeasurements: ['cup', 'tbsp', 'tsp'],
      avoidFor: ['NAFLD', 'fatty_liver'],
      sugarGPer100g: 100.0,
    ),
    IngredientMatrixEntry(
      name: 'brown sugar',
      aliases: ['dark brown sugar'],
      category: IngredientCategory.condiment,
      liverImpact: LiverImpact.caution,
      liverFlags: ['high_sugar'],
      typicalMeasurements: ['tbsp', 'tsp'],
      avoidFor: ['NAFLD'],
    ),
    IngredientMatrixEntry(
      name: 'honey',
      aliases: ['raw honey'],
      category: IngredientCategory.condiment,
      liverImpact: LiverImpact.caution,
      liverFlags: ['high_sugar', 'fructose'],
      typicalMeasurements: ['tbsp', 'tsp'],
      avoidFor: ['NAFLD'],
    ),
  ];

  /// Get all entries for a given category
  static List<IngredientMatrixEntry> byCategory(IngredientCategory cat) =>
      entries.where((e) => e.category == cat).toList();

  /// Get all entries preferred for a disease type
  static List<IngredientMatrixEntry> preferredForDisease(String disease) =>
      entries.where((e) => e.preferredFor.contains(disease)).toList();

  /// Get all entries to avoid for a disease type
  static List<IngredientMatrixEntry> avoidForDisease(String disease) =>
      entries.where((e) => e.avoidFor.contains(disease)).toList();

  /// Look up an entry by name or alias (case-insensitive)
  static IngredientMatrixEntry? lookup(String term) {
    final lower = term.toLowerCase().trim();
    for (final entry in entries) {
      if (entry.name == lower) return entry;
      if (entry.aliases.any((a) => a.toLowerCase() == lower)) return entry;
    }
    return null;
  }

  /// Check if a term is a known food (replaces _knownFoodWords fast-path)
  static bool isKnownFood(String term) => lookup(term) != null;

  /// Get beneficial ingredients count (for dataset stats)
  static int get beneficialCount =>
      entries.where((e) => e.liverImpact == LiverImpact.beneficial).length;
}