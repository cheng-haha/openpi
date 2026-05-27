#!/usr/bin/env bash
set -euo pipefail

# Run on the Y1 robot control machine. The GPU policy server must already be
# reachable through SERVER_URL, usually the VS Code / Inspire forwarded address
# ending with /proxy/8000/.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

CONDA_SH="${CONDA_SH:-/home/ubuntu/miniconda3/etc/profile.d/conda.sh}"
CONDA_ENV="${CONDA_ENV:-openpi_local_infer_py310}"
ROS_SETUP="${ROS_SETUP:-/opt/ros/humble/setup.bash}"

SERVER_URL="${SERVER_URL:-}"
if [[ -z "$SERVER_URL" ]]; then
  echo 'Missing SERVER_URL. Example:' >&2
  echo '  SERVER_URL="https://.../proxy/8000/" bash scripts/run_scripts/07_rtc_infer_stack_bowls_basket_remote_real_robot.sh' >&2
  exit 1
fi

# Task defaults. Override from the command line when needed.
export PROMPT="${PROMPT:-stack bowls then place in basket}"
export SINGLE_ARM="${SINGLE_ARM:-0}"
export CAMERA_TYPE="${CAMERA_TYPE:-ros2}"
export CAM_NAMES="${CAM_NAMES:-cam_high cam_left_wrist cam_right_wrist}"
export CAMERA_TOPICS="${CAMERA_TOPICS:-cam_high=/camera_high/color/image_raw cam_left_wrist=/camera_left/color/image_raw cam_right_wrist=/camera_right/color/image_raw}"
export ARM_CAN_IDS="${ARM_CAN_IDS:-left_arm=can1 right_arm=can0}"
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
export USE_RTC="${USE_RTC:-1}"
export ACTION_HORIZON="${ACTION_HORIZON:-30}"
export CONTROL_RATE_HZ="${CONTROL_RATE_HZ:-30}"
export MAX_EPISODE_STEPS="${MAX_EPISODE_STEPS:-3000}"
export MAX_PUBLISH_STEP="${MAX_PUBLISH_STEP:-$MAX_EPISODE_STEPS}"

export INFERENCE_RATE="${INFERENCE_RATE:-4}"
export CHUNK_SIZE="${CHUNK_SIZE:-30}"
export RTC_MODEL_CHUNK_SIZE="${RTC_MODEL_CHUNK_SIZE:-50}"
export RTC_EXECUTE_HORIZON="${RTC_EXECUTE_HORIZON:-8}"
export RTC_MAX_GUIDANCE_WEIGHT="${RTC_MAX_GUIDANCE_WEIGHT:-0.3}"
export LATENCY_K="${LATENCY_K:-8}"
export MIN_SMOOTH_STEPS="${MIN_SMOOTH_STEPS:-8}"
export BUFFER_MAX_CHUNKS="${BUFFER_MAX_CHUNKS:-10}"
export INTERPOLATION="${INTERPOLATION:-1}"
export INTERP_STEPS="${INTERP_STEPS:-10}"
export INTERP_FREQUENCY="${INTERP_FREQUENCY:-300}"
export RTC_MASK_PREFIX_DELAY="${RTC_MASK_PREFIX_DELAY:-0}"
export RTC_DISABLE_SMOOTHING="${RTC_DISABLE_SMOOTHING:-0}"
export VISUAL="${VISUAL:-0}"
export VISUAL_FPS="${VISUAL_FPS:-30}"
INFER_IMAGE_HEIGHT="${INFER_IMAGE_HEIGHT:-224}"
INFER_IMAGE_WIDTH="${INFER_IMAGE_WIDTH:-224}"

# These default to on because real-robot inference needs CAN and camera topics.
# The control initializer may ask for the local sudo password.
START_Y1_CONTROL="${START_Y1_CONTROL:-1}"
START_Y1_CAMERAS="${START_Y1_CAMERAS:-1}"
RUN_FAKE_SMOKE="${RUN_FAKE_SMOKE:-0}"

source_env() {
  set +u
  # shellcheck disable=SC1090
  source "$1"
  set -u
}

ensure_sudo_ready() {
  if sudo -n true >/dev/null 2>&1; then
    return 0
  fi

  if [[ ! -t 0 ]]; then
    echo "sudo is required to initialize CAN interfaces." >&2
    return 1
  fi

  echo "sudo is required to initialize can0/can1. You may be prompted once below."
  sudo -v
}

setup_can_interface() {
  local can_device="$1"
  local can_interface="$2"

  if [[ ! -e "$can_device" ]]; then
    echo "Missing CAN device: $can_device" >&2
    return 1
  fi

  echo "Detected CAN device: $can_device -> $(readlink -f "$can_device")"
  sudo pkill -f "slcand -o -f -s8 $can_device $can_interface" >/dev/null 2>&1 || true
  sudo ip link set "$can_interface" down >/dev/null 2>&1 || true
  sleep 1
  sudo slcand -o -f -s8 "$can_device" "$can_interface"
  sudo ifconfig "$can_interface" up
  sudo ip link set "$can_interface" txqueuelen 1000
}

start_can_status_tmux() {
  local session_name="${Y1_CAN_SESSION:-y1_dual_arm_inference}"

  if ! command -v tmux >/dev/null 2>&1; then
    echo "tmux is not installed. CAN interfaces are up, but no status session was created." >&2
    return 0
  fi

  if tmux has-session -t "$session_name" 2>/dev/null; then
    tmux kill-session -t "$session_name"
    echo "Restarted existing tmux session: $session_name"
  fi

  local can0_cmd="while true; do clear; date; echo; echo 'can0 status'; ip -details link show can0 || true; sleep 1; done"
  local can1_cmd="while true; do clear; date; echo; echo 'can1 status'; ip -details link show can1 || true; sleep 1; done"

  tmux new-session -d -s "$session_name" -n can0
  tmux send-keys -t "$session_name":can0 "$can0_cmd" C-m
  tmux new-window -t "$session_name" -n can1
  tmux send-keys -t "$session_name":can1 "$can1_cmd" C-m
  tmux select-window -t "$session_name":can0

  echo "tmux session created: $session_name"
  echo "Attach with: tmux attach -t $session_name"
  echo
  echo "Window layout:"
  echo "  can0 -> monitor can0 status"
  echo "  can1 -> monitor can1 status"
  echo
  echo "Python SDK inference controls the arms directly; ROS2 y1_controller is not started."
}

start_y1_can_only() {
  ensure_sudo_ready
  setup_can_interface /dev/imeta_y1_can0 can0
  setup_can_interface /dev/imeta_y1_can1 can1
  start_can_status_tmux
}

if [[ ! -f "$CONDA_SH" ]]; then
  echo "Conda hook not found: $CONDA_SH" >&2
  exit 1
fi
source_env "$CONDA_SH"
conda activate "$CONDA_ENV"

if [[ ! -f "$ROS_SETUP" ]]; then
  echo "ROS setup not found: $ROS_SETUP" >&2
  exit 1
fi
source_env "$ROS_SETUP"

if [[ "$START_Y1_CONTROL" == "1" ]]; then
  echo "[init] starting Y1 CAN interfaces for Python SDK inference"
  start_y1_can_only
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
  mode              = $([[ "$USE_RTC" == "1" ]] && echo rtc || echo sync)
  prompt            = $PROMPT
  server_url        = $SERVER_URL
  conda_env         = $CONDA_ENV
  camera_type       = $CAMERA_TYPE
  cam_names         = $CAM_NAMES
  reset_before_infer= $RESET_BEFORE_INFER
  reset_joints      = ${RESET_JOINTS:-none}
  arm_can_ids       = $ARM_CAN_IDS
  rtc_chunk_size    = $CHUNK_SIZE
  rtc_infer_rate    = $INFERENCE_RATE
  rtc_execute_horz  = $RTC_EXECUTE_HORIZON
  rtc_latency_k     = $LATENCY_K
  infer_image_size  = ${INFER_IMAGE_HEIGHT}x${INFER_IMAGE_WIDTH}
  action_horizon    = $ACTION_HORIZON
  control_rate_hz   = $CONTROL_RATE_HZ
  max_episode_steps = $MAX_EPISODE_STEPS
EOF

if [[ "$USE_RTC" == "1" ]]; then
  CMD=(
    python scripts/inference_python/y1_openpi_inference_rtc.py
    --server "$SERVER_URL"
    --prompt "$PROMPT"
    --camera_type "$CAMERA_TYPE"
    --control_frequency "$CONTROL_RATE_HZ"
    --inference_rate "$INFERENCE_RATE"
    --chunk_size "$CHUNK_SIZE"
    --max_publish_step "$MAX_PUBLISH_STEP"
    --rtc_model_chunk_size "$RTC_MODEL_CHUNK_SIZE"
    --rtc_execute_horizon "$RTC_EXECUTE_HORIZON"
    --rtc_max_guidance_weight "$RTC_MAX_GUIDANCE_WEIGHT"
    --latency_k "$LATENCY_K"
    --min_smooth_steps "$MIN_SMOOTH_STEPS"
    --buffer_max_chunks "$BUFFER_MAX_CHUNKS"
    --interp_steps "$INTERP_STEPS"
    --interp_frequency "$INTERP_FREQUENCY"
    --visual_fps "$VISUAL_FPS"
    --image_height "$INFER_IMAGE_HEIGHT"
    --image_width "$INFER_IMAGE_WIDTH"
    --wait_for_enter
  )

  if [[ "$SINGLE_ARM" == "1" ]]; then
    CMD+=(--single_arm)
  fi

  CMD+=(--camera_names)
  for cam_name in $CAM_NAMES; do
    CMD+=("$cam_name")
  done

  if [[ -n "${CAMERA_TOPICS:-}" ]]; then
    CMD+=(--camera_topics)
    for pair in $CAMERA_TOPICS; do
      CMD+=("$pair")
    done
  fi

  if [[ -n "${CAMERA_DEVICES:-}" ]]; then
    CMD+=(--camera_devices)
    for pair in $CAMERA_DEVICES; do
      CMD+=("$pair")
    done
  fi

  if [[ -n "${CAMERA_SERIALS:-}" ]]; then
    CMD+=(--camera_serials)
    for pair in $CAMERA_SERIALS; do
      CMD+=("$pair")
    done
  fi

  if [[ -n "$ARM_CAN_IDS" ]]; then
    CMD+=(--arm_can_ids)
    for pair in $ARM_CAN_IDS; do
      CMD+=("$pair")
    done
  fi

  if [[ -n "${RESET_JOINTS:-}" ]]; then
    CMD+=(--init_state)
    for joint in $RESET_JOINTS; do
      CMD+=("$joint")
    done
  fi

  if [[ "$INTERPOLATION" == "1" ]]; then
    CMD+=(--interpolation)
  fi

  if [[ "$RTC_MASK_PREFIX_DELAY" == "1" ]]; then
    CMD+=(--rtc_mask_prefix_delay)
  fi

  if [[ "$RTC_DISABLE_SMOOTHING" == "1" ]]; then
    CMD+=(--rtc_disable_smoothing)
  fi

  if [[ "$VISUAL" == "1" ]]; then
    CMD+=(--visual)
  fi

  "${CMD[@]}"
else
  bash scripts/inference_remote/eval_real_robot.sh
fi
