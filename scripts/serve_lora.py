#!/usr/bin/env python3
# scripts/serve_lora.py
# BBRS LoRA Inference Server
#
# Loads a trained LoRA model and exposes a REST API that matches
# the endpoint pattern lora_inference_service.dart already expects.
#
# Endpoints:
#   POST /recipes/search          ← SuggestedRecipesPage
#   POST /recipes/check-ingredient ← food_classifier_service.dart
#   POST /compliance/prescreen    ← submit_recipe.dart
#   GET  /health                  ← status check
#
# Usage:
#   source scripts/.venv/bin/activate
#   pip install -r scripts/requirements_train.txt
#   python3 scripts/serve_lora.py --module recipes
#
# Then in AppConfig, set your Cloudflare Worker URL to point
# to http://localhost:8080 for local testing, or deploy this
# server behind a reverse proxy for production.
#
# To run all three modules simultaneously (recommended):
#   python3 scripts/serve_lora.py --module recipes --port 8080 &
#   python3 scripts/serve_lora.py --module compliance --port 8081 &
#   python3 scripts/serve_lora.py --module classifier --port 8082 &

import os
import sys
import json
import argparse
import logging
import time
from pathlib import Path
from datetime import datetime
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse

# ── Logging ───────────────────────────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s',
    datefmt='%H:%M:%S',
)
log = logging.getLogger(__name__)

# ── Paths ─────────────────────────────────────────────────────────────────────
PROJECT_ROOT = Path(__file__).parent.parent
MODELS_DIR   = PROJECT_ROOT / 'models'

MODULE_TO_DIR = {
    'recipes':    MODELS_DIR / 'bbrs_lora_recipes',
    'compliance': MODELS_DIR / 'bbrs_lora_compliance',
    'classifier': MODELS_DIR / 'bbrs_lora_classifier',
}

# ── Global model state ────────────────────────────────────────────────────────
# Loaded once at startup, shared across all requests.
_model     = None
_tokenizer = None
_module    = None
_device    = None

# ── Model loading ─────────────────────────────────────────────────────────────

def load_model(module, base_model_override=None):
    global _model, _tokenizer, _module, _device

    model_dir = MODULE_TO_DIR.get(module)
    if not model_dir or not model_dir.exists():
        log.error(f'Model directory not found: {model_dir}')
        log.error(f'Run training first: python3 scripts/train_lora.py --module {module}')
        sys.exit(1)

    # Read base model from training metadata
    metadata_path = model_dir / 'training_metadata.json'
    base_model = 'microsoft/Phi-3-mini-4k-instruct'
    if metadata_path.exists():
        with open(metadata_path) as f:
            metadata = json.load(f)
            base_model = metadata.get('base_model', base_model)
            log.info(f'Loaded training metadata: {metadata}')

    if base_model_override:
        base_model = base_model_override

    log.info(f'Loading base model: {base_model}')
    log.info(f'Loading LoRA adapter: {model_dir}')

    try:
        import torch
        from transformers import AutoModelForCausalLM, AutoTokenizer
        from peft import PeftModel
    except ImportError as e:
        log.error(f'Missing dependency: {e}')
        log.error('Run: pip install -r scripts/requirements_train.txt')
        sys.exit(1)

    # Device
    if torch.backends.mps.is_available():
        _device = 'mps'
        log.info('Using Apple Silicon MPS')
    elif torch.cuda.is_available():
        _device = 'cuda'
        log.info(f'Using CUDA: {torch.cuda.get_device_name(0)}')
    else:
        _device = 'cpu'
        log.warning('Using CPU — inference will be slow')

    torch_dtype = torch.float16 if _device in ('mps', 'cuda') else torch.float32

    # Load tokenizer
    _tokenizer = AutoTokenizer.from_pretrained(
        str(model_dir),
        trust_remote_code=True,
    )
    if _tokenizer.pad_token is None:
        _tokenizer.pad_token = _tokenizer.eos_token

    # Load base model + LoRA adapter
    base = AutoModelForCausalLM.from_pretrained(
        base_model,
        torch_dtype=torch_dtype,
        trust_remote_code=True,
    )
    _model = PeftModel.from_pretrained(base, str(model_dir))

    if _device != 'cpu':
        _model = _model.to(_device)

    _model.eval()
    _module = module

    log.info(f'✅ Model loaded — serving {module} module on {_device}')

# ── Inference helpers ─────────────────────────────────────────────────────────

def generate(prompt, max_new_tokens=512, temperature=0.3):
    """Run inference with the loaded LoRA model."""
    import torch

    inputs = _tokenizer(prompt, return_tensors='pt', truncation=True, max_length=1024)

    if _device != 'cpu':
        inputs = {k: v.to(_device) for k, v in inputs.items()}

    with torch.no_grad():
        output_ids = _model.generate(
            **inputs,
            max_new_tokens=max_new_tokens,
            temperature=temperature,
            do_sample=(temperature > 0),
            pad_token_id=_tokenizer.eos_token_id,
            eos_token_id=_tokenizer.eos_token_id,
        )

    # Decode only the new tokens (not the prompt)
    new_ids = output_ids[0][inputs['input_ids'].shape[1]:]
    return _tokenizer.decode(new_ids, skip_special_tokens=True)

def build_recipe_prompt(ingredients, liver_health_score, limit, offset):
    """Build a Phi-3 prompt for recipe search."""
    constraint = 'liver-safe'
    if liver_health_score < 50:
        constraint = 'liver-detox focused, very low sodium and sugar'
    elif liver_health_score < 75:
        constraint = 'liver-supportive, moderate restrictions'

    return (
        f'<|system|>\n'
        f'You are a clinical nutrition AI. Generate {limit} complete, '
        f'{constraint} recipes using these ingredients. '
        f'Return valid JSON array of recipe objects with fields: '
        f'id, title, description, ingredients (array), instructions, health_score.\n'
        f'No placeholders. Whole foods only. health_score must be 0-100.<|end|>\n'
        f'<|user|>\n'
        f'Ingredients available: {", ".join(ingredients)}\n'
        f'Liver health score: {liver_health_score}/100\n'
        f'Generate {limit} recipes (offset {offset}).<|end|>\n'
        f'<|assistant|>\n'
    )

def build_classifier_prompt(ingredient):
    """Build a Phi-3 prompt for ingredient classification."""
    return (
        f'<|system|>\n'
        f'You are a food ingredient classifier. Respond with JSON only: '
        f'{{"isFood": bool, "category": string, "liverImpact": string, "confidence": float}}<|end|>\n'
        f'<|user|>\nClassify this word: "{ingredient}"<|end|>\n'
        f'<|assistant|>\n'
    )

def build_compliance_prompt(recipe_name, ingredients, directions):
    """Build a Phi-3 prompt for compliance prescreening."""
    return (
        f'<|system|>\n'
        f'You are a liver health recipe compliance reviewer. '
        f'Check for: sodium > 2000mg, sugar > 50g, fat > 50g, health score < 50. '
        f'Return JSON: {{"passedCompliance": bool, "complianceErrors": [], '
        f'"complianceWarnings": [], "correctionNotes": string or null}}<|end|>\n'
        f'<|user|>\n'
        f'Recipe: {recipe_name}\n'
        f'Ingredients: {json.dumps(ingredients)}\n'
        f'Directions: {directions}<|end|>\n'
        f'<|assistant|>\n'
    )

def try_parse_json(text):
    """Attempt to parse JSON from model output, with fallback."""
    text = text.strip()
    # Find first { or [ in the output
    for start_char, end_char in [('{', '}'), ('[', ']')]:
        start = text.find(start_char)
        end   = text.rfind(end_char)
        if start != -1 and end != -1 and end > start:
            try:
                return json.loads(text[start:end+1])
            except json.JSONDecodeError:
                pass
    return None

# ── HTTP request handler ──────────────────────────────────────────────────────

class LoRAHandler(BaseHTTPRequestHandler):

    def log_message(self, format, *args):
        log.info(f'{self.address_string()} — {format % args}')

    def send_json(self, data, status=200):
        body = json.dumps(data, indent=2).encode('utf-8')
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        self.wfile.write(body)

    def send_error_json(self, message, status=500):
        self.send_json({'error': message, 'lora_enabled': True}, status)

    def read_body(self):
        length = int(self.headers.get('Content-Length', 0))
        if length == 0:
            return {}
        raw = self.rfile.read(length)
        try:
            return json.loads(raw)
        except json.JSONDecodeError:
            return {}

    def do_OPTIONS(self):
        self.send_response(200)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'POST, GET, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
        self.end_headers()

    def do_GET(self):
        path = urlparse(self.path).path
        if path == '/health':
            self.send_json({
                'status':  'ok',
                'module':  _module,
                'device':  _device,
                'time':    datetime.now().isoformat(),
            })
        else:
            self.send_error_json('Not found', 404)

    def do_POST(self):
        path = urlparse(self.path).path
        body = self.read_body()
        start = time.time()

        try:
            if path == '/recipes/search':
                self._handle_recipe_search(body)
            elif path == '/recipes/check-ingredient':
                self._handle_check_ingredient(body)
            elif path == '/compliance/prescreen':
                self._handle_compliance_prescreen(body)
            else:
                self.send_error_json('Unknown endpoint', 404)
        except Exception as e:
            log.error(f'Request error: {e}', exc_info=True)
            self.send_error_json(str(e))

        elapsed = time.time() - start
        log.info(f'{path} completed in {elapsed:.1f}s')

    # ── Endpoint handlers ──────────────────────────────────────────────────────

    def _handle_recipe_search(self, body):
        """
        POST /recipes/search
        Input:  { ingredients: [...], liverHealthScore: int, limit: int, offset: int }
        Output: { recipes: [...], source: "lora" }

        Maps to: SuggestedRecipesPage._loadRecipes() LoRA branch
        """
        ingredients        = body.get('ingredients', [])
        liver_health_score = body.get('liverHealthScore', 70)
        limit              = body.get('limit', 2)
        offset             = body.get('offset', 0)

        if not ingredients:
            self.send_json({'recipes': [], 'source': 'lora'})
            return

        prompt = build_recipe_prompt(ingredients, liver_health_score, limit, offset)
        log.info(f'Generating {limit} recipes for ingredients: {ingredients}')

        raw_output = generate(prompt, max_new_tokens=800)
        parsed     = try_parse_json(raw_output)

        if parsed is None:
            log.warning('Could not parse recipe JSON from model output')
            self.send_json({'recipes': [], 'source': 'lora', 'parse_error': True})
            return

        # Normalize to list
        recipes = parsed if isinstance(parsed, list) else [parsed]

        # Ensure required fields exist
        normalized = []
        for i, r in enumerate(recipes[:limit]):
            normalized.append({
                'id':           r.get('id', f'lora_{offset + i}'),
                'title':        r.get('title', r.get('name', 'Recipe')),
                'description':  r.get('description', ''),
                'ingredients':  r.get('ingredients', []),
                'instructions': r.get('instructions', r.get('directions', '')),
                'health_score': r.get('health_score', liver_health_score),
            })

        self.send_json({'recipes': normalized, 'source': 'lora'})

    def _handle_check_ingredient(self, body):
        """
        POST /recipes/check-ingredient
        Input:  { ingredient: string }
        Output: { exists: bool, isFood: bool, category: string }

        Maps to: SuggestedRecipesPage._checkIngredientsExist() LoRA branch
        """
        ingredient = body.get('ingredient', '').strip()

        if not ingredient:
            self.send_json({'exists': False, 'isFood': False})
            return

        prompt     = build_classifier_prompt(ingredient)
        raw_output = generate(prompt, max_new_tokens=100, temperature=0.1)
        parsed     = try_parse_json(raw_output)

        if parsed is None:
            # Fall back to simple heuristic
            is_food = len(ingredient) > 2 and ingredient.isalpha()
            self.send_json({'exists': is_food, 'isFood': is_food, 'source': 'lora_fallback'})
            return

        is_food = parsed.get('isFood', False)
        self.send_json({
            'exists':     is_food,
            'isFood':     is_food,
            'category':   parsed.get('category', 'unknown'),
            'confidence': parsed.get('confidence', 0.0),
            'source':     'lora',
        })

    def _handle_compliance_prescreen(self, body):
        """
        POST /compliance/prescreen
        Input:  { recipeName: string, ingredients: [...], directions: string }
        Output: { passedCompliance: bool, complianceErrors: [], complianceWarnings: [],
                  correctionNotes: string|null }

        Maps to: submit_recipe.dart _submitForCommunityReview() LoRA branch
        """
        recipe_name = body.get('recipeName', '')
        ingredients = body.get('ingredients', [])
        directions  = body.get('directions', '')

        prompt     = build_compliance_prompt(recipe_name, ingredients, directions)
        raw_output = generate(prompt, max_new_tokens=400, temperature=0.1)
        parsed     = try_parse_json(raw_output)

        if parsed is None:
            # If we can't parse compliance output, pass through (don't block submission)
            self.send_json({
                'passedCompliance':   True,
                'complianceErrors':   [],
                'complianceWarnings': ['LoRA compliance check could not parse output'],
                'correctionNotes':    None,
                'source':             'lora_fallback',
            })
            return

        self.send_json({
            'passedCompliance':   parsed.get('passedCompliance', True),
            'complianceErrors':   parsed.get('complianceErrors', []),
            'complianceWarnings': parsed.get('complianceWarnings', []),
            'correctionNotes':    parsed.get('correctionNotes'),
            'source':             'lora',
        })

# ── Main ──────────────────────────────────────────────────────────────────────

def parse_args():
    parser = argparse.ArgumentParser(description='BBRS LoRA Inference Server')
    parser.add_argument(
        '--module',
        choices=['recipes', 'compliance', 'classifier'],
        default='recipes',
        help='Which LoRA module to serve (default: recipes)'
    )
    parser.add_argument(
        '--port',
        type=int,
        default=8080,
        help='Port to listen on (default: 8080)'
    )
    parser.add_argument(
        '--host',
        default='127.0.0.1',
        help='Host to bind to (default: 127.0.0.1 — local only)'
    )
    parser.add_argument(
        '--base-model',
        default=None,
        help='Override base model ID'
    )
    return parser.parse_args()

def main():
    args = parse_args()

    log.info('=' * 60)
    log.info(f'BBRS LoRA Inference Server — {args.module.upper()} module')
    log.info('=' * 60)

    # Load model
    load_model(args.module, args.base_model)

    # Start server
    server = HTTPServer((args.host, args.port), LoRAHandler)
    log.info(f'✅ Server running at http://{args.host}:{args.port}')
    log.info(f'   Endpoints:')
    log.info(f'     GET  /health')
    log.info(f'     POST /recipes/search')
    log.info(f'     POST /recipes/check-ingredient')
    log.info(f'     POST /compliance/prescreen')
    log.info(f'')
    log.info(f'   To test: curl http://{args.host}:{args.port}/health')
    log.info(f'   Press Ctrl+C to stop.')

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        log.info('Shutting down server...')
        server.shutdown()

if __name__ == '__main__':
    main()