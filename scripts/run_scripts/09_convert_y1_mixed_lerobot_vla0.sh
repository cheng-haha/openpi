#!/usr/bin/env bash
set -euo pipefail

CONDA_ROOT=/inspire/hdd/global_user/chengdongzhou-240108390137/anaconda3
PROJECT_ROOT=/inspire/hdd/global_user/chengdongzhou-240108390137/vla_projects/openpi-cheng-haha
RAW_ROOT=/inspire/hdd/global_user/chengdongzhou-240108390137/datasets/y1_data/raw_hdf5/2026-05-26
export HF_LEROBOT_HOME=/inspire/hdd/global_user/chengdongzhou-240108390137/datasets/y1_data/lerobot_data
export PYTHONUNBUFFERED=1

LOG_DIR=/inspire/hdd/global_user/chengdongzhou-240108390137/.install_logs
LOG_FILE=${LOG_DIR}/y1_mixed_lerobot_convert_vla0_20260526.log

mkdir -p "${LOG_DIR}"
source "${CONDA_ROOT}/etc/profile.d/conda.sh"
conda activate openpi
cd "${PROJECT_ROOT}"

export LD_LIBRARY_PATH="${CONDA_PREFIX}/lib:${LD_LIBRARY_PATH:-}"

python examples/imeta_y1/convert_h5_to_lerobot_multi.py \
  --config.repo-id openpi/y1_dual_arm_mixed_20260526 \
  --config.no-single-arm \
  --config.cam-names cam_high cam_left_wrist cam_right_wrist \
  --config.image-writer-processes 24 \
  --config.image-writer-threads 8 \
  --config.h5-raw-dirs \
    "${RAW_ROOT}/paper_ball_cleanup" \
    "${RAW_ROOT}/stack_bowls_basket" \
    "${RAW_ROOT}/bottle_handoff_basket" \
  2>&1 | tee "${LOG_FILE}"
