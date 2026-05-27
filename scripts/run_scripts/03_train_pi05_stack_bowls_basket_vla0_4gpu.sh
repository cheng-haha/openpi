#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GLOBAL_ROOT="/inspire/hdd/global_user/chengdongzhou-240108390137"
CONDA_SH="$GLOBAL_ROOT/anaconda3/etc/profile.d/conda.sh"

CONFIG_NAME="${CONFIG_NAME:-pi05_base_full_dual_arm_stack_bowls_basket}"
EXP_NAME="${EXP_NAME:-stack_bowls_basket_pi05_vla0_4gpu_$(date +%Y%m%d_%H%M%S)}"
FSDP_DEVICES="${FSDP_DEVICES:-4}"
BATCH_SIZE="${BATCH_SIZE:-32}"
NUM_TRAIN_STEPS="${NUM_TRAIN_STEPS:-30000}"
SAVE_INTERVAL="${SAVE_INTERVAL:-5000}"
KEEP_PERIOD="${KEEP_PERIOD:-10000}"
NUM_WORKERS="${NUM_WORKERS:-2}"
CHECKPOINT_BASE_DIR="${CHECKPOINT_BASE_DIR:-./checkpoints}"

source "$CONDA_SH"
conda activate openpi

cd "$PROJECT_ROOT"

export GIT_LFS_SKIP_SMUDGE=1
export UV_CACHE_DIR="$GLOBAL_ROOT/uv_cache_openpi"
export UV_PROJECT_ENVIRONMENT="$CONDA_PREFIX"
export UV_OFFLINE=1
export OPENPI_DATA_HOME="$GLOBAL_ROOT/ai_models/physical-intelligence"
export XDG_CACHE_HOME="$GLOBAL_ROOT/openpi_data/.cache"
export HF_HOME="$GLOBAL_ROOT/openpi_data/.cache/huggingface_hub"
export HF_LEROBOT_HOME="$GLOBAL_ROOT/datasets/y1_data/lerobot_data"
export LD_LIBRARY_PATH="$CONDA_PREFIX/lib:${LD_LIBRARY_PATH:-}"
export HF_HUB_OFFLINE=1
export HF_DATASETS_OFFLINE=1
export TRANSFORMERS_OFFLINE=1
export XLA_PYTHON_CLIENT_MEM_FRACTION="${XLA_PYTHON_CLIENT_MEM_FRACTION:-0.9}"
export WANDB_MODE="${WANDB_MODE:-offline}"
export WANDB_DIR="${WANDB_DIR:-$GLOBAL_ROOT/openpi_data/wandb}"
export WANDB_SILENT=true
mkdir -p "$WANDB_DIR"

if [[ ! -f "assets/$CONFIG_NAME/openpi/stack_bowls_basket/norm_stats.json" ]]; then
  echo "Missing norm stats: assets/$CONFIG_NAME/openpi/stack_bowls_basket/norm_stats.json" >&2
  echo "Run scripts/run_scripts/02_compute_norm_stats_stack_bowls_basket.sh first." >&2
  exit 1
fi
if [[ ! -f "$HF_LEROBOT_HOME/openpi/stack_bowls_basket/meta/info.json" ]]; then
  echo "Missing local LeRobot dataset: $HF_LEROBOT_HOME/openpi/stack_bowls_basket" >&2
  exit 1
fi
if [[ ! -f "$OPENPI_DATA_HOME/openpi-assets/checkpoints/pi05_base/params/_METADATA" ]]; then
  echo "Missing local pi05_base checkpoint cache: $OPENPI_DATA_HOME/openpi-assets/checkpoints/pi05_base" >&2
  exit 1
fi
if [[ ! -f "$OPENPI_DATA_HOME/big_vision/paligemma_tokenizer.model" ]]; then
  echo "Missing local PaliGemma tokenizer cache: $OPENPI_DATA_HOME/big_vision/paligemma_tokenizer.model" >&2
  exit 1
fi

extra_args=()
if [[ "${RESUME:-0}" == "1" ]]; then
  extra_args+=(--resume)
fi
if [[ "${OVERWRITE:-0}" == "1" ]]; then
  extra_args+=(--overwrite)
fi
if [[ "${DISABLE_WANDB:-0}" == "1" ]]; then
  extra_args+=(--no-wandb-enabled)
fi

echo "config: $CONFIG_NAME"
echo "exp_name: $EXP_NAME"
echo "fsdp_devices: $FSDP_DEVICES"
echo "batch_size: $BATCH_SIZE"
echo "num_train_steps: $NUM_TRAIN_STEPS"
echo "checkpoint_dir: $CHECKPOINT_BASE_DIR/$CONFIG_NAME/$EXP_NAME"
echo "wandb_mode: $WANDB_MODE"
echo "wandb_dir: $WANDB_DIR"

python -m uv run --offline --no-sync --python "$CONDA_PREFIX/bin/python" scripts/train.py "$CONFIG_NAME" \
  --exp-name "$EXP_NAME" \
  --fsdp-devices "$FSDP_DEVICES" \
  --batch-size "$BATCH_SIZE" \
  --num-train-steps "$NUM_TRAIN_STEPS" \
  --save-interval "$SAVE_INTERVAL" \
  --keep-period "$KEEP_PERIOD" \
  --num-workers "$NUM_WORKERS" \
  --checkpoint-base-dir "$CHECKPOINT_BASE_DIR" \
  "${extra_args[@]}" \
  "$@"
