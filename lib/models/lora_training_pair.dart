// lib/models/lora_training_pair.dart
// Canonical training pair model for LoRA dataset generation.
// Every field maps exactly to existing models:
//   - ingredients  → IngredientRow / RecipeIngredient
//   - nutrition    → NutritionInfo.fromDatabaseJson() keys (camelCase)
//   - compliance   → ComplianceReport fields
// DO NOT change field names — downstream JSON must match these exactly.

import 'dart:convert';
import 'package:liver_wise/models/nutrition_info.dart';
import 'package:liver_wise/models/recipe_submission.dart';

// ─────────────────────────────────────────────
// TRAINING PAIR  (instruction → output)
// ─────────────────────────────────────────────

class LoraTrainingPair {
  final String id; // UUID, for deduplication
  final LoraTaskType taskType; // which LoRA model this trains
  final String instruction;
  final LoraInput input;
  final LoraOutput output;
  final String datasetVersion; // e.g. "v1.0"
  final DateTime createdAt;
  final bool isNegativeExample;

  LoraTrainingPair({
    required this.id,
    required this.taskType,
    required this.instruction,
    required this.input,
    required this.output,
    this.datasetVersion = 'v1.0',
    DateTime? createdAt,
    this.isNegativeExample = false,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'task_type': taskType.name,
        'instruction': instruction,
        'input': input.toJson(),
        'output': output.toJson(),
        'dataset_version': datasetVersion,
        'created_at': createdAt.toIso8601String(),
        'is_negative_example': isNegativeExample,
      };

  factory LoraTrainingPair.fromJson(Map<String, dynamic> json) =>
      LoraTrainingPair(
        id: json['id'] as String,
        taskType: LoraTaskType.values.byName(json['task_type'] as String),
        instruction: json['instruction'] as String,
        input: LoraInput.fromJson(json['input'] as Map<String, dynamic>),
        output: LoraOutput.fromJson(json['output'] as Map<String, dynamic>),
        datasetVersion: json['dataset_version'] as String? ?? 'v1.0',
        createdAt: DateTime.parse(json['created_at'] as String),
        isNegativeExample: json['is_negative_example'] as bool? ?? false,
      );

  /// Serialize to JSONL line for training file
  String toJsonLine() => jsonEncode(toJson());
}

// ─────────────────────────────────────────────
// TASK TYPE — which LoRA model gets trained
// ─────────────────────────────────────────────

enum LoraTaskType {
  recipeGenerator, // Model A: instruction → full recipe JSON
  complianceReviewer, // Model B: recipe JSON → ComplianceReport + corrections
  foodClassifier, // Model C: word → {isFood, category, confidence}
}

// ─────────────────────────────────────────────
// INPUT
// ─────────────────────────────────────────────

class LoraInput {
  // Recipe generator inputs
  final String? diseaseType; // "NAFLD" | "cirrhosis" | "fatty_liver" | null
  final LoraConstraints? constraints;
  final List<String>? availableIngredients;

  // Compliance reviewer input
  final LoraRawRecipe? rawRecipe; // the recipe to be reviewed

  // Food classifier input
  final String? word;

  LoraInput({
    this.diseaseType,
    this.constraints,
    this.availableIngredients,
    this.rawRecipe,
    this.word,
  });

  Map<String, dynamic> toJson() => {
        if (diseaseType != null) 'disease_type': diseaseType,
        if (constraints != null) 'constraints': constraints!.toJson(),
        if (availableIngredients != null)
          'available_ingredients': availableIngredients,
        if (rawRecipe != null) 'raw_recipe': rawRecipe!.toJson(),
        if (word != null) 'word': word,
      };

  factory LoraInput.fromJson(Map<String, dynamic> json) => LoraInput(
        diseaseType: json['disease_type'] as String?,
        constraints: json['constraints'] != null
            ? LoraConstraints.fromJson(
                json['constraints'] as Map<String, dynamic>)
            : null,
        availableIngredients:
            (json['available_ingredients'] as List?)?.cast<String>(),
        rawRecipe: json['raw_recipe'] != null
            ? LoraRawRecipe.fromJson(
                json['raw_recipe'] as Map<String, dynamic>)
            : null,
        word: json['word'] as String?,
      );
}

// ─────────────────────────────────────────────
// CONSTRAINTS  (mirrors RecipeComplianceService thresholds)
// ─────────────────────────────────────────────

class LoraConstraints {
  final double? maxSodiumMg; // compliance threshold: 2000
  final double? maxSugarG; // compliance threshold: 50
  final double? maxFatG; // compliance threshold: 50
  final double? minProteinG;
  final int? minHealthScore; // compliance threshold: 50
  final int? maxCalories;
  final bool? requireHighFiber;

  const LoraConstraints({
    this.maxSodiumMg,
    this.maxSugarG,
    this.maxFatG,
    this.minProteinG,
    this.minHealthScore,
    this.maxCalories,
    this.requireHighFiber,
  });

  Map<String, dynamic> toJson() => {
        if (maxSodiumMg != null) 'max_sodium_mg': maxSodiumMg,
        if (maxSugarG != null) 'max_sugar_g': maxSugarG,
        if (maxFatG != null) 'max_fat_g': maxFatG,
        if (minProteinG != null) 'min_protein_g': minProteinG,
        if (minHealthScore != null) 'min_health_score': minHealthScore,
        if (maxCalories != null) 'max_calories': maxCalories,
        if (requireHighFiber != null) 'require_high_fiber': requireHighFiber,
      };

  factory LoraConstraints.fromJson(Map<String, dynamic> json) =>
      LoraConstraints(
        maxSodiumMg: (json['max_sodium_mg'] as num?)?.toDouble(),
        maxSugarG: (json['max_sugar_g'] as num?)?.toDouble(),
        maxFatG: (json['max_fat_g'] as num?)?.toDouble(),
        minProteinG: (json['min_protein_g'] as num?)?.toDouble(),
        minHealthScore: json['min_health_score'] as int?,
        maxCalories: json['max_calories'] as int?,
        requireHighFiber: json['require_high_fiber'] as bool?,
      );

  // Standard presets matching compliance service thresholds
  static const LoraConstraints liverSafe = LoraConstraints(
    maxSodiumMg: 2000,
    maxSugarG: 50,
    maxFatG: 50,
    minHealthScore: 50,
  );

  static const LoraConstraints strict = LoraConstraints(
    maxSodiumMg: 800,
    maxSugarG: 20,
    maxFatG: 25,
    minProteinG: 20,
    minHealthScore: 70,
    requireHighFiber: true,
  );
}

// ─────────────────────────────────────────────
// RAW RECIPE  (used as input to compliance reviewer)
// — ingredient format matches IngredientRow.toJson()
// ─────────────────────────────────────────────

class LoraRawRecipe {
  final String recipeName;
  // Each map: {"quantity": "2", "measurement": "cup", "name": "flour"}
  // Matches IngredientRow.toJson() exactly
  final List<Map<String, dynamic>> ingredients;
  final String directions;
  final String? description;
  // nutrition keys match NutritionInfo.fromDatabaseJson() — camelCase
  final Map<String, dynamic>? nutrition;

  LoraRawRecipe({
    required this.recipeName,
    required this.ingredients,
    required this.directions,
    this.description,
    this.nutrition,
  });

  Map<String, dynamic> toJson() => {
        'recipe_name': recipeName,
        'ingredients': ingredients,
        'directions': directions,
        if (description != null) 'description': description,
        if (nutrition != null) 'nutrition': nutrition,
      };

  factory LoraRawRecipe.fromJson(Map<String, dynamic> json) => LoraRawRecipe(
        recipeName: json['recipe_name'] as String,
        ingredients: (json['ingredients'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(),
        directions: json['directions'] as String,
        description: json['description'] as String?,
        nutrition: json['nutrition'] != null
            ? Map<String, dynamic>.from(json['nutrition'] as Map)
            : null,
      );

  /// Convert to plain-text ingredient string used by RecipeDetailPage
  /// Matches _ingredientsToPlainText() in SubmitRecipePage
  String get ingredientsAsPlainText {
    return ingredients
        .where((i) =>
            (i['quantity'] as String? ?? '').isNotEmpty &&
            (i['name'] as String? ?? '').isNotEmpty)
        .map((i) {
          final qty = i['quantity'] as String? ?? '';
          final meas = i['measurement'] == 'other'
              ? (i['customMeasurement'] as String? ?? '')
              : (i['measurement'] as String? ?? '');
          final name = i['name'] as String? ?? '';
          return '$qty $meas $name'.trim();
        })
        .join('\n');
  }

  /// Convert to NutritionInfo using existing fromDatabaseJson parser
  NutritionInfo? get parsedNutrition {
    if (nutrition == null) return null;
    try {
      return NutritionInfo.fromDatabaseJson(nutrition!);
    } catch (_) {
      return null;
    }
  }
}

// ─────────────────────────────────────────────
// OUTPUT
// ─────────────────────────────────────────────

class LoraOutput {
  // Recipe generator output
  final LoraGeneratedRecipe? generatedRecipe;

  // Compliance reviewer output
  final LoraComplianceResult? complianceResult;

  // Food classifier output
  final LoraClassificationResult? classificationResult;

  LoraOutput({
    this.generatedRecipe,
    this.complianceResult,
    this.classificationResult,
  });

  Map<String, dynamic> toJson() => {
        if (generatedRecipe != null)
          'generated_recipe': generatedRecipe!.toJson(),
        if (complianceResult != null)
          'compliance_result': complianceResult!.toJson(),
        if (classificationResult != null)
          'classification_result': classificationResult!.toJson(),
      };

  factory LoraOutput.fromJson(Map<String, dynamic> json) => LoraOutput(
        generatedRecipe: json['generated_recipe'] != null
            ? LoraGeneratedRecipe.fromJson(
                json['generated_recipe'] as Map<String, dynamic>)
            : null,
        complianceResult: json['compliance_result'] != null
            ? LoraComplianceResult.fromJson(
                json['compliance_result'] as Map<String, dynamic>)
            : null,
        classificationResult: json['classification_result'] != null
            ? LoraClassificationResult.fromJson(
                json['classification_result'] as Map<String, dynamic>)
            : null,
      );
}

// ─────────────────────────────────────────────
// GENERATED RECIPE OUTPUT
// All fields match existing rendering targets:
//   - ingredients  → rendered by RecipeDetailPage as plain text
//   - nutrition    → passed to NutritionFactsLabel(nutrition: ...)
//   - compliance   → matches ComplianceReport fields exactly
// ─────────────────────────────────────────────

class LoraGeneratedRecipe {
  final String recipeName;
  final String description;
  // Structured format — matches IngredientRow.toJson()
  final List<Map<String, dynamic>> ingredients;
  // Step-separated by \n, each step starts with "N. "
  final String directions;
  final int servings;
  // camelCase keys — matches NutritionInfo.fromDatabaseJson()
  final Map<String, dynamic> nutrition;
  final LoraComplianceSnapshot compliance;

  LoraGeneratedRecipe({
    required this.recipeName,
    required this.description,
    required this.ingredients,
    required this.directions,
    required this.servings,
    required this.nutrition,
    required this.compliance,
  });

  Map<String, dynamic> toJson() => {
        'recipe_name': recipeName,
        'description': description,
        'ingredients': ingredients,
        'directions': directions,
        'servings': servings,
        'nutrition': nutrition,
        'compliance': compliance.toJson(),
      };

  factory LoraGeneratedRecipe.fromJson(Map<String, dynamic> json) =>
      LoraGeneratedRecipe(
        recipeName: json['recipe_name'] as String,
        description: json['description'] as String,
        ingredients: (json['ingredients'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(),
        directions: json['directions'] as String,
        servings: json['servings'] as int,
        nutrition:
            Map<String, dynamic>.from(json['nutrition'] as Map),
        compliance: LoraComplianceSnapshot.fromJson(
            json['compliance'] as Map<String, dynamic>),
      );

  /// Convert to NutritionInfo for passing to NutritionFactsLabel
  NutritionInfo get nutritionInfo =>
      NutritionInfo.fromDatabaseJson(nutrition);

  /// Convert ingredients to plain text for RecipeDetailPage
  String get ingredientsPlainText {
    return ingredients
        .where((i) =>
            (i['quantity'] as String? ?? '').isNotEmpty &&
            (i['name'] as String? ?? '').isNotEmpty)
        .map((i) {
          final qty = i['quantity'] as String? ?? '';
          final meas = i['measurement'] == 'other'
              ? (i['customMeasurement'] as String? ?? '')
              : (i['measurement'] as String? ?? '');
          final name = i['name'] as String? ?? '';
          return '$qty $meas $name'.trim();
        })
        .join('\n');
  }
}

// ─────────────────────────────────────────────
// COMPLIANCE SNAPSHOT  (embedded in generated recipe output)
// Mirrors ComplianceReport but without errors list —
// generated recipes should always be valid
// ─────────────────────────────────────────────

class LoraComplianceSnapshot {
  final int healthScore; // 0–100
  final bool isLiverSafe;
  final List<String> dietaryFlags; // e.g. ["High Protein", "Low Sodium"]
  final List<String> warnings;

  LoraComplianceSnapshot({
    required this.healthScore,
    required this.isLiverSafe,
    this.dietaryFlags = const [],
    this.warnings = const [],
  });

  Map<String, dynamic> toJson() => {
        'health_score': healthScore,
        'is_liver_safe': isLiverSafe,
        'dietary_flags': dietaryFlags,
        'warnings': warnings,
      };

  factory LoraComplianceSnapshot.fromJson(Map<String, dynamic> json) =>
      LoraComplianceSnapshot(
        healthScore: json['health_score'] as int,
        isLiverSafe: json['is_liver_safe'] as bool,
        dietaryFlags:
            (json['dietary_flags'] as List?)?.cast<String>() ?? [],
        warnings: (json['warnings'] as List?)?.cast<String>() ?? [],
      );

  /// Convert to ComplianceReport for passing to compliance service
  ComplianceReport toComplianceReport() => ComplianceReport(
        hasCompleteNutrition: true,
        isLiverSafe: isLiverSafe,
        contentAppropriate: true,
        healthScore: healthScore,
        warnings: warnings,
        errors: [],
      );
}

// ─────────────────────────────────────────────
// COMPLIANCE RESULT  (output of compliance reviewer model)
// ─────────────────────────────────────────────

class LoraComplianceResult {
  final List<String> complianceErrors;
  final List<String> complianceWarnings;
  final bool passedCompliance;
  final LoraRawRecipe? correctedRecipe; // null if recipe passed
  final String? correctionNotes;

  LoraComplianceResult({
    required this.complianceErrors,
    required this.complianceWarnings,
    required this.passedCompliance,
    this.correctedRecipe,
    this.correctionNotes,
  });

  Map<String, dynamic> toJson() => {
        'compliance_errors': complianceErrors,
        'compliance_warnings': complianceWarnings,
        'passed_compliance': passedCompliance,
        if (correctedRecipe != null)
          'corrected_recipe': correctedRecipe!.toJson(),
        if (correctionNotes != null) 'correction_notes': correctionNotes,
      };

  factory LoraComplianceResult.fromJson(Map<String, dynamic> json) =>
      LoraComplianceResult(
        complianceErrors:
            (json['compliance_errors'] as List?)?.cast<String>() ?? [],
        complianceWarnings:
            (json['compliance_warnings'] as List?)?.cast<String>() ?? [],
        passedCompliance: json['passed_compliance'] as bool,
        correctedRecipe: json['corrected_recipe'] != null
            ? LoraRawRecipe.fromJson(
                json['corrected_recipe'] as Map<String, dynamic>)
            : null,
        correctionNotes: json['correction_notes'] as String?,
      );
}

// ─────────────────────────────────────────────
// CLASSIFICATION RESULT
// ─────────────────────────────────────────────

class LoraClassificationResult {
  final bool isFood;
  final String category; // "protein" | "vegetable" | "grain" | "dairy" | etc.
  final double confidence; // 0.0–1.0
  final List<String> liverFlags; // e.g. ["beneficial", "high_omega3"]
  final List<String> preferredFor; // disease types

  LoraClassificationResult({
    required this.isFood,
    required this.category,
    required this.confidence,
    this.liverFlags = const [],
    this.preferredFor = const [],
  });

  Map<String, dynamic> toJson() => {
        'is_food': isFood,
        'category': category,
        'confidence': confidence,
        'liver_flags': liverFlags,
        'preferred_for': preferredFor,
      };

  factory LoraClassificationResult.fromJson(Map<String, dynamic> json) =>
      LoraClassificationResult(
        isFood: json['is_food'] as bool,
        category: json['category'] as String,
        confidence: (json['confidence'] as num).toDouble(),
        liverFlags: (json['liver_flags'] as List?)?.cast<String>() ?? [],
        preferredFor: (json['preferred_for'] as List?)?.cast<String>() ?? [],
      );
}