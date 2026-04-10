#!/usr/bin/env bash
# =============================================================
# scripts/run_pipeline.sh
# LiverWise LoRA Training Pipeline Orchestrator
#
# Runs the full dataset export → validation → deduplication →
# training prep sequence. Safe to run repeatedly — all steps
# are idempotent. Does NOT touch any Flutter/Dart code.
#
# Usage:
#   chmod +x scripts/run_pipeline.sh
#   ./scripts/run_pipeline.sh [--mode all|recipes|negative|matrix]
#                             [--skip-export]
#                             [--skip-validate]
#                             [--dry-run]
#
# Required env vars (set in .env or shell):
#   LIVERWISE_AUTH_TOKEN   — Supabase session token for Worker auth
#
# Optional env vars:
#   CLOUDFLARE_WORKER_URL  — override default Worker URL
#   DATASET_DIR            — override default ./datasets
#   PYTHON                 — override python binary (default: python3)
# =============================================================

set -euo pipefail

# ── Color helpers ────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

log_info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_ok()      { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*"; }
log_section() { echo -e "\n${BOLD}${CYAN}══════════════════════════════════════════${NC}"; echo -e "${BOLD}${CYAN}  $*${NC}"; echo -e "${BOLD}${CYAN}══════════════════════════════════════════${NC}"; }

# ── Parse args ───────────────────────────────────────────────
MODE="all"
SKIP_EXPORT=false
SKIP_VALIDATE=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --mode)         MODE="$2";         shift 2 ;;
        --skip-export)  SKIP_EXPORT=true;  shift   ;;
        --skip-validate) SKIP_VALIDATE=true; shift  ;;
        --dry-run)      DRY_RUN=true;      shift   ;;
        *)
            log_error "Unknown argument: $1"
            echo "Usage: $0 [--mode all|recipes|negative|matrix] [--skip-export] [--skip-validate] [--dry-run]"
            exit 1
            ;;
    esac
done

# ── Config ───────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DATASET_DIR="${DATASET_DIR:-$PROJECT_ROOT/datasets}"
PYTHON="${PYTHON:-python3}"
EXPORT_SCRIPT="$SCRIPT_DIR/export_training_data.py"
TIMESTAMP="$(date -u +%Y%m%d_%H%M%S)"
LOG_FILE="$DATASET_DIR/pipeline_${TIMESTAMP}.log"

# ── Auth check ───────────────────────────────────────────────
if [[ -z "${LIVERWISE_AUTH_TOKEN:-}" ]]; then
    # Try loading from project .env
    ENV_FILE="$PROJECT_ROOT/.env"
    if [[ -f "$ENV_FILE" ]]; then
        # shellcheck source=/dev/null
        set -o allexport
        source "$ENV_FILE"
        set +o allexport
        log_info "Loaded env from $ENV_FILE"
    fi
fi

if [[ -z "${LIVERWISE_AUTH_TOKEN:-}" ]] && [[ "$DRY_RUN" == false ]]; then
    log_warn "LIVERWISE_AUTH_TOKEN not set — forcing dry-run mode."
    log_warn "To export real data: export LIVERWISE_AUTH_TOKEN=<your_token>"
    DRY_RUN=true
fi

# ── Create output dirs ───────────────────────────────────────
mkdir -p "$DATASET_DIR"
mkdir -p "$DATASET_DIR/validated"
mkdir -p "$DATASET_DIR/deduped"
mkdir -p "$DATASET_DIR/train"
mkdir -p "$DATASET_DIR/eval"

# ── Logging helper (Mac-compatible, no tee process substitution) ──
_log() { echo "$*" | tee -a "$LOG_FILE"; }
# Redefine output helpers to also write to log file
log_info()    { _log "$(echo -e "${BLUE}[INFO]${NC}  $*")"; }
log_ok()      { _log "$(echo -e "${GREEN}[OK]${NC}    $*")"; }
log_warn()    { _log "$(echo -e "${YELLOW}[WARN]${NC}  $*")"; }
log_error()   { _log "$(echo -e "${RED}[ERROR]${NC} $*")"; }
log_section() { _log "$(echo -e "\n${BOLD}${CYAN}══════════════════════════════════════════${NC}")"; _log "$(echo -e "${BOLD}${CYAN}  $*${NC}")"; _log "$(echo -e "${BOLD}${CYAN}══════════════════════════════════════════${NC}")"; }

# =============================================================
log_section "LiverWise LoRA Pipeline — $TIMESTAMP"
# =============================================================

log_info "Project root:  $PROJECT_ROOT"
log_info "Dataset dir:   $DATASET_DIR"
log_info "Mode:          $MODE"
log_info "Dry run:       $DRY_RUN"
log_info "Log file:      $LOG_FILE"
echo ""

# ── Step 0: Dependency check ─────────────────────────────────
log_section "Step 0 — Dependency Check"

check_dep() {
    if command -v "$1" &>/dev/null; then
        log_ok "$1 found: $(command -v "$1")"
    else
        log_error "$1 not found. Install it and re-run."
        exit 1
    fi
}

check_dep "$PYTHON"
check_dep "jq"

# Check Python version >= 3.8
PY_VERSION=$("$PYTHON" -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
PY_MAJOR=$(echo "$PY_VERSION" | cut -d. -f1)
PY_MINOR=$(echo "$PY_VERSION" | cut -d. -f2)
if [[ "$PY_MAJOR" -lt 3 ]] || { [[ "$PY_MAJOR" -eq 3 ]] && [[ "$PY_MINOR" -lt 8 ]]; }; then
    log_error "Python >= 3.8 required. Found: $PY_VERSION"
    exit 1
fi
log_ok "Python $PY_VERSION — OK"

# Check requests library
if ! "$PYTHON" -c "import requests" 2>/dev/null; then
    log_warn "'requests' not found. Installing..."
    "$PYTHON" -m pip install requests --quiet
fi
log_ok "Python 'requests' — OK"

# Check export script exists
if [[ ! -f "$EXPORT_SCRIPT" ]]; then
    log_error "Export script not found: $EXPORT_SCRIPT"
    exit 1
fi
log_ok "Export script found"

# Remove previous files to prevent accumulation across runs
rm -f "$DATASET_DIR"/recipes_v1_*.jsonl
rm -f "$DATASET_DIR"/negative_examples_v1_*.jsonl
rm -f "$DATASET_DIR"/ingredient_matrix_v1_*.jsonl
rm -f "$DATASET_DIR"/export_report_*.json
rm -f "$DATASET_DIR"/deduped/*.jsonl
rm -f "$DATASET_DIR"/train/*.jsonl
rm -f "$DATASET_DIR"/eval/*.jsonl

# =============================================================
# Step 1: Export
# =============================================================
log_section "Step 1 — Dataset Export"

if [[ "$SKIP_EXPORT" == true ]]; then
    log_warn "Skipping export (--skip-export set)"
else
    DRY_RUN_FLAG=""
    [[ "$DRY_RUN" == true ]] && DRY_RUN_FLAG="--dry-run"

    log_info "Running: $PYTHON $EXPORT_SCRIPT --mode $MODE --out $DATASET_DIR $DRY_RUN_FLAG"

    if "$PYTHON" "$EXPORT_SCRIPT" \
        --mode "$MODE" \
        --out  "$DATASET_DIR" \
        $DRY_RUN_FLAG; then
        log_ok "Export complete"
    else
        log_error "Export failed — check log above"
        exit 1
    fi
fi

# =============================================================
# Step 2: Validation
# =============================================================
log_section "Step 2 — JSONL Validation"

if [[ "$SKIP_VALIDATE" == true ]]; then
    log_warn "Skipping validation (--skip-validate set)"
else
    TOTAL_PAIRS=0
    TOTAL_ERRORS=0

    for jsonl_file in "$DATASET_DIR"/*.jsonl; do
        [[ -f "$jsonl_file" ]] || continue
        FILENAME="$(basename "$jsonl_file")"
        LINE_COUNT=0
        ERROR_COUNT=0

        while IFS= read -r line; do
            LINE_COUNT=$((LINE_COUNT + 1))
            # Validate: must be valid JSON
            if ! echo "$line" | jq . >/dev/null 2>&1; then
                log_warn "  Invalid JSON at line $LINE_COUNT in $FILENAME"
                ERROR_COUNT=$((ERROR_COUNT + 1))
                continue
            fi

            # Validate: must have instruction and output keys
            HAS_INSTRUCTION=$(echo "$line" | jq 'has("instruction")' 2>/dev/null || echo "false")
            HAS_OUTPUT=$(echo "$line" | jq 'has("output")' 2>/dev/null || echo "false")

            if [[ "$HAS_INSTRUCTION" != "true" ]] || [[ "$HAS_OUTPUT" != "true" ]]; then
                log_warn "  Missing instruction or output at line $LINE_COUNT in $FILENAME"
                ERROR_COUNT=$((ERROR_COUNT + 1))
            fi

            # Validate recipe pairs: output must have recipe_name and ingredients
            PAIR_TYPE=$(echo "$line" | jq -r '._meta.source // "unknown"' 2>/dev/null)
            if [[ "$PAIR_TYPE" == "approved_submission" ]]; then
                HAS_NAME=$(echo "$line" | jq '.output | has("recipe_name")' 2>/dev/null || echo "false")
                HAS_INGS=$(echo "$line" | jq '.output | has("ingredients")' 2>/dev/null || echo "false")
                HAS_NUTR=$(echo "$line" | jq '.output | has("nutrition")' 2>/dev/null || echo "false")
                if [[ "$HAS_NAME" != "true" ]] || [[ "$HAS_INGS" != "true" ]] || [[ "$HAS_NUTR" != "true" ]]; then
                    log_warn "  Positive pair missing required output fields at line $LINE_COUNT"
                    ERROR_COUNT=$((ERROR_COUNT + 1))
                fi
            fi

        done < "$jsonl_file"

        TOTAL_PAIRS=$((TOTAL_PAIRS + LINE_COUNT))
        TOTAL_ERRORS=$((TOTAL_ERRORS + ERROR_COUNT))

        if [[ "$ERROR_COUNT" -eq 0 ]]; then
            log_ok "$FILENAME — $LINE_COUNT pairs, 0 errors"
        else
            log_warn "$FILENAME — $LINE_COUNT pairs, $ERROR_COUNT errors"
        fi
    done

    if [[ "$TOTAL_PAIRS" -eq 0 ]]; then
        log_warn "No JSONL files found in $DATASET_DIR — nothing to validate"
    else
        log_info "Validation complete: $TOTAL_PAIRS total pairs, $TOTAL_ERRORS errors"
        if [[ "$TOTAL_ERRORS" -gt 0 ]]; then
            log_warn "Fix errors before proceeding to training"
        fi
    fi
fi

# =============================================================
# Step 3: Deduplication
# =============================================================
log_section "Step 3 — Deduplication"

DEDUP_TOTAL=0
DEDUP_REMOVED=0

for jsonl_file in "$DATASET_DIR"/*.jsonl; do
    [[ -f "$jsonl_file" ]] || continue
    FILENAME="$(basename "$jsonl_file")"
    OUT_FILE="$DATASET_DIR/deduped/$FILENAME"

    # Extract dedup keys, find unique lines
    SEEN_KEYS=()
    WRITTEN=0
    SKIPPED=0

    # Use Python for reliable JSON dedup
    "$PYTHON" - <<'PYEOF' "$jsonl_file" "$OUT_FILE"
import sys, json, hashlib

in_path, out_path = sys.argv[1], sys.argv[2]
seen = set()
written = 0
skipped = 0

with open(in_path, "r") as fin, open(out_path, "w") as fout:
    for line in fin:
        line = line.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
        except json.JSONDecodeError:
            fout.write(line + "\n")
            written += 1
            continue

        # Use _meta.dedup_key if present, else hash the whole output
        key = obj.get("_meta", {}).get("dedup_key")
        if not key:
            key = hashlib.md5(json.dumps(obj.get("output", {}), sort_keys=True).encode()).hexdigest()

        if key in seen:
            skipped += 1
        else:
            seen.add(key)
            fout.write(json.dumps(obj, ensure_ascii=False) + "\n")
            written += 1

print(f"  {written} kept, {skipped} duplicates removed from {in_path}")
PYEOF

    DEDUP_TOTAL=$((DEDUP_TOTAL + 1))
done

log_ok "Deduplication complete — deduplicated files in $DATASET_DIR/deduped/"

# =============================================================
# Step 4: Train / Eval split (80/20)
# =============================================================
log_section "Step 4 — Train / Eval Split (80/20)"

for jsonl_file in "$DATASET_DIR/deduped"/*.jsonl; do
    [[ -f "$jsonl_file" ]] || continue
    FILENAME="$(basename "$jsonl_file")"

    "$PYTHON" - <<'PYEOF' "$jsonl_file" "$DATASET_DIR/train/$FILENAME" "$DATASET_DIR/eval/$FILENAME"
import sys, json, random

in_path, train_path, eval_path = sys.argv[1], sys.argv[2], sys.argv[3]

lines = []
with open(in_path) as f:
    for line in f:
        line = line.strip()
        if line:
            lines.append(line)

random.seed(42)  # Deterministic split
random.shuffle(lines)

split = max(1, int(len(lines) * 0.8))
train_lines = lines[:split]
eval_lines  = lines[split:]

with open(train_path, "w") as f:
    f.write("\n".join(train_lines) + "\n")

with open(eval_path, "w") as f:
    f.write("\n".join(eval_lines) + "\n")

print(f"  {in_path.split('/')[-1]}: {len(train_lines)} train / {len(eval_lines)} eval")
PYEOF

done

log_ok "Train/eval split complete"
log_info "  Train → $DATASET_DIR/train/"
log_info "  Eval  → $DATASET_DIR/eval/"

# =============================================================
# Step 5: Dataset summary
# =============================================================
log_section "Step 5 — Dataset Summary"

echo ""
echo -e "${BOLD}Dataset Inventory:${NC}"
echo "──────────────────────────────────────────"

count_lines() {
    local dir="$1"
    local label="$2"
    local total=0
    for f in "$dir"/*.jsonl; do
        [[ -f "$f" ]] || continue
        count=$(wc -l < "$f" 2>/dev/null || echo 0)
        total=$((total + count))
        printf "  %-40s %6d pairs\n" "$(basename "$f")" "$count"
    done
    printf "  %-40s %6d TOTAL\n" "$label" "$total"
    echo "$total"
}

echo ""
echo "Raw exports:"
count_lines "$DATASET_DIR" "raw" > /dev/null

echo ""
echo "Deduplicated:"
DEDUPED_TOTAL=$(count_lines "$DATASET_DIR/deduped" "deduped")

echo ""
echo "Train (80%):"
count_lines "$DATASET_DIR/train" "train"

echo ""
echo "Eval (20%):"
count_lines "$DATASET_DIR/eval" "eval"

echo ""
echo "──────────────────────────────────────────"

# Phase 1 target check
TARGET_POSITIVE=1000
TARGET_NEGATIVE=500

POSITIVE_COUNT=$(wc -l < "$DATASET_DIR/deduped/recipes_v1"*.jsonl 2>/dev/null | tail -1 || echo 0)
NEGATIVE_COUNT=$(wc -l < "$DATASET_DIR/deduped/negative_examples_v1"*.jsonl 2>/dev/null | tail -1 || echo 0)

echo ""
echo -e "${BOLD}Phase 1 Targets:${NC}"
printf "  Positive examples: %4d / %4d  " "$POSITIVE_COUNT" "$TARGET_POSITIVE"
if [[ "${POSITIVE_COUNT:-0}" -ge "$TARGET_POSITIVE" ]]; then
    echo -e "${GREEN}✓ READY${NC}"
else
    NEEDED=$((TARGET_POSITIVE - ${POSITIVE_COUNT:-0}))
    echo -e "${YELLOW}⚠ Need $NEEDED more${NC}"
fi

printf "  Negative examples: %4d / %4d  " "$NEGATIVE_COUNT" "$TARGET_NEGATIVE"
if [[ "${NEGATIVE_COUNT:-0}" -ge "$TARGET_NEGATIVE" ]]; then
    echo -e "${GREEN}✓ READY${NC}"
else
    NEEDED=$((TARGET_NEGATIVE - ${NEGATIVE_COUNT:-0}))
    echo -e "${YELLOW}⚠ Need $NEEDED more${NC}"
fi

echo ""

# =============================================================
# Step 6: LoRA readiness check
# =============================================================
log_section "Step 6 — LoRA Readiness Check"

# Check total training pairs
TOTAL_TRAIN=0
for f in "$DATASET_DIR/train"/*.jsonl; do
    [[ -f "$f" ]] || continue
    COUNT=$(wc -l < "$f" 2>/dev/null || echo 0)
    TOTAL_TRAIN=$((TOTAL_TRAIN + COUNT))
done

echo ""
if [[ "$TOTAL_TRAIN" -ge 500 ]]; then
    log_ok "Training pairs: $TOTAL_TRAIN — sufficient for initial LoRA training"
elif [[ "$TOTAL_TRAIN" -ge 100 ]]; then
    log_warn "Training pairs: $TOTAL_TRAIN — minimal viable dataset. More pairs recommended."
elif [[ "$TOTAL_TRAIN" -gt 0 ]]; then
    log_warn "Training pairs: $TOTAL_TRAIN — too few for reliable LoRA training."
    log_warn "Continue collecting approved recipes before training."
else
    log_warn "No training pairs found. Run export first."
fi

echo ""
echo -e "${BOLD}Next Steps:${NC}"

if [[ "$TOTAL_TRAIN" -lt 500 ]]; then
    echo "  1. Collect more approved recipes in the app"
    echo "  2. Re-run: ./scripts/run_pipeline.sh --mode recipes"
else
    echo "  1. Review train/eval split in $DATASET_DIR/train/ and $DATASET_DIR/eval/"
    echo "  2. Upload to your LoRA training environment:"
    echo "     - HuggingFace: upload $DATASET_DIR/train/*.jsonl to your dataset repo"
    echo "     - Local:       python lora_train.py --dataset $DATASET_DIR/train/"
    echo "  3. After training, run validation:"
    echo "     python validate_lora_outputs.py --eval $DATASET_DIR/eval/"
    echo "  4. On pass: deploy inference server behind:"
    echo "     ${CLOUDFLARE_WORKER_URL:-https://shrill-paper-a8ce.terryd0612.workers.dev}/recipes/search"
fi

echo ""
echo -e "${BOLD}LORA_INTEGRATION_POINTs in Flutter code:${NC}"
echo "  lib/pages/suggested_recipes_page.dart  → /recipes/search endpoint (LoRA output injection)"
echo "  lib/services/food_classifier_service.dart → batch inference hook (replace per-word API calls)"
echo "  lib/services/recipe_compliance_service.dart → approveSubmission() → training data export"
echo "  lib/config/app_config.dart              → cloudflareWorkerQueryEndpoint (inference server)"

# =============================================================
log_section "Pipeline Complete — $TIMESTAMP"
# =============================================================

log_ok "Log saved to: $LOG_FILE"
echo ""