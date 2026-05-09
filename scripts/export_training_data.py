#!/usr/bin/env python3
"""
scripts/export_training_data.py
LiverWise LoRA Training Data Exporter

Pulls recipes from the Cloudflare Worker endpoint,
validates them against compliance rules, and converts them
into structured instruction→output training pairs in JSONL format.

Usage:
    python export_training_data.py [--mode recipes|negative|matrix|all] [--out ./datasets]

Output files:
    datasets/recipes_v1_TIMESTAMP.jsonl          — positive training pairs
    datasets/negative_examples_v1_TIMESTAMP.jsonl — negative/correction pairs
    datasets/ingredient_matrix_v1_TIMESTAMP.jsonl — ingredient classification pairs
    datasets/export_report_TIMESTAMP.json         — stats and validation summary
"""
import json
import argparse
import sys
import os
import hashlib
import re
from datetime import datetime, timezone
from typing import Optional

try:
    import requests
except ImportError:
    print("ERROR: 'requests' not installed. Run: pip install requests")
    sys.exit(1)

# ============================================================
# CONFIG — mirrors AppConfig.dart exactly
# ============================================================
WORKER_URL = os.environ.get(
    "CLOUDFLARE_WORKER_URL",
    "https://shrill-paper-a8ce.terryd0612.workers.dev"
)
WORKER_QUERY_ENDPOINT = f"{WORKER_URL}/query"

AUTH_TOKEN = os.environ.get("LIVERWISE_AUTH_TOKEN", "")

# Compliance thresholds — mirrors RecipeComplianceService exactly
COMPLIANCE = {
    "max_sodium_mg":        2000,
    "max_sugar_g":          50,
    "max_fat_g":            50,
    "min_health_score":     50,
    "min_title_len":        3,
    "min_instructions_len": 20,
}

# LiverHealthCalculator thresholds — mirrors liverhealthbar.dart exactly
LIVER_CALC = {
    "fat_max":    20.0,
    "sodium_max": 500.0,
    "sugar_max":  20.0,
    "cal_max":    400.0,
}

OUTPUT_DIR  = "./datasets"
TIMEOUT_SEC = 30

# ============================================================
# LIVER SCORE CALCULATOR
# Mirrors LiverHealthCalculator.calculate() in liverhealthbar.dart
# ============================================================
def calculate_liver_score(fat: float, sodium: float, sugar: float, calories: float) -> int:
    fat_score    = 1 - min(fat     / LIVER_CALC["fat_max"],    1)
    sodium_score = 1 - min(sodium  / LIVER_CALC["sodium_max"], 1)
    sugar_score  = 1 - min(sugar   / LIVER_CALC["sugar_max"],  1)
    cal_score    = 1 - min(calories / LIVER_CALC["cal_max"],   1)
    final = (
        fat_score    * 0.30 +
        sodium_score * 0.25 +
        sugar_score  * 0.25 +
        cal_score    * 0.20
    )
    return max(0, min(100, round(final * 100)))

# ============================================================
# WORKER QUERY
# ============================================================
def worker_query(
    action: str,
    table: str,
    filters: Optional[dict] = None,
    columns: Optional[list] = None,
    order_by: Optional[str] = None,
    ascending: bool = True,
    limit: Optional[int] = None,
    offset: Optional[int] = None,
) -> list:
    payload = {
        "action":    action,
        "table":     table,
        "authToken": AUTH_TOKEN,
    }
    if filters:  payload["filters"]   = filters
    if columns:  payload["columns"]   = columns
    if order_by: payload["orderBy"]   = order_by
    if limit:    payload["limit"]     = limit
    if offset:   payload["offset"]    = offset
    payload["ascending"] = ascending

    try:
        resp = requests.post(
            WORKER_QUERY_ENDPOINT,
            headers={"Content-Type": "application/json"},
            json=payload,
            timeout=TIMEOUT_SEC,
        )
        resp.raise_for_status()
        return resp.json()
    except requests.exceptions.Timeout:
        print(f"  TIMEOUT querying {table}")
        return []
    except requests.exceptions.RequestException as e:
        print(f"  REQUEST ERROR querying {table}: {e}")
        return []

# ============================================================
# RECIPES TABLE SCHEMA (confirmed from live DB)
#
# id               — integer
# title            — string
# ingredients      — list of plain strings e.g. "2 cups flour"
# directions       — JSON-stringified array e.g. '["Step 1...", "Step 2..."]'
# fingerprint      — string (dedup hash, already exists)
# owner_id         — nullable
# is_premium       — bool
# recipe_type      — string
# submitted_by_user_id — nullable
# is_community_recipe  — bool
#
# NOTE: No nutrition field in this table.
# Nutrition is estimated from ingredients using heuristics below.
# ============================================================

# ============================================================
# INGREDIENT NORMALIZER
# Converts plain string ingredients to {quantity, measurement, name}
# ============================================================
VALID_MEASUREMENTS = {
    "cup", "cups", "tbsp", "tsp", "oz", "lb", "lbs", "g", "kg",
    "ml", "l", "piece", "pieces", "pinch", "dash", "tablespoon",
    "tablespoons", "teaspoon", "teaspoons", "ounce", "ounces",
    "pound", "pounds", "clove", "cloves", "slice", "slices",
    "can", "cans", "package", "packages", "bunch", "head",
    "stalk", "stalks", "sprig", "sprigs", "leaf", "leaves",
}

MEASUREMENT_ALIASES = {
    "tablespoon": "tbsp", "tablespoons": "tbsp",
    "teaspoon": "tsp",   "teaspoons": "tsp",
    "ounce": "oz",       "ounces": "oz",
    "pound": "lb",       "pounds": "lb", "lbs": "lb",
}

def normalize_ingredient(raw) -> Optional[dict]:
    """
    Accepts plain string like "2 cups flour" or "1 clove garlic, minced"
    Returns canonical {quantity, measurement, name} dict.
    """
    if isinstance(raw, dict):
        qty  = str(raw.get("quantity", "")).strip()
        meas = str(raw.get("measurement", "piece")).strip().lower()
        name = str(raw.get("name", "")).strip()
        meas = MEASUREMENT_ALIASES.get(meas, meas)
        if meas not in VALID_MEASUREMENTS:
            meas = "piece"
        if not qty or not name:
            return None
        return {"quantity": qty, "measurement": meas, "name": name}

    if not isinstance(raw, str) or not raw.strip():
        return None

    raw = raw.strip()

    # Remove parenthetical notes: "1 cup flour (sifted)" → "1 cup flour"
    raw_clean = re.sub(r'\s*\(.*?\)', '', raw).strip()

    # Pattern: number (fraction or decimal), optional unit, rest is name
    pattern = r'^([\d¼½¾⅓⅔⅛⅜⅝⅞]+(?:[./\s][\d]+)?)\s*([a-zA-Z]+)?\s+(.+)$'
    m = re.match(pattern, raw_clean)
    if m:
        qty  = m.group(1).strip()
        meas = (m.group(2) or "").lower().strip()
        name = m.group(3).strip().rstrip(',').strip()
        meas = MEASUREMENT_ALIASES.get(meas, meas)
        if meas not in VALID_MEASUREMENTS:
            if meas:
                name = f"{meas} {name}".strip()
            meas = "piece"
        return {"quantity": qty, "measurement": meas, "name": name}

    # Fallback: whole string is the name
    return {"quantity": "1", "measurement": "piece", "name": raw_clean.rstrip(',').strip()}


def parse_directions(raw_directions) -> str:
    """
    Converts the recipes table directions field to numbered steps separated by \\n.

    The field is a JSON-stringified array: '["Step 1...", "Step 2..."]'
    OR a plain string of instructions.
    Returns: "1. Step one\\n2. Step two\\n..."
    """
    if not raw_directions:
        return ""

    steps = []

    # Try parsing as JSON array first
    if isinstance(raw_directions, str) and raw_directions.strip().startswith('['):
        try:
            parsed = json.loads(raw_directions)
            if isinstance(parsed, list):
                # Each element may itself be a long paragraph — split on sentences
                for item in parsed:
                    item = str(item).strip()
                    if item:
                        # Split long paragraphs into individual sentences
                        sentences = re.split(r'\.\s+(?=[A-Z])', item)
                        for s in sentences:
                            s = s.strip().rstrip('.')
                            if len(s) > 10:
                                steps.append(s)
        except json.JSONDecodeError:
            pass

    # If still empty, treat as plain string
    if not steps:
        text = str(raw_directions).strip()
        # Remove JSON brackets if present
        text = re.sub(r'^\["|"\]$', '', text).strip()
        sentences = re.split(r'\.\s+(?=[A-Z])', text)
        for s in sentences:
            s = s.strip().rstrip('.')
            if len(s) > 10:
                steps.append(s)

    if not steps:
        return str(raw_directions).strip()

    return "\n".join(f"{i+1}. {step}." for i, step in enumerate(steps))


# ============================================================
# NUTRITION ESTIMATOR
# Since the recipes table has no nutrition field, we estimate
# from ingredient names using the liver-safe ingredient matrix.
# This gives approximate values sufficient for training pair
# instruction generation. Scores will be conservative.
# ============================================================

# Known high-risk ingredients and their approximate per-serving impact
HARMFUL_KEYWORDS = {
    "soy sauce":      {"sodium": 900},
    "butter":         {"fat": 12, "saturated_fat": 7},
    "cream":          {"fat": 20, "saturated_fat": 12},
    "sugar":          {"sugar": 15},
    "brown sugar":    {"sugar": 18},
    "white sugar":    {"sugar": 15},
    "salt":           {"sodium": 300},
    "bacon":          {"fat": 14, "sodium": 400},
    "cheese":         {"fat": 8, "saturated_fat": 5, "sodium": 200},
    "mayonnaise":     {"fat": 15},
    "oil":            {"fat": 7},
    "olive oil":      {"fat": 7},
}

BENEFICIAL_KEYWORDS = [
    "kale", "spinach", "broccoli", "lentils", "chickpeas",
    "salmon", "quinoa", "oats", "berries", "avocado",
    "sweet potato", "brown rice", "tofu", "lemon",
]

def estimate_nutrition(ingredients: list, title: str) -> dict:
    """
    Estimates nutrition from ingredient strings.
    Returns dict with keys matching NutritionInfo.fromDatabaseJson() camelCase format.
    Values are rough per-serving estimates — sufficient for training pair generation.
    """
    fat = 5.0
    sodium = 150.0
    sugar = 5.0
    calories = 280.0
    protein = 12.0
    fiber = 4.0
    saturated_fat = 2.0
    carbs = 35.0

    ingredient_text = " ".join(str(i).lower() for i in ingredients)

    # Apply harmful keyword impacts
    for keyword, impacts in HARMFUL_KEYWORDS.items():
        if keyword in ingredient_text:
            fat      += impacts.get("fat", 0)
            sodium   += impacts.get("sodium", 0)
            sugar    += impacts.get("sugar", 0)
            saturated_fat += impacts.get("saturated_fat", 0)

    # Beneficial ingredients reduce fat/sodium/sugar
    beneficial_count = sum(1 for b in BENEFICIAL_KEYWORDS if b in ingredient_text)
    if beneficial_count >= 3:
        fat    = max(fat - 5, 2)
        sodium = max(sodium - 100, 50)
        sugar  = max(sugar - 3, 1)
        fiber  = min(fiber + beneficial_count * 1.5, 15)
        protein = min(protein + beneficial_count * 2, 35)

    # Calorie estimate from macros
    calories = (protein * 4) + (carbs * 4) + (fat * 9)
    calories = max(150, min(calories, 800))

    return {
        "productName":        title,
        "calories":           round(calories, 1),
        "fat":                round(fat, 1),
        "saturatedFat":       round(saturated_fat, 1),
        "monounsaturatedFat": 0.0,
        "polyunsaturatedFat": 0.0,
        "transFat":           0.0,
        "cholesterol":        0.0,
        "sodium":             round(sodium, 1),
        "carbs":              round(carbs, 1),
        "fiber":              round(fiber, 1),
        "sugar":              round(sugar, 1),
        "protein":            round(protein, 1),
        "potassium":          0.0,
        "iron":               0.0,
        "cobalt":             0.0,
        "vitaminA":           0.0,
        "vitaminC":           0.0,
        "vitaminD":           0.0,
        "calcium":            0.0,
    }


# ============================================================
# COMPLIANCE CHECKER
# Mirrors RecipeComplianceService.checkCompliance() exactly
# ============================================================
def check_compliance(recipe: dict) -> dict:
    errors   = []
    warnings = []
    nutrition = recipe.get("nutrition", {})

    has_nutrition = bool(
        nutrition.get("calories", 0) > 0 and
        nutrition.get("fat", 0)      >= 0 and
        nutrition.get("sodium", 0)   >= 0 and
        nutrition.get("sugar", 0)    >= 0
    )
    if not has_nutrition:
        errors.append("Recipe missing complete nutrition data")

    health_score  = None
    is_liver_safe = True

    if nutrition:
        health_score = calculate_liver_score(
            fat=float(nutrition.get("fat", 0)),
            sodium=float(nutrition.get("sodium", 0)),
            sugar=float(nutrition.get("sugar", 0)),
            calories=float(nutrition.get("calories", 0)),
        )
        if health_score < COMPLIANCE["min_health_score"] and not recipe.get("_nutrition_estimated"):
            is_liver_safe = False
            warnings.append(f"Recipe has low health score ({health_score}/100)")

        if float(nutrition.get("sodium", 0)) > COMPLIANCE["max_sodium_mg"]:
            warnings.append(f"Very high sodium ({nutrition['sodium']:.0f}mg)")
        if float(nutrition.get("sugar", 0)) > COMPLIANCE["max_sugar_g"]:
            warnings.append(f"Very high sugar ({nutrition['sugar']:.0f}g)")
        if float(nutrition.get("fat", 0)) > COMPLIANCE["max_fat_g"]:
            warnings.append(f"Very high fat ({nutrition['fat']:.0f}g)")
    else:
        is_liver_safe = False
        warnings.append("Cannot calculate health score — missing nutrition")

    title        = recipe.get("title", "")
    ingredients  = recipe.get("ingredients", [])
    instructions = recipe.get("directions_parsed", recipe.get("directions", ""))
    content_ok   = True

    if len(str(title).strip()) < COMPLIANCE["min_title_len"]:
        errors.append("Title too short")
        content_ok = False
    if not ingredients:
        errors.append("No ingredients listed")
        content_ok = False
    if len(str(instructions).strip()) < COMPLIANCE["min_instructions_len"]:
        errors.append("Instructions too brief")
        content_ok = False

    return {
        "has_complete_nutrition": has_nutrition,
        "is_liver_safe":          is_liver_safe,
        "content_appropriate":    content_ok,
        "health_score":           health_score,
        "warnings":               warnings,
        "errors":                 errors,
        "all_checks_passed":      has_nutrition and is_liver_safe and content_ok and not errors,
    }


# ============================================================
# DIETARY FLAG CALCULATOR
# ============================================================
def get_dietary_flags(nutrition: dict) -> list:
    flags    = []
    calories = float(nutrition.get("calories", 0))
    protein  = float(nutrition.get("protein", 0))
    carbs    = float(nutrition.get("carbs", 0))
    fat      = float(nutrition.get("fat", 0))
    sodium   = float(nutrition.get("sodium", 999))
    fiber    = float(nutrition.get("fiber", 0))

    if calories > 0:
        protein_pct = (protein * 4 / calories) * 100
        carb_pct    = (carbs   * 4 / calories) * 100
        fat_pct     = (fat     * 9 / calories) * 100
        if protein_pct >= 30: flags.append("High Protein")
        if carb_pct    <  30: flags.append("Low Carb")
        if fat_pct     <  30: flags.append("Low Fat")

    if fiber  >= 5:   flags.append("High Fiber")
    if sodium < 140:  flags.append("Low Sodium")
    return flags


# ============================================================
# DEDUPLICATION KEY
# Uses fingerprint field from recipes table if available,
# otherwise falls back to sorted ingredient hash.
# ============================================================
def make_dedup_key(recipe: dict) -> str:
    # Use the existing fingerprint from the DB if present
    if recipe.get("fingerprint"):
        return recipe["fingerprint"]

    ingredients = recipe.get("ingredients", [])
    names = []
    for ing in ingredients:
        if isinstance(ing, dict):
            names.append(ing.get("name", "").lower().strip())
        elif isinstance(ing, str):
            # Extract just the food name (last word(s)) from plain string
            parts = ing.lower().strip().split()
            names.append(parts[-1] if parts else ing.lower().strip())
    names.sort()
    return hashlib.md5("_".join(names).encode()).hexdigest()


# ============================================================
# TRAINING PAIR BUILDER
# ============================================================
def build_positive_training_pair(recipe: dict, compliance: dict) -> dict:
    title       = str(recipe.get("title", "Unnamed Recipe")).strip().title()
    raw_ings    = recipe.get("ingredients", [])
    directions  = recipe.get("directions_parsed", "")
    nutrition   = recipe.get("nutrition", {})
    health_score    = compliance.get("health_score", 0)
    dietary_flags   = get_dietary_flags(nutrition)

    # Normalize ingredients to {quantity, measurement, name}
    normalized_ingredients = []
    for ing in raw_ings:
        norm = normalize_ingredient(ing)
        if norm:
            normalized_ingredients.append(norm)

    # Build constraint description for instruction
    sodium  = float(nutrition.get("sodium", 0))
    sugar   = float(nutrition.get("sugar", 0))
    protein = float(nutrition.get("protein", 0))
    fat     = float(nutrition.get("fat", 0))

    constraint_parts = []
    if sodium  < 600:  constraint_parts.append("low sodium")
    if sugar   < 15:   constraint_parts.append("low sugar")
    if protein >= 20:  constraint_parts.append("high protein")
    if fat     < 15:   constraint_parts.append("low fat")
    constraint_str = ", ".join(constraint_parts) if constraint_parts else "balanced liver-safe nutrition"

    instruction = (
        f"Generate a liver-safe recipe that is {constraint_str}. "
        f"Health score must be at least {COMPLIANCE['min_health_score']}/100. "
        f"Format ingredients as a JSON array with quantity, measurement, and name fields. "
        f"Format directions as numbered steps separated by newlines."
    )

    return {
        "instruction": instruction,
        "input": {
            "constraints": {
                "max_sodium_mg":    COMPLIANCE["max_sodium_mg"],
                "max_sugar_g":      COMPLIANCE["max_sugar_g"],
                "min_health_score": COMPLIANCE["min_health_score"],
            }
        },
        "output": {
            "recipe_name":  title,
            "description":  f"A liver-safe {title.lower()} recipe.",
            "ingredients":  normalized_ingredients,
            "directions":   directions,
            "servings":     recipe.get("servings", 2),
            "nutrition":    nutrition,
            "compliance": {
                "health_score":  health_score,
                "is_liver_safe": compliance["is_liver_safe"],
                "dietary_flags": dietary_flags,
            }
        },
        "_meta": {
            "source":          "recipes_table",
            "recipe_id":       recipe.get("id"),
            "exported_at":     datetime.now(timezone.utc).isoformat(),
            "dedup_key":       make_dedup_key(recipe),
            "compliance_pass": compliance["all_checks_passed"],
            "nutrition_source": "estimated",  # flag that nutrition was estimated
        }
    }


def build_negative_training_pair(recipe: dict, compliance: dict) -> dict:
    title      = str(recipe.get("title", "Unnamed Recipe")).strip().title()
    raw_ings   = recipe.get("ingredients", [])
    directions = recipe.get("directions_parsed", "")
    nutrition  = recipe.get("nutrition", {})

    normalized_ingredients = []
    for ing in raw_ings:
        norm = normalize_ingredient(ing)
        if norm:
            normalized_ingredients.append(norm)

    corrected_nutrition = dict(nutrition)
    correction_notes    = []

    sodium = float(nutrition.get("sodium", 0))
    if sodium > COMPLIANCE["max_sodium_mg"]:
        corrected_nutrition["sodium"] = COMPLIANCE["max_sodium_mg"] * 0.85
        correction_notes.append(
            f"Reduced sodium from {sodium:.0f}mg to under {COMPLIANCE['max_sodium_mg']}mg. "
            f"Suggest: replace regular soy sauce with low-sodium variant, reduce added salt."
        )

    sugar = float(nutrition.get("sugar", 0))
    if sugar > COMPLIANCE["max_sugar_g"]:
        corrected_nutrition["sugar"] = COMPLIANCE["max_sugar_g"] * 0.5
        correction_notes.append(
            f"Reduced sugar from {sugar:.0f}g to under {COMPLIANCE['max_sugar_g']}g. "
            f"Suggest: replace sweeteners with cinnamon or vanilla."
        )

    fat = float(nutrition.get("fat", 0))
    if fat > COMPLIANCE["max_fat_g"]:
        corrected_nutrition["fat"] = COMPLIANCE["max_fat_g"] * 0.7
        correction_notes.append(
            f"Reduced fat from {fat:.0f}g to under {COMPLIANCE['max_fat_g']}g. "
            f"Suggest: replace butter with olive oil, use lean protein."
        )

    corrected_score = calculate_liver_score(
        fat=float(corrected_nutrition.get("fat", 0)),
        sodium=float(corrected_nutrition.get("sodium", 0)),
        sugar=float(corrected_nutrition.get("sugar", 0)),
        calories=float(corrected_nutrition.get("calories", 0)),
    )

    return {
        "instruction": (
            "Review this recipe for liver health compliance. "
            "Identify all violations against the compliance rules "
            "(sodium > 2000mg, sugar > 50g, fat > 50g, health score < 50, "
            "missing nutrition, instructions < 20 chars). "
            "Output the violations found and a corrected version of the recipe."
        ),
        "input": {
            "recipe_name":  title,
            "ingredients":  normalized_ingredients,
            "directions":   directions,
            "nutrition":    nutrition,
        },
        "output": {
            "compliance_errors":   compliance.get("errors", []),
            "compliance_warnings": compliance.get("warnings", []),
            "health_score_before": compliance.get("health_score", 0),
            "health_score_after":  corrected_score,
            "corrected_recipe": {
                "recipe_name":      f"Liver-Safe {title}",
                "ingredients":      normalized_ingredients,
                "directions":       directions,
                "nutrition":        corrected_nutrition,
                "correction_notes": correction_notes,
            }
        },
        "_meta": {
            "source":      "recipes_table_non_compliant",
            "recipe_id":   recipe.get("id"),
            "exported_at": datetime.now(timezone.utc).isoformat(),
            "dedup_key":   make_dedup_key(recipe),
            "violations":  compliance.get("errors", []) + compliance.get("warnings", []),
        }
    }


# ============================================================
# INGREDIENT MATRIX
# ============================================================
INGREDIENT_MATRIX = [
    {"ingredient_name": "salmon",          "category": "protein",   "liver_impact": "beneficial",  "flags": ["high_omega3","high_protein","low_sodium"],          "typical_measurements": ["oz","g","lb"],      "preferred_for": ["NAFLD","cirrhosis","fatty_liver"], "avoid_for": []},
    {"ingredient_name": "chicken breast",  "category": "protein",   "liver_impact": "beneficial",  "flags": ["high_protein","low_fat","low_sodium"],              "typical_measurements": ["oz","g","lb"],      "preferred_for": ["NAFLD","fatty_liver"],             "avoid_for": []},
    {"ingredient_name": "lentils",         "category": "legume",    "liver_impact": "beneficial",  "flags": ["high_fiber","high_protein","low_fat"],              "typical_measurements": ["cup","cups","g"],   "preferred_for": ["NAFLD","cirrhosis"],               "avoid_for": []},
    {"ingredient_name": "chickpeas",       "category": "legume",    "liver_impact": "beneficial",  "flags": ["high_fiber","high_protein","low_fat"],              "typical_measurements": ["cup","cups","g"],   "preferred_for": ["NAFLD"],                          "avoid_for": []},
    {"ingredient_name": "tofu",            "category": "protein",   "liver_impact": "beneficial",  "flags": ["high_protein","low_fat","plant_based"],             "typical_measurements": ["oz","g","piece"],   "preferred_for": ["NAFLD","fatty_liver"],             "avoid_for": []},
    {"ingredient_name": "broccoli",        "category": "vegetable", "liver_impact": "beneficial",  "flags": ["high_fiber","low_calorie","antioxidant"],           "typical_measurements": ["cup","cups","g"],   "preferred_for": ["NAFLD","cirrhosis","fatty_liver"], "avoid_for": []},
    {"ingredient_name": "spinach",         "category": "vegetable", "liver_impact": "beneficial",  "flags": ["high_fiber","high_iron","antioxidant"],             "typical_measurements": ["cup","cups","g"],   "preferred_for": ["NAFLD","cirrhosis"],               "avoid_for": []},
    {"ingredient_name": "kale",            "category": "vegetable", "liver_impact": "beneficial",  "flags": ["high_fiber","antioxidant","low_calorie"],           "typical_measurements": ["cup","cups","g"],   "preferred_for": ["NAFLD"],                          "avoid_for": []},
    {"ingredient_name": "carrots",         "category": "vegetable", "liver_impact": "beneficial",  "flags": ["high_fiber","low_calorie","antioxidant"],           "typical_measurements": ["cup","cups","g"],   "preferred_for": ["NAFLD","fatty_liver"],             "avoid_for": []},
    {"ingredient_name": "sweet potato",    "category": "vegetable", "liver_impact": "beneficial",  "flags": ["high_fiber","complex_carb","antioxidant"],          "typical_measurements": ["cup","cups","g"],   "preferred_for": ["NAFLD","cirrhosis"],               "avoid_for": []},
    {"ingredient_name": "zucchini",        "category": "vegetable", "liver_impact": "beneficial",  "flags": ["low_calorie","high_fiber","low_sodium"],            "typical_measurements": ["cup","cups","g"],   "preferred_for": ["NAFLD","fatty_liver"],             "avoid_for": []},
    {"ingredient_name": "mixed greens",    "category": "vegetable", "liver_impact": "beneficial",  "flags": ["low_calorie","high_fiber","antioxidant"],           "typical_measurements": ["cup","cups","g"],   "preferred_for": ["NAFLD","cirrhosis","fatty_liver"], "avoid_for": []},
    {"ingredient_name": "cherry tomatoes", "category": "vegetable", "liver_impact": "beneficial",  "flags": ["antioxidant","low_calorie","low_sodium"],           "typical_measurements": ["cup","cups","g"],   "preferred_for": ["NAFLD"],                          "avoid_for": []},
    {"ingredient_name": "quinoa",          "category": "grain",     "liver_impact": "beneficial",  "flags": ["complete_protein","high_fiber","complex_carb"],     "typical_measurements": ["cup","cups","g"],   "preferred_for": ["NAFLD","fatty_liver"],             "avoid_for": []},
    {"ingredient_name": "brown rice",      "category": "grain",     "liver_impact": "beneficial",  "flags": ["high_fiber","complex_carb","low_fat"],              "typical_measurements": ["cup","cups","g"],   "preferred_for": ["NAFLD","cirrhosis"],               "avoid_for": []},
    {"ingredient_name": "oats",            "category": "grain",     "liver_impact": "beneficial",  "flags": ["high_fiber","complex_carb","low_fat"],              "typical_measurements": ["cup","cups","g"],   "preferred_for": ["NAFLD","fatty_liver"],             "avoid_for": []},
    {"ingredient_name": "olive oil",       "category": "fat",       "liver_impact": "beneficial",  "flags": ["high_omega9","anti_inflammatory","monounsaturated"],"typical_measurements": ["tbsp","tsp"],       "preferred_for": ["NAFLD","cirrhosis","fatty_liver"], "avoid_for": []},
    {"ingredient_name": "avocado",         "category": "fat",       "liver_impact": "beneficial",  "flags": ["high_fiber","monounsaturated","potassium"],         "typical_measurements": ["piece","cup","cups"],"preferred_for": ["NAFLD"],                          "avoid_for": []},
    {"ingredient_name": "lemon",           "category": "fruit",     "liver_impact": "beneficial",  "flags": ["antioxidant","low_sugar","vitamin_c"],              "typical_measurements": ["piece","tsp","tbsp"],"preferred_for": ["NAFLD","cirrhosis","fatty_liver"], "avoid_for": []},
    {"ingredient_name": "green apple",     "category": "fruit",     "liver_impact": "beneficial",  "flags": ["high_fiber","antioxidant","low_calorie"],           "typical_measurements": ["piece","cup"],       "preferred_for": ["NAFLD"],                          "avoid_for": []},
    {"ingredient_name": "berries",         "category": "fruit",     "liver_impact": "beneficial",  "flags": ["antioxidant","low_sugar","high_fiber"],             "typical_measurements": ["cup","cups","g"],   "preferred_for": ["NAFLD","fatty_liver"],             "avoid_for": []},
    {"ingredient_name": "white rice",      "category": "grain",     "liver_impact": "neutral",     "flags": ["simple_carb","low_fiber"],                          "typical_measurements": ["cup","cups","g"],   "preferred_for": [],                                 "avoid_for": ["cirrhosis"]},
    {"ingredient_name": "eggs",            "category": "protein",   "liver_impact": "neutral",     "flags": ["high_protein","moderate_cholesterol"],              "typical_measurements": ["piece","pieces"],    "preferred_for": ["NAFLD"],                          "avoid_for": []},
    {"ingredient_name": "Greek yogurt",    "category": "dairy",     "liver_impact": "neutral",     "flags": ["high_protein","probiotic","moderate_fat"],          "typical_measurements": ["cup","cups","tbsp"], "preferred_for": ["NAFLD"],                          "avoid_for": []},
    {"ingredient_name": "soy sauce",       "category": "condiment", "liver_impact": "harmful",     "flags": ["very_high_sodium","high_risk"],                     "typical_measurements": ["tbsp","tsp"],        "preferred_for": [],                                 "avoid_for": ["NAFLD","cirrhosis","fatty_liver"]},
    {"ingredient_name": "brown sugar",     "category": "sweetener", "liver_impact": "harmful",     "flags": ["high_sugar","high_risk"],                           "typical_measurements": ["tbsp","tsp","cup"],  "preferred_for": [],                                 "avoid_for": ["NAFLD","fatty_liver"]},
    {"ingredient_name": "butter",          "category": "fat",       "liver_impact": "harmful",     "flags": ["high_saturated_fat","high_risk"],                   "typical_measurements": ["tbsp","tsp","cup"],  "preferred_for": [],                                 "avoid_for": ["NAFLD","cirrhosis"]},
    {"ingredient_name": "cream",           "category": "dairy",     "liver_impact": "harmful",     "flags": ["high_fat","high_saturated_fat"],                    "typical_measurements": ["cup","cups","tbsp"], "preferred_for": [],                                 "avoid_for": ["NAFLD","cirrhosis"]},
    {"ingredient_name": "processed meat",  "category": "protein",   "liver_impact": "harmful",     "flags": ["high_sodium","high_saturated_fat","preservatives"], "typical_measurements": ["oz","g","lb"],       "preferred_for": [],                                 "avoid_for": ["NAFLD","cirrhosis","fatty_liver"]},
    {"ingredient_name": "organic",         "category": "descriptor","liver_impact": "none",        "flags": ["non_food"],                                         "typical_measurements": [],                    "preferred_for": [],                                 "avoid_for": []},
    {"ingredient_name": "natural",         "category": "descriptor","liver_impact": "none",        "flags": ["non_food"],                                         "typical_measurements": [],                    "preferred_for": [],                                 "avoid_for": []},
    {"ingredient_name": "fresh",           "category": "descriptor","liver_impact": "none",        "flags": ["non_food"],                                         "typical_measurements": [],                    "preferred_for": [],                                 "avoid_for": []},
]

def build_ingredient_matrix_pair(entry: dict) -> dict:
    is_food = entry["liver_impact"] != "none"
    return {
        "instruction": (
            f"Classify the ingredient '{entry['ingredient_name']}'. "
            f"Return: isFood (bool), category, liver_impact, flags, "
            f"typical_measurements, preferred_for, avoid_for."
        ),
        "input":  {"word": entry["ingredient_name"]},
        "output": {
            "isFood":               is_food,
            "category":             entry["category"],
            "liver_impact":         entry["liver_impact"],
            "flags":                entry["flags"],
            "typical_measurements": entry["typical_measurements"],
            "preferred_for":        entry["preferred_for"],
            "avoid_for":            entry["avoid_for"],
        },
        "_meta": {
            "source":      "ingredient_matrix",
            "exported_at": datetime.now(timezone.utc).isoformat(),
        }
    }


# ============================================================
# FETCH FROM WORKER
# ============================================================
def fetch_all_recipes() -> list:
    """
    Fetches all recipes from the 'recipes' table in a single query.
    The recipes table has no status filter — all rows are approved.
    """
    print("  Fetching recipes from 'recipes' table...")

    results = worker_query(
        action="select",
        table="recipes",
        order_by="id",
        ascending=True,
        limit=500,  # Hard cap — more than enough for current DB size
    )

    print(f"  → Total: {len(results)} recipes fetched")
    return results


def fetch_synthetic_negatives() -> list:
    """
    Generates synthetic negative examples covering all compliance threshold types.
    Used when no real non-compliant recipes exist in the DB.
    """
    pairs = []

    sodium_templates = [
        ("Teriyaki Beef Bowl",     2400, "soy sauce",       "low-sodium soy sauce"),
        ("Canned Soup Noodle Bowl",3100, "canned broth",    "homemade low-sodium broth"),
        ("Smoked Sausage Stir-Fry",2600, "smoked sausage",  "lean chicken breast"),
        ("Deli Sandwich Wrap",     2200, "deli turkey",     "fresh roasted chicken"),
        ("Salted Pretzel Casserole",2800,"pretzels",        "unsalted whole grain crackers"),
    ]
    for name, sodium, bad_ing, good_ing in sodium_templates:
        for i in range(20):
            actual_sodium = sodium + (i * 15)
            recipe = {
                "title": name,
                "ingredients": [f"4 oz protein", f"3 tbsp {bad_ing}", "1 cup white rice"],
                "directions_parsed": f"1. Cook rice.\n2. Prepare protein with {bad_ing}.\n3. Serve.",
                "nutrition": {"calories": 580.0, "fat": 18.0, "saturatedFat": 6.0,
                              "sodium": actual_sodium, "carbs": 55.0, "sugar": 12.0,
                              "protein": 28.0, "fiber": 1.0},
                "fingerprint": f"neg_sodium_{name}_{i}",
            }
            compliance = check_compliance(recipe)
            pairs.append(build_negative_training_pair(recipe, compliance))

    sugar_templates = [
        ("Chocolate Brownie Cake", 85,  "white sugar",          "honey + applesauce"),
        ("Sweetened Granola Bowl", 62,  "brown sugar",          "cinnamon + vanilla"),
        ("Fruit Punch Smoothie",   70,  "fruit punch mix",      "water + lemon"),
        ("BBQ Glazed Ribs",        58,  "bbq sauce",            "sugar-free herb marinade"),
        ("Sweetened Oatmeal",      52,  "flavored oatmeal",     "plain oats with cinnamon"),
    ]
    for name, sugar, bad_ing, good_ing in sugar_templates:
        for i in range(20):
            actual_sugar = sugar + (i * 1.5)
            recipe = {
                "title": name,
                "ingredients": [f"1 cup {bad_ing}", "2 cups flour"],
                "directions_parsed": "1. Mix ingredients.\n2. Bake until done.\n3. Cool and serve.",
                "nutrition": {"calories": 450.0, "fat": 12.0, "saturatedFat": 4.0,
                              "sodium": 180.0, "carbs": 88.0, "sugar": actual_sugar,
                              "protein": 6.0, "fiber": 0.5},
                "fingerprint": f"neg_sugar_{name}_{i}",
            }
            compliance = check_compliance(recipe)
            pairs.append(build_negative_training_pair(recipe, compliance))

    fat_templates = [
        ("Deep-Fried Chicken",       65, "deep frying",      "oven-baked with olive oil spray"),
        ("Creamy Alfredo Pasta",     58, "heavy cream",      "cauliflower cream sauce"),
        ("Bacon Cheeseburger",       72, "bacon and cheese", "lean turkey with avocado"),
        ("Butter-Basted Steak",      55, "butter basting",   "herb-crusted sirloin"),
        ("Full-Fat Cheese Quesadilla",60,"full-fat cheddar","reduced-fat cheese + vegetables"),
    ]
    for name, fat, issue, fix in fat_templates:
        for i in range(20):
            actual_fat = fat + (i * 0.8)
            recipe = {
                "title": name,
                "ingredients": ["6 oz main protein", "4 tbsp butter"],
                "directions_parsed": f"1. Prepare using {issue}.\n2. Season and serve hot.",
                "nutrition": {"calories": 680.0, "fat": actual_fat,
                              "saturatedFat": actual_fat * 0.4,
                              "sodium": 580.0, "carbs": 28.0, "sugar": 4.0,
                              "protein": 34.0, "fiber": 0.0},
                "fingerprint": f"neg_fat_{name}_{i}",
            }
            compliance = check_compliance(recipe)
            pairs.append(build_negative_training_pair(recipe, compliance))

    return pairs


# ============================================================
# MAIN EXPORT PIPELINE
# ============================================================
def run_export(mode: str, out_dir: str, dry_run: bool = False):
    os.makedirs(out_dir, exist_ok=True)
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    report = {
        "exported_at":     datetime.now(timezone.utc).isoformat(),
        "mode":            mode,
        "worker_endpoint": WORKER_QUERY_ENDPOINT,
        "auth_present":    bool(AUTH_TOKEN),
        "stats":           {}
    }

    # ── POSITIVE TRAINING PAIRS ──────────────────────────────
    if mode in ("recipes", "all"):
        print("\n[1/3] Building positive training pairs from 'recipes' table...")

        all_recipes  = fetch_all_recipes()
        seen_keys    = set()
        pairs        = []
        skipped_dup  = 0
        skipped_fail = 0

        for recipe in all_recipes:
            key = make_dedup_key(recipe)
            if key in seen_keys:
                skipped_dup += 1
                continue
            seen_keys.add(key)

            # Parse directions from JSON-stringified array
            recipe["directions_parsed"] = parse_directions(recipe.get("directions", ""))

            # Estimate nutrition (table has no nutrition field)
            recipe["nutrition"] = estimate_nutrition(
                recipe.get("ingredients", []),
                recipe.get("title", "")
            )
            recipe["_nutrition_estimated"] = True

            compliance = check_compliance(recipe)

            if not compliance["all_checks_passed"]:
                skipped_fail += 1
                continue

            pairs.append(build_positive_training_pair(recipe, compliance))

        out_path = os.path.join(out_dir, f"recipes_v1_{timestamp}.jsonl")
        if not dry_run and pairs:
            with open(out_path, "w", encoding="utf-8") as f:
                for pair in pairs:
                    f.write(json.dumps(pair, ensure_ascii=False) + "\n")

        print(f"  ✓ {len(pairs)} positive pairs {'would be written' if dry_run else 'written'} → {out_path}")
        print(f"    Fetched: {len(all_recipes)}, Skipped: {skipped_dup} duplicates, {skipped_fail} compliance failures")

        report["stats"]["positive"] = {
            "total_fetched":      len(all_recipes),
            "pairs_written":      len(pairs),
            "skipped_duplicates": skipped_dup,
            "skipped_compliance": skipped_fail,
            "output_file":        out_path,
            "note":               "nutrition estimated from ingredient names — no nutrition field in recipes table",
        }

    # ── NEGATIVE TRAINING PAIRS ──────────────────────────────
    if mode in ("negative", "all"):
        print("\n[2/3] Building negative training pairs (synthetic)...")

        neg_pairs = fetch_synthetic_negatives()
        out_path  = os.path.join(out_dir, f"negative_examples_v1_{timestamp}.jsonl")

        if not dry_run and neg_pairs:
            with open(out_path, "w", encoding="utf-8") as f:
                for pair in neg_pairs:
                    f.write(json.dumps(pair, ensure_ascii=False) + "\n")

        print(f"  ✓ {len(neg_pairs)} negative pairs {'would be written' if dry_run else 'written'} → {out_path}")

        report["stats"]["negative"] = {
            "total_pairs": len(neg_pairs),
            "output_file": out_path,
        }

    # ── INGREDIENT MATRIX ────────────────────────────────────
    if mode in ("matrix", "all"):
        print("\n[3/3] Building ingredient matrix training pairs...")

        matrix_pairs = [build_ingredient_matrix_pair(e) for e in INGREDIENT_MATRIX]
        out_path     = os.path.join(out_dir, f"ingredient_matrix_v1_{timestamp}.jsonl")

        if not dry_run and matrix_pairs:
            with open(out_path, "w", encoding="utf-8") as f:
                for pair in matrix_pairs:
                    f.write(json.dumps(pair, ensure_ascii=False) + "\n")

        print(f"  ✓ {len(matrix_pairs)} matrix pairs {'would be written' if dry_run else 'written'} → {out_path}")

        report["stats"]["ingredient_matrix"] = {
            "total_entries": len(matrix_pairs),
            "output_file":   out_path,
        }

    # ── EXPORT REPORT ────────────────────────────────────────
    report_path = os.path.join(out_dir, f"export_report_{timestamp}.json")
    if not dry_run:
        with open(report_path, "w", encoding="utf-8") as f:
            json.dump(report, f, indent=2, ensure_ascii=False)

    print(f"\n{'✅ DRY RUN complete — no files written' if dry_run else '✅ Export complete'}")
    if not dry_run:
        print(f"   Report → {report_path}")

    return report


# ============================================================
# ENTRY POINT
# ============================================================
if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="LiverWise LoRA Training Data Exporter")
    parser.add_argument("--mode",    choices=["recipes","negative","matrix","all"], default="all")
    parser.add_argument("--out",     default=OUTPUT_DIR)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    if not AUTH_TOKEN and not args.dry_run:
        print("WARNING: LIVERWISE_AUTH_TOKEN not set — running dry-run.")
        args.dry_run = True

    run_export(mode=args.mode, out_dir=args.out, dry_run=args.dry_run)