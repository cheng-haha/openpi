#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GLOBAL_ROOT="/inspire/hdd/global_user/chengdongzhou-240108390137"
CONDA_SH="$GLOBAL_ROOT/anaconda3/etc/profile.d/conda.sh"
CONFIG_NAME="${CONFIG_NAME:-pi05_base_full_dual_arm_y1_mixed_20260526}"
REPO_PATH="$GLOBAL_ROOT/datasets/y1_data/lerobot_data/openpi/y1_dual_arm_mixed_20260526"

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

test -f "$REPO_PATH/meta/info.json"
test -f "$OPENPI_DATA_HOME/big_vision/paligemma_tokenizer.model"

python -m uv run --offline --no-sync --python "$CONDA_PREFIX/bin/python" scripts/compute_norm_stats.py \
  --config-name "$CONFIG_NAME" \
  "$@"

echo "norm stats path: assets/$CONFIG_NAME/openpi/y1_dual_arm_mixed_20260526/norm_stats.json"
