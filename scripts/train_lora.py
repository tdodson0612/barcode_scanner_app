#!/usr/bin/env python3
# scripts/train_lora.py
# BBRS LoRA Training Script
#
# Base model:  microsoft/Phi-3-mini-4k-instruct (3.8B)
# Hardware:    Apple Silicon Mac (16GB unified memory) — uses MPS
# Framework:   Hugging Face Transformers + PEFT + PyTorch
#
# Usage:
#   source scripts/.venv/bin/activate
#   pip install -r scripts/requirements_train.txt
#   python3 scripts/train_lora.py --module recipes
#   python3 scripts/train_lora.py --module compliance
#   python3 scripts/train_lora.py --module classifier
#
# Output:
#   models/bbrs_lora_recipes/       ← Recipe Generator (Model A)
#   models/bbrs_lora_compliance/    ← Compliance Reviewer (Model B)
#   models/bbrs_lora_classifier/    ← Food Classifier (Model C)
#
# Each output directory contains:
#   adapter_config.json
#   adapter_model.safetensors
#   tokenizer files
#
# To resume training from a checkpoint:
#   python3 scripts/train_lora.py --module recipes --resume

import os
import sys
import json
import argparse
import logging
from pathlib import Path
from datetime import datetime

# ── Logging ───────────────────────────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s',
    datefmt='%H:%M:%S',
)
log = logging.getLogger(__name__)

# ── Paths ─────────────────────────────────────────────────────────────────────
PROJECT_ROOT = Path(__file__).parent.parent
DATASETS_DIR = PROJECT_ROOT / 'datasets' / 'train'
MODELS_DIR   = PROJECT_ROOT / 'models'
LOGS_DIR     = PROJECT_ROOT / 'logs'

MODELS_DIR.mkdir(exist_ok=True)
LOGS_DIR.mkdir(exist_ok=True)

# ── Module config ─────────────────────────────────────────────────────────────
# Each LoRA module trains on different data files and saves to a different dir.

MODULE_CONFIG = {
    'recipes': {
        'data_files':  ['recipes_v1_*.jsonl'],
        'output_dir':  MODELS_DIR / 'bbrs_lora_recipes',
        'description': 'Recipe Generator (Model A) — liver-safe recipe generation',
        'epochs':      3,
        'system_prompt': (
            'You are a clinical nutrition AI specialized in liver-safe, '
            'Mediterranean-style recipes for bariatric patients. '
            'Always output fully structured recipes with no placeholders. '
            'Use whole foods only. Enforce sodium < 2000mg, sugar < 50g, fat < 50g.'
        ),
    },
    'compliance': {
        'data_files':  ['negative_examples_v1_*.jsonl'],
        'output_dir':  MODELS_DIR / 'bbrs_lora_compliance',
        'description': 'Compliance Reviewer (Model B) — recipe violation detection and correction',
        'epochs':      3,
        'system_prompt': (
            'You are a recipe compliance reviewer for a liver health application. '
            'Identify nutritional violations (high sodium, sugar, fat) and structural '
            'errors (missing nutrition, unformatted ingredients, unnumbered directions). '
            'Always return the corrected recipe alongside violation details.'
        ),
    },
    'classifier': {
        'data_files':  ['ingredient_matrix_v1_*.jsonl'],
        'output_dir':  MODELS_DIR / 'bbrs_lora_classifier',
        'description': 'Food Classifier (Model C) — ingredient recognition and liver impact',
        'epochs':      5,  # More epochs for the smaller classifier dataset
        'system_prompt': (
            'You are a food ingredient classifier for a liver health application. '
            'For each word or phrase, determine if it is a food ingredient, '
            'its category, liver health impact, and confidence score.'
        ),
    },
}

# ── Argument parsing ──────────────────────────────────────────────────────────

def parse_args():
    parser = argparse.ArgumentParser(
        description='BBRS LoRA Training Script',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python3 scripts/train_lora.py --module recipes
  python3 scripts/train_lora.py --module compliance --epochs 5
  python3 scripts/train_lora.py --module recipes --dry-run
        """
    )
    parser.add_argument(
        '--module',
        choices=['recipes', 'compliance', 'classifier'],
        required=True,
        help='Which LoRA module to train'
    )
    parser.add_argument(
        '--epochs',
        type=int,
        default=None,
        help='Override number of training epochs'
    )
    parser.add_argument(
        '--resume',
        action='store_true',
        help='Resume training from existing checkpoint'
    )
    parser.add_argument(
        '--dry-run',
        action='store_true',
        help='Validate dataset and config without training'
    )
    parser.add_argument(
        '--base-model',
        default='microsoft/Phi-3-mini-4k-instruct',
        help='HuggingFace model ID to use as base (default: Phi-3-mini)'
    )
    return parser.parse_args()

# ── Dataset loading ───────────────────────────────────────────────────────────

def load_jsonl_files(data_files_patterns):
    """Load all JSONL files matching patterns from the train directory."""
    import glob
    records = []
    for pattern in data_files_patterns:
        matches = sorted(glob.glob(str(DATASETS_DIR / pattern)))
        if not matches:
            log.warning(f'No files found matching: {DATASETS_DIR / pattern}')
            continue
        for filepath in matches:
            log.info(f'Loading: {filepath}')
            with open(filepath, 'r', encoding='utf-8') as f:
                for line_num, line in enumerate(f, 1):
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        records.append(json.loads(line))
                    except json.JSONDecodeError as e:
                        log.warning(f'  Skipping malformed line {line_num}: {e}')

    log.info(f'Loaded {len(records)} training records total')
    return records

def format_record_for_training(record, system_prompt):
    """
    Convert a LoRA training pair into the Phi-3 chat format.

    Phi-3 format:
      <|system|>SYSTEM<|end|>
      <|user|>USER<|end|>
      <|assistant|>ASSISTANT<|end|>
    """
    instruction = record.get('instruction', '')
    input_text  = ''

    # Pull input context if present
    if 'input' in record and record['input']:
        inp = record['input']
        if isinstance(inp, dict):
            parts = []
            if inp.get('diseaseType'):
                parts.append(f"Disease type: {inp['diseaseType']}")
            if inp.get('word'):
                parts.append(f"Word: {inp['word']}")
            if inp.get('rawRecipe'):
                raw = inp['rawRecipe']
                if isinstance(raw, dict):
                    parts.append(f"Recipe: {raw.get('recipeName', '')}")
            input_text = '\n'.join(parts)
        else:
            input_text = str(inp)

    # Build user message
    user_msg = instruction
    if input_text:
        user_msg = f'{instruction}\n\nContext:\n{input_text}'

    # Build assistant response from output
    output = record.get('output', {})
    if isinstance(output, dict):
        assistant_msg = json.dumps(output, indent=2)
    else:
        assistant_msg = str(output)

    # Phi-3 format
    formatted = (
        f'<|system|>\n{system_prompt}<|end|>\n'
        f'<|user|>\n{user_msg}<|end|>\n'
        f'<|assistant|>\n{assistant_msg}<|end|>'
    )
    return formatted

def validate_dataset(records, system_prompt):
    """Validate dataset quality before training."""
    errors = []
    for i, record in enumerate(records):
        if 'instruction' not in record:
            errors.append(f'Record {i}: missing "instruction" field')
        if 'output' not in record:
            errors.append(f'Record {i}: missing "output" field')
        # Check for placeholders
        text = json.dumps(record)
        if '(placeholder)' in text.lower() or 'TODO' in text:
            errors.append(f'Record {i}: contains placeholder text')

    if errors:
        log.error(f'Dataset validation failed with {len(errors)} errors:')
        for e in errors[:10]:
            log.error(f'  {e}')
        if len(errors) > 10:
            log.error(f'  ... and {len(errors) - 10} more')
        return False

    log.info(f'✅ Dataset validation passed — {len(records)} clean records')

    # Format one example to verify
    sample = format_record_for_training(records[0], system_prompt)
    log.info(f'Sample formatted record ({len(sample)} chars):')
    log.info(sample[:300] + '...' if len(sample) > 300 else sample)
    return True

# ── Training ──────────────────────────────────────────────────────────────────

def train(args, config, records):
    """Run LoRA fine-tuning."""
    try:
        import torch
        from transformers import (
            AutoModelForCausalLM,
            AutoTokenizer,
            TrainingArguments,
            Trainer,
            DataCollatorForLanguageModeling,
        )
        from peft import LoraConfig, get_peft_model, TaskType
        from datasets import Dataset
    except ImportError as e:
        log.error(f'Missing dependency: {e}')
        log.error('Run: pip install -r scripts/requirements_train.txt')
        sys.exit(1)

    # ── Device setup (Apple Silicon MPS) ──────────────────────────────────────
    if torch.backends.mps.is_available():
        device = 'mps'
        log.info('✅ Using Apple Silicon MPS (Metal Performance Shaders)')
    elif torch.cuda.is_available():
        device = 'cuda'
        log.info(f'✅ Using CUDA GPU: {torch.cuda.get_device_name(0)}')
    else:
        device = 'cpu'
        log.warning('⚠️  No GPU found — training on CPU (very slow)')

    output_dir = config['output_dir']
    epochs     = args.epochs or config['epochs']
    base_model = args.base_model

    log.info(f'Base model:  {base_model}')
    log.info(f'Output dir:  {output_dir}')
    log.info(f'Epochs:      {epochs}')
    log.info(f'Records:     {len(records)}')

    # ── Load tokenizer ────────────────────────────────────────────────────────
    log.info('Loading tokenizer...')
    tokenizer = AutoTokenizer.from_pretrained(
        base_model,
        trust_remote_code=True,
    )
    if tokenizer.pad_token is None:
        tokenizer.pad_token = tokenizer.eos_token

    # ── Load base model (4-bit quantization for 16GB RAM) ────────────────────
    log.info('Loading base model (this may take a few minutes)...')

    # On Apple Silicon we use float16 instead of bfloat16
    torch_dtype = torch.float16 if device == 'mps' else torch.bfloat16

    model = AutoModelForCausalLM.from_pretrained(
        base_model,
        torch_dtype=torch_dtype,
        trust_remote_code=True,
        # Note: bitsandbytes 4-bit quant not supported on MPS
        # If you have a CUDA GPU, add: load_in_4bit=True
    )

    if device == 'mps':
        model = model.to('mps')

    # ── Apply LoRA ────────────────────────────────────────────────────────────
    lora_config = LoraConfig(
        r=16,                          # Rank — higher = more capacity, more VRAM
        lora_alpha=32,                 # Scaling factor
        target_modules=[               # Phi-3 attention projection layers
            'q_proj',
            'v_proj',
            'k_proj',
            'o_proj',
        ],
        lora_dropout=0.05,
        bias='none',
        task_type=TaskType.CAUSAL_LM,
    )

    model = get_peft_model(model, lora_config)
    model.print_trainable_parameters()

    # ── Prepare dataset ───────────────────────────────────────────────────────
    log.info('Formatting records for training...')
    system_prompt = config['system_prompt']
    formatted_texts = [
        format_record_for_training(r, system_prompt) for r in records
    ]

    def tokenize(examples):
        return tokenizer(
            examples['text'],
            truncation=True,
            max_length=1024,
            padding=False,
        )

    hf_dataset = Dataset.from_dict({'text': formatted_texts})
    tokenized  = hf_dataset.map(tokenize, batched=True, remove_columns=['text'])

    # ── Training arguments ────────────────────────────────────────────────────
    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
    log_dir   = LOGS_DIR / f'lora_{args.module}_{timestamp}'

    training_args = TrainingArguments(
        output_dir=str(output_dir / 'checkpoints'),
        num_train_epochs=epochs,
        per_device_train_batch_size=1,      # Keep at 1 for 16GB
        gradient_accumulation_steps=8,      # Effective batch size = 8
        learning_rate=2e-4,
        warmup_steps=10,
        logging_steps=10,
        save_steps=50,
        save_total_limit=2,                 # Keep only 2 checkpoints
        fp16=(device != 'mps'),             # fp16 on CUDA, off on MPS
        bf16=False,
        optim='adamw_torch',
        logging_dir=str(log_dir),
        report_to='none',                   # Disable W&B etc.
        dataloader_pin_memory=False,        # Required for MPS
        resume_from_checkpoint=args.resume,
    )

    data_collator = DataCollatorForLanguageModeling(
        tokenizer=tokenizer,
        mlm=False,
    )

    trainer = Trainer(
        model=model,
        args=training_args,
        train_dataset=tokenized,
        data_collator=data_collator,
    )

    # ── Train ─────────────────────────────────────────────────────────────────
    log.info(f'Starting training — {epochs} epoch(s), {len(records)} records...')
    log.info('This will take approximately 30–90 minutes on Apple Silicon M-series.')

    trainer.train(resume_from_checkpoint=args.resume)

    # ── Save ──────────────────────────────────────────────────────────────────
    log.info(f'Saving LoRA adapter to {output_dir}...')
    output_dir.mkdir(parents=True, exist_ok=True)
    model.save_pretrained(str(output_dir))
    tokenizer.save_pretrained(str(output_dir))

    # Save training metadata
    metadata = {
        'module':     args.module,
        'base_model': base_model,
        'epochs':     epochs,
        'records':    len(records),
        'trained_at': datetime.now().isoformat(),
        'device':     device,
    }
    with open(output_dir / 'training_metadata.json', 'w') as f:
        json.dump(metadata, f, indent=2)

    log.info(f'✅ Training complete. Model saved to: {output_dir}')
    log.info(f'   Next step: python3 scripts/serve_lora.py --module {args.module}')

# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    args   = parse_args()
    config = MODULE_CONFIG[args.module]

    log.info('=' * 60)
    log.info(f'BBRS LoRA Training — {args.module.upper()} module')
    log.info(f'{config["description"]}')
    log.info('=' * 60)

    # Load data
    records = load_jsonl_files(config['data_files'])

    if not records:
        log.error('No training records found. Run the pipeline first:')
        log.error('  ./scripts/run_pipeline.sh --mode all')
        sys.exit(1)

    # Validate
    if not validate_dataset(records, config['system_prompt']):
        log.error('Fix dataset errors before training.')
        sys.exit(1)

    if args.dry_run:
        log.info('✅ Dry run complete — dataset is valid. Remove --dry-run to train.')
        sys.exit(0)

    log.info(f'Phase 1 target: 1,000 recipe pairs (current: {len(records)})')
    if len(records) < 100:
        log.warning(
            f'Only {len(records)} records — minimum recommended is 100 for meaningful training. '
            'Approve more recipes in the app and re-run the pipeline first.'
        )
        response = input('Continue anyway? (y/N): ').strip().lower()
        if response != 'y':
            log.info('Aborted. Collect more data and try again.')
            sys.exit(0)

    # Train
    train(args, config, records)

if __name__ == '__main__':
    main()