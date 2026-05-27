#!/usr/bin/env bash
set -euo pipefail

GLOBAL_ROOT="/inspire/hdd/global_user/chengdongzhou-240108390137"
CONFIG_NAME="${CONFIG_NAME:-pi05_base_full_dual_arm_stack_bowls_basket}"
EXP_NAME="${EXP_NAME:-stack_bowls_basket_pi05_vla0_4gpu_20260525}"
MONITOR_DIR="${MONITOR_DIR:-$GLOBAL_ROOT/.train_monitor/20260525-stack-bowls-full}"
LOGFILE="${LOGFILE:-$MONITOR_DIR/train.log}"
STATUS_FILE="${STATUS_FILE:-$MONITOR_DIR/train_status.txt}"
TMUX_SESSION="${TMUX_SESSION:-openpi_stack_bowls_full_20260525}"
INTERVAL="${INTERVAL:-30}"

PROCESS_PATTERN="scripts/train.py $CONFIG_NAME --exp-name $EXP_NAME"

mkdir -p "$MONITOR_DIR"
echo WAITING > "$STATUS_FILE"

while ! pgrep -f "$PROCESS_PATTERN" >/dev/null 2>&1; do
  tmux_out="$(tmux capture-pane -t "$TMUX_SESSION" -p -S -20 2>/dev/null || true)"
  if grep -q "EXIT_CODE:" <<<"$tmux_out"; then
    {
      echo CRASHED
      echo "process exited before watchdog saw it"
      echo "=== TAIL ==="
      tail -120 "$LOGFILE" 2>/dev/null || true
    } > "$STATUS_FILE"
    exit 0
  fi
  sleep 1
done

while true; do
  first_err="$(
    grep -n 'Traceback\|OOM\|FAILED\|Killed\|Segmentation fault\|NCCL error' "$LOGFILE" 2>/dev/null \
      | head -1 \
      | cut -d: -f1 || true
  )"
  if [[ -n "$first_err" ]]; then
    {
      echo CRASHED
      echo "=== ERROR (from line $first_err) ==="
      tail -n +"$first_err" "$LOGFILE" 2>/dev/null || true
    } > "$STATUS_FILE"
    break
  fi

  if ! pgrep -f "$PROCESS_PATTERN" >/dev/null 2>&1; then
    sleep 2
    tmux_out="$(tmux capture-pane -t "$TMUX_SESSION" -p -S -30 2>/dev/null || true)"
    exit_code="$(grep -o 'EXIT_CODE:[0-9]*' <<<"$tmux_out" | tail -1 | cut -d: -f2 || true)"
    if [[ "$exit_code" == "0" ]]; then
      {
        echo COMPLETED
        echo "=== TAIL ==="
        grep -E 'Step [0-9]+|Progress on:|Saving checkpoint at step|Finished saving checkpoint|all, folks' "$LOGFILE" 2>/dev/null \
          | tail -30 || true
      } > "$STATUS_FILE"
    else
      {
        echo CRASHED
        echo "exit_code=${exit_code:-unknown}"
        echo "=== TAIL ==="
        tail -120 "$LOGFILE" 2>/dev/null || true
      } > "$STATUS_FILE"
    fi
    break
  fi

  {
    echo RUNNING
    date -Is
    grep -E 'Progress on:|Step [0-9]+|Saving checkpoint at step|Finished saving checkpoint|Initialized data loader|Restoring checkpoint|Finished restoring checkpoint' "$LOGFILE" 2>/dev/null \
      | tail -20 || true
  } > "$STATUS_FILE.tmp"
  mv "$STATUS_FILE.tmp" "$STATUS_FILE"
  sleep "$INTERVAL"
done
