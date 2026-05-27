#!/usr/bin/env bash
set -euo pipefail

GLOBAL_ROOT="/inspire/hdd/global_user/chengdongzhou-240108390137"
PROJECT_ROOT="$GLOBAL_ROOT/vla_projects/openpi-cheng-haha"
CONDA_SH="$GLOBAL_ROOT/anaconda3/etc/profile.d/conda.sh"
REPO_ID="${REPO_ID:-openpi/y1_dual_arm_mixed_20260526}"

source "$CONDA_SH"
conda activate openpi

cd "$PROJECT_ROOT"

export HF_LEROBOT_HOME="$GLOBAL_ROOT/datasets/y1_data/lerobot_data"
export LD_LIBRARY_PATH="$CONDA_PREFIX/lib:${LD_LIBRARY_PATH:-}"

python - <<'PY'
from lerobot.common.datasets.lerobot_dataset import LeRobotDataset
from lerobot.common.datasets.lerobot_dataset import LeRobotDatasetMetadata

repo_id = "openpi/y1_dual_arm_mixed_20260526"
meta = LeRobotDatasetMetadata(repo_id)
dataset = LeRobotDataset(repo_id)

print("repo_id", repo_id)
print("total_episodes", meta.total_episodes)
print("num_frames", len(dataset))
print("fps", meta.fps)
print("tasks", meta.tasks)
print("features", sorted(dataset.features))
PY
