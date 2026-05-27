#!/usr/bin/env bash
set -euo pipefail

export TASK_NAME="${TASK_NAME:-bottle_handoff_basket}"
export PROMPT="${PROMPT:-handoff water bottle into basket}"

exec bash "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/15_infer_y1_mixed_task_remote_real_robot.sh" "$@"
