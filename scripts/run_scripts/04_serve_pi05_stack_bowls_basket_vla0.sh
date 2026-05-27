#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GLOBAL_ROOT="/inspire/hdd/global_user/chengdongzhou-240108390137"
CONDA_SH="$GLOBAL_ROOT/anaconda3/etc/profile.d/conda.sh"
CONDA_PREFIX_OVERRIDE="${CONDA_PREFIX_OVERRIDE:-}"

CONFIG_NAME="${CONFIG_NAME:-pi05_base_full_dual_arm_stack_bowls_basket}"
EXP_NAME="${EXP_NAME:-stack_bowls_basket_pi05_smoke_100_20260525}"
CHECKPOINT_STEP="${CHECKPOINT_STEP:-99}"
CHECKPOINT_DIR="${CHECKPOINT_DIR:-./checkpoints/$CONFIG_NAME/$EXP_NAME/$CHECKPOINT_STEP}"
PORT="${PORT:-8000}"
CUDA_VISIBLE_DEVICES="${CUDA_VISIBLE_DEVICES:-0}"

if [[ -n "$CONDA_PREFIX_OVERRIDE" ]]; then
  export CONDA_PREFIX="$CONDA_PREFIX_OVERRIDE"
  export PATH="$CONDA_PREFIX/bin:$PATH"
else
  source "$CONDA_SH"
  conda activate openpi
fi

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
export XLA_PYTHON_CLIENT_MEM_FRACTION="${XLA_PYTHON_CLIENT_MEM_FRACTION:-0.45}"
export WANDB_MODE=disabled
export WANDB_DISABLED=true
export CUDA_VISIBLE_DEVICES

if [[ ! -f "$CHECKPOINT_DIR/params/_METADATA" ]]; then
  echo "Missing checkpoint params: $CHECKPOINT_DIR/params/_METADATA" >&2
  exit 1
fi
if [[ ! -f "$CHECKPOINT_DIR/assets/openpi/stack_bowls_basket/norm_stats.json" ]]; then
  echo "Missing checkpoint norm stats: $CHECKPOINT_DIR/assets/openpi/stack_bowls_basket/norm_stats.json" >&2
  exit 1
fi
if [[ ! -f "$OPENPI_DATA_HOME/big_vision/paligemma_tokenizer.model" ]]; then
  echo "Missing local PaliGemma tokenizer cache: $OPENPI_DATA_HOME/big_vision/paligemma_tokenizer.model" >&2
  exit 1
fi

echo "config: $CONFIG_NAME"
echo "checkpoint_dir: $CHECKPOINT_DIR"
echo "port: $PORT"
echo "cuda_visible_devices: $CUDA_VISIBLE_DEVICES"
echo "offline: HF_HUB_OFFLINE=$HF_HUB_OFFLINE TRANSFORMERS_OFFLINE=$TRANSFORMERS_OFFLINE UV_OFFLINE=$UV_OFFLINE"

python scripts/serve_policy.py \
  --port="$PORT" \
  policy:checkpoint \
  --policy.config="$CONFIG_NAME" \
  --policy.dir="$CHECKPOINT_DIR" \
  "$@"
