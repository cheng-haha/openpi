#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GLOBAL_ROOT="/inspire/hdd/global_user/chengdongzhou-240108390137"
CONDA_SH="$GLOBAL_ROOT/anaconda3/etc/profile.d/conda.sh"

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

test -f "$HF_LEROBOT_HOME/openpi/stack_bowls_basket/meta/info.json"

python - <<'PY'
import json
from pathlib import Path

from lerobot.common.datasets.lerobot_dataset import LeRobotDataset

repo_id = "openpi/stack_bowls_basket"
root = Path("/inspire/hdd/global_user/chengdongzhou-240108390137/datasets/y1_data/lerobot_data") / repo_id
info = json.loads((root / "meta" / "info.json").read_text())

dataset = LeRobotDataset(repo_id=repo_id)
sample = dataset[0]
image_keys = sorted(key for key in sample if key.startswith("observation.images."))

print("repo_id", repo_id)
print("root", root)
print("meta_total_episodes", info["total_episodes"])
print("meta_total_frames", info["total_frames"])
print("dataset_num_episodes", dataset.num_episodes)
print("dataset_num_frames", dataset.num_frames)
print("state_shape", tuple(sample["observation.state"].shape))
print("action_shape", tuple(sample["action"].shape))
print("image_keys", image_keys)
print("tasks", dataset.meta.tasks)

assert info["total_episodes"] == dataset.num_episodes
assert tuple(sample["observation.state"].shape) == (14,)
assert tuple(sample["action"].shape) == (14,)
assert image_keys == [
    "observation.images.cam_high",
    "observation.images.cam_left_wrist",
    "observation.images.cam_right_wrist",
]
print("validation ok")
PY
