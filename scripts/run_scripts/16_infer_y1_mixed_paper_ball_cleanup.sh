#!/usr/bin/env bash
set -euo pipefail

export TASK_NAME="${TASK_NAME:-paper_ball_cleanup}"
export PROMPT="${PROMPT:-clear paper balls into trash bin}"

exec bash "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/15_infer_y1_mixed_task_remote_real_robot.sh" "$@"
