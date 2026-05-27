#!/usr/bin/env bash
set -euo pipefail

# Run on the Y1 robot control machine. The GPU policy server must already be
# reachable through SERVER_URL, usually the VS Code / Inspire forwarded address
# ending with /proxy/8000/.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

CONDA_SH="${CONDA_SH:-/home/ubuntu/miniconda3/etc/profile.d/conda.sh}"
CONDA_ENV="${CONDA_ENV:-openpi_local_infer_py310}"

SERVER_URL="${SERVER_URL:-}"
if [[ -z "$SERVER_URL" ]]; then
  echo 'Missing SERVER_URL. Example:' >&2
  echo '  SERVER_URL="https://.../proxy/8000/" bash scripts/run_scripts/06_infer_stack_bowls_basket_remote_real_robot.sh' >&2
  exit 1
fi

# Task defaults. Override from the command line when needed.
export PROMPT="${PROMPT:-stack bowls then place in basket}"
export SINGLE_ARM="${SINGLE_ARM:-0}"
export CAMERA_TYPE="${CAMERA_TYPE:-ros2}"
export CAM_NAMES="${CAM_NAMES:-cam_high cam_left_wrist cam_right_wrist}"
export CAMERA_TOPICS="${CAMERA_TOPICS:-cam_high=/camera_high/color/image_raw cam_left_wrist=/camera_left/color/image_raw cam_right_wrist=/camera_right/color/image_raw}"
export ARM_CAN_IDS="${ARM_CAN_IDS:-left_arm=can1 right_arm=can0}"

# Keep the successful synchronous path unchanged by default: no automatic reset.
# Set RESET_BEFORE_INFER=1 or RESET_JOINTS="..." if you explicitly want an init move.
export RESET_BEFORE_INFER="${RESET_BEFORE_INFER:-1}"
if [[ "$RESET_BEFORE_INFER" == "1" && -z "${RESET_JOINTS:-}" ]]; then
  if [[ "$SINGLE_ARM" == "1" ]]; then
    export RESET_JOINTS="0 0 0 0 0 0 0"
  else
    export RESET_JOINTS="0 0 0 0 0 0 0 0 0 0 0 0 0 0"
  fi
fi

# PI0.5 returns 50 actions. For 30 Hz synchronous Y1 inference, execute the
# first 30 actions and then query again.
export ACTION_HORIZON="${ACTION_HORIZON:-30}"
export CONTROL_RATE_HZ="${CONTROL_RATE_HZ:-30}"
export MAX_EPISODE_STEPS="${MAX_EPISODE_STEPS:-3000}"

# These default to on because real-robot inference needs CAN and camera topics.
# This is the original ROS2 support chain: CAN + two_arm_control launch, and
# ROS2 usb_cam topics. Use 07_rtc_* for the Python SDK RTC path.
START_Y1_CONTROL="${START_Y1_CONTROL:-1}"
START_Y1_CAMERAS="${START_Y1_CAMERAS:-1}"
RUN_FAKE_SMOKE="${RUN_FAKE_SMOKE:-0}"

source_env() {
  set +u
  # shellcheck disable=SC1090
  source "$1"
  set -u
}

if [[ ! -f "$CONDA_SH" ]]; then
  echo "Conda hook not found: $CONDA_SH" >&2
  exit 1
fi
source_env "$CONDA_SH"
conda activate "$CONDA_ENV"

if [[ "$START_Y1_CONTROL" == "1" ]]; then
  echo "[init] starting Y1 dual-arm control and CAN interfaces"
  bash /home/ubuntu/projects/y1_robot/start_y1_dual_arm_inference_tmux.sh
fi

if [[ "$START_Y1_CAMERAS" == "1" ]]; then
  echo "[init] starting Y1 cameras"
  bash /home/ubuntu/projects/y1_robot/start_y1_cameras_tmux.sh
fi

echo "[check] policy server health"
curl --http1.1 --fail --silent --show-error "${SERVER_URL%/}/healthz" >/dev/null

if [[ "$RUN_FAKE_SMOKE" == "1" ]]; then
  echo "[check] fake OpenPI request"
  python scripts/inference_remote/fake_openpi_client.py \
    --server "$SERVER_URL" \
    --prompt "$PROMPT" \
    --state-dim 14 \
    --image-layout chw
fi

cat <<EOF
[run] remote real-robot inference
  mode              = sync
  prompt            = $PROMPT
  server_url        = $SERVER_URL
  conda_env         = $CONDA_ENV
  camera_type       = $CAMERA_TYPE
  cam_names         = $CAM_NAMES
  arm_can_ids       = $ARM_CAN_IDS
  reset_before_infer= $RESET_BEFORE_INFER
  reset_joints      = ${RESET_JOINTS:-none}
  action_horizon    = $ACTION_HORIZON
  control_rate_hz   = $CONTROL_RATE_HZ
  max_episode_steps = $MAX_EPISODE_STEPS
EOF

bash scripts/inference_remote/eval_real_robot.sh
