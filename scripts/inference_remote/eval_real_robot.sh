#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

ROS_SETUP="${ROS_SETUP:-/opt/ros/humble/setup.bash}"
if [ ! -f "$ROS_SETUP" ]; then
  echo "ROS setup not found: $ROS_SETUP" >&2
  exit 1
fi
source "$ROS_SETUP"

SERVER_HOST="${SERVER_HOST:-127.0.0.1}"
SERVER_PORT="${SERVER_PORT:-8000}"
PROMPT="${PROMPT:-}"
SINGLE_ARM="${SINGLE_ARM:-0}"
ACTION_HORIZON="${ACTION_HORIZON:-30}"
CONTROL_RATE_HZ="${CONTROL_RATE_HZ:-30}"
MAX_EPISODE_STEPS="${MAX_EPISODE_STEPS:-1000}"
CAMERA_TYPE="${CAMERA_TYPE:-ros2}"
CAMERA_DEVICES="${CAMERA_DEVICES:-}"
CAMERA_SERIALS="${CAMERA_SERIALS:-}"
CAMERA_TOPICS="${CAMERA_TOPICS:-}"
ARM_CAN_IDS="${ARM_CAN_IDS:-}"

if [ "$SINGLE_ARM" = "1" ]; then
  SINGLE_ARM_ARGS=(--single-arm)
  CAM_NAMES="${CAM_NAMES:-cam_high cam_right_wrist}"
else
  SINGLE_ARM_ARGS=()
  CAM_NAMES="${CAM_NAMES:-cam_high cam_left_wrist cam_right_wrist}"
fi

CMD=(
  python scripts/inference_remote/eval_real_robot.py
  --host "$SERVER_HOST"
  --port "$SERVER_PORT"
  --prompt "$PROMPT"
  "${SINGLE_ARM_ARGS[@]}"
  --camera-type "$CAMERA_TYPE"
  --action-horizon "$ACTION_HORIZON"
  --control-rate-hz "$CONTROL_RATE_HZ"
  --max-episode-steps "$MAX_EPISODE_STEPS"
  --cam-names
)

for cam_name in $CAM_NAMES; do
  CMD+=("$cam_name")
done

for pair in $CAMERA_DEVICES; do
  CMD+=(--camera-devices "$pair")
done

for pair in $CAMERA_SERIALS; do
  CMD+=(--camera-serials "$pair")
done

for pair in $CAMERA_TOPICS; do
  CMD+=(--camera-topics "$pair")
done

for pair in $ARM_CAN_IDS; do
  CMD+=(--arm-can-ids "$pair")
done

"${CMD[@]}"
