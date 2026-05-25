#!/usr/bin/env bash
set -euo pipefail

ENV_NAME="${1:-openpi_local_infer}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

if conda env list | awk '{print $1}' | grep -Fxq "$ENV_NAME"; then
  echo "Using existing conda env: $ENV_NAME"
else
  conda create -n "$ENV_NAME" python=3.10 -y
fi

conda run -n "$ENV_NAME" python -m pip install --upgrade pip uv
conda run -n "$ENV_NAME" python -m pip install "numpy<2" "opencv-python<4.11" tyro pybind11 v4l2
conda run -n "$ENV_NAME" python -m pip install -e "$ROOT_DIR/packages/openpi-client"
conda run -n "$ENV_NAME" python -m pip install -e "$ROOT_DIR/../y1_sdk_python/y1_sdk"
conda run -n "$ENV_NAME" bash -lc 'source /opt/ros/humble/setup.bash && python -c "import openpi_client, v4l2, y1_sdk, rclpy, cv_bridge; print(\"import check ok\")"'

cat <<EOF

Local minimal environment is ready.

Activate:
  conda activate $ENV_NAME

Run client:
  cd $ROOT_DIR
  source /opt/ros/humble/setup.bash
  CAMERA_TYPE=ros2 PROMPT="replace_with_your_task" bash scripts/inference_remote/eval_real_robot.sh

EOF
