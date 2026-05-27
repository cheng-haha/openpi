#!/usr/bin/env bash
set -euo pipefail

# Run on the Y1 robot control machine. The mixed policy server must already be
# reachable through SERVER_URL, usually the VS Code / Inspire forwarded address
# ending with /proxy/8000/.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

TASK_NAME="${TASK_NAME:-y1_mixed_task}"
PROMPT="${PROMPT:-}"

if [[ -z "${SERVER_URL:-}" ]]; then
  echo 'Missing SERVER_URL. Example:' >&2
  echo '  SERVER_URL="https://.../proxy/8000/" bash scripts/run_scripts/16_infer_y1_mixed_paper_ball_cleanup.sh' >&2
  exit 1
fi

if [[ -z "$PROMPT" ]]; then
  echo "Missing PROMPT for $TASK_NAME." >&2
  exit 1
fi

# The mixed policy was trained with three cameras, 14-D state/action, and
# client-provided task prompts. Reuse the RTC-capable Y1 remote inference path.
export PROMPT
export SINGLE_ARM="${SINGLE_ARM:-0}"
export CAMERA_TYPE="${CAMERA_TYPE:-ros2}"
export CAM_NAMES="${CAM_NAMES:-cam_high cam_left_wrist cam_right_wrist}"
export CAMERA_TOPICS="${CAMERA_TOPICS:-cam_high=/camera_high/color/image_raw cam_left_wrist=/camera_left/color/image_raw cam_right_wrist=/camera_right/color/image_raw}"
export ARM_CAN_IDS="${ARM_CAN_IDS:-left_arm=can1 right_arm=can0}"
export USE_RTC="${USE_RTC:-1}"
export ACTION_HORIZON="${ACTION_HORIZON:-30}"
export CONTROL_RATE_HZ="${CONTROL_RATE_HZ:-30}"
export MAX_EPISODE_STEPS="${MAX_EPISODE_STEPS:-3000}"
export RUN_FAKE_SMOKE="${RUN_FAKE_SMOKE:-0}"

cat <<EOF
[task] y1 mixed remote inference
  task_name         = $TASK_NAME
  prompt            = $PROMPT
  server_url        = $SERVER_URL
  use_rtc           = $USE_RTC
  camera_type       = $CAMERA_TYPE
  cam_names         = $CAM_NAMES
  action_horizon    = $ACTION_HORIZON
  control_rate_hz   = $CONTROL_RATE_HZ
  max_episode_steps = $MAX_EPISODE_STEPS
EOF

exec bash scripts/run_scripts/07_rtc_infer_stack_bowls_basket_remote_real_robot.sh "$@"
