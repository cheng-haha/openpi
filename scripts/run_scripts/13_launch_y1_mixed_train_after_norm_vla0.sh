#!/usr/bin/env bash
set -euo pipefail

GLOBAL_ROOT="/inspire/hdd/global_user/chengdongzhou-240108390137"
PROJECT_ROOT="$GLOBAL_ROOT/vla_projects/openpi-cheng-haha"
NORM_SESSION="${NORM_SESSION:-openpi_y1_mixed_norm_20260526}"
TRAIN_SESSION="${TRAIN_SESSION:-openpi_y1_mixed_full_20260526}"
RUN_TAG="${RUN_TAG:-20260526-y1-mixed-full}"
EXP_NAME="${EXP_NAME:-y1_dual_arm_mixed_pi05_vla0_4gpu_20260526}"
MONITOR_DIR="$GLOBAL_ROOT/.train_monitor/$RUN_TAG"
NORM_FILE="$PROJECT_ROOT/assets/pi05_base_full_dual_arm_y1_mixed_20260526/openpi/y1_dual_arm_mixed_20260526/norm_stats.json"
NORM_EXIT_FILE="$GLOBAL_ROOT/.install_logs/y1_mixed_norm_stats_exit_20260526.txt"

cd "$PROJECT_ROOT"

echo "waiting_for_norm_session: $NORM_SESSION"
while tmux has-session -t "$NORM_SESSION" 2>/dev/null; do
  date '+%Y-%m-%d %H:%M:%S still_waiting_for_norm'
  sleep 60
done

if [[ -f "$NORM_EXIT_FILE" ]]; then
  cat "$NORM_EXIT_FILE"
fi

if [[ ! -f "$NORM_FILE" ]]; then
  echo "Missing norm stats after norm session finished: $NORM_FILE" >&2
  exit 1
fi

if tmux has-session -t "$TRAIN_SESSION" 2>/dev/null; then
  echo "Training session already exists: $TRAIN_SESSION"
  exit 0
fi

mkdir -p "$MONITOR_DIR"
rm -f "$MONITOR_DIR/train.log" "$MONITOR_DIR/train_status.txt" "$MONITOR_DIR/exit_code.txt"

tmux new-session -d -s "$TRAIN_SESSION" \
  "cd $PROJECT_ROOT && EXP_NAME=$EXP_NAME bash scripts/run_scripts/12_train_pi05_y1_mixed_vla0_4gpu.sh 2>&1 | tee $MONITOR_DIR/train.log; echo EXIT_CODE:\${PIPESTATUS[0]} | tee $MONITOR_DIR/exit_code.txt"

echo "started_training_session: $TRAIN_SESSION"
echo "monitor_dir: $MONITOR_DIR"
