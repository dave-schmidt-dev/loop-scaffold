#!/usr/bin/env bash
set -euo pipefail

# Ralph loop runner.
#
# Contract:
# - CHECK_CMD exits 0 when done.
# - AGENT_CMD is non-interactive and reads prompt from stdin.

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
metrics_lib="${script_dir}/scripts/metrics_lib.sh"

WORKDIR="${WORKDIR:-$(pwd)}"
CHECK_CMD="${CHECK_CMD:-make check}"
PROMPT_FILE="${PROMPT_FILE:-PROMPT.md}"
LOG_DIR="${LOG_DIR:-.ralph/logs}"
MAX_ITERS="${MAX_ITERS:-4}"
SLEEP_SECONDS="${SLEEP_SECONDS:-0}"
AGENT_CMD="${AGENT_CMD:-./agent.sh}"

have_metrics="0"
if [[ -f "$metrics_lib" ]]; then
  # shellcheck disable=SC1090
  source "$metrics_lib"
  metrics_init || true
  have_metrics="1"
fi

usage() {
  cat <<'USAGE'
Usage: ./ralph.sh [options]

Options (or env vars):
  --workdir PATH        (WORKDIR)       default: pwd
  --check CMD           (CHECK_CMD)     default: make check
  --prompt FILE         (PROMPT_FILE)   default: PROMPT.md
  --agent CMD           (AGENT_CMD)     default: ./agent.sh
  --max N               (MAX_ITERS)     default: 4
  --sleep SECONDS       (SLEEP_SECONDS) default: 0
  --log-dir DIR         (LOG_DIR)       default: .ralph/logs

Notes:
- CHECK_CMD must return exit code 0 when work is complete.
- AGENT_CMD must not ask for interactive confirmation.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workdir) WORKDIR="$2"; shift 2 ;;
    --check) CHECK_CMD="$2"; shift 2 ;;
    --prompt) PROMPT_FILE="$2"; shift 2 ;;
    --agent) AGENT_CMD="$2"; shift 2 ;;
    --max) MAX_ITERS="$2"; shift 2 ;;
    --sleep) SLEEP_SECONDS="$2"; shift 2 ;;
    --log-dir) LOG_DIR="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

cd "$WORKDIR"
mkdir -p "$LOG_DIR"

if [[ ! -f "$PROMPT_FILE" ]]; then
  echo "Missing prompt file: $PROMPT_FILE" >&2
  exit 1
fi

run_check() {
  set +e
  local out
  out="$(bash -lc "$CHECK_CMD" 2>&1)"
  local ec=$?
  set -e
  printf '%s\n' "$out"
  return "$ec"
}

iter=0
while true; do
  check_started_epoch="$(date +%s)"
  set +e
  check_out="$(run_check)"
  check_ec=$?
  set -e
  check_finished_epoch="$(date +%s)"
  check_duration_s=$((check_finished_epoch - check_started_epoch))

  if [[ "$check_ec" -eq 0 ]]; then
    if [[ "$have_metrics" == "1" ]]; then
      metrics_append_jsonl "$TASK_RUNS_LOG" \
        "event_type=ralph_iteration" \
        "ts_utc=$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
        "loop_session_id=${LOOP_SESSION_ID:-}" \
        "task_id=${CURRENT_TASK_ID:-}" \
        "iteration=${iter}" \
        "check_exit_code=0" \
        "check_duration_s=${check_duration_s}" \
        "agent_duration_s=0" \
        "agent_exit_code=0" \
        "status=check_passed" || true
    fi
    echo "Check passed. Done."
    exit 0
  fi

  iter=$((iter + 1))
  if (( iter > MAX_ITERS )); then
    echo "Max iterations reached ($MAX_ITERS)." >&2
    echo "Last check output (tail):" >&2
    printf '%s\n' "$check_out" | tail -n 200 >&2
    exit 2
  fi

  ts="$(date +"%Y%m%d-%H%M%S")"
  check_file="$LOG_DIR/iter-${iter}-${ts}.check.txt"
  agent_log="$LOG_DIR/iter-${iter}-${ts}.agent.log"
  printf '%s\n' "$check_out" > "$check_file"
  check_tail="$(printf '%s\n' "$check_out" | tail -n 200)"

  agent_started_epoch="$(date +%s)"
  set +e
  {
    cat "$PROMPT_FILE"
    printf '\n\n## Latest check output (tail)\n\n```\n%s\n```\n' "$check_tail"
  } | {
    echo "=== Iteration $iter ($ts) ===" | tee -a "$agent_log"
    echo "Check output saved to: $check_file" | tee -a "$agent_log"
    echo "Running agent command: $AGENT_CMD" | tee -a "$agent_log"
    echo "" | tee -a "$agent_log"
    # shellcheck disable=SC2086
    bash -lc "$AGENT_CMD" 2>&1 | tee -a "$agent_log"
  }
  agent_ec=$?
  set -e
  agent_finished_epoch="$(date +%s)"
  agent_duration_s=$((agent_finished_epoch - agent_started_epoch))

  if [[ "$have_metrics" == "1" ]]; then
    metrics_append_jsonl "$TASK_RUNS_LOG" \
      "event_type=ralph_iteration" \
      "ts_utc=$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
      "loop_session_id=${LOOP_SESSION_ID:-}" \
      "task_id=${CURRENT_TASK_ID:-}" \
      "iteration=${iter}" \
      "check_exit_code=${check_ec}" \
      "check_duration_s=${check_duration_s}" \
      "agent_duration_s=${agent_duration_s}" \
      "agent_exit_code=${agent_ec}" \
      "status=agent_ran" \
      "check_file=${check_file}" \
      "agent_log=${agent_log}" || true
  fi

  if [[ "$agent_ec" -ne 0 ]]; then
    echo "Agent command failed with exit code ${agent_ec}." >&2
    exit "$agent_ec"
  fi

  if (( SLEEP_SECONDS > 0 )); then
    sleep "$SLEEP_SECONDS"
  fi
done
