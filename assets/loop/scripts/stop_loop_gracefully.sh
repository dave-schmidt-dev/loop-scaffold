#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
cd "$repo_root"
loop_state_lib="${repo_root}/scripts/loop_state.sh"
if [[ -f "$loop_state_lib" ]]; then
  # shellcheck disable=SC1090
  source "$loop_state_lib"
  LOOP_STATE_LIB_SOURCED=1
else
  echo "Missing required loop state helper: $loop_state_lib" >&2
  exit 1
fi
loop_scan_lib="${repo_root}/scripts/loop_process_scan.sh"
if [[ -f "$loop_scan_lib" ]]; then
  # shellcheck disable=SC1090
  source "$loop_scan_lib"
else
  echo "Missing required loop scan helper: $loop_scan_lib" >&2
  exit 1
fi

STATE_ROOT="${STATE_ROOT:-.ralph/state}"
STOP_REQUEST_FILE="${STOP_REQUEST_FILE:-${STATE_ROOT}/stop-after-current-task}"
PID_FILE="${PID_FILE:-${STATE_ROOT}/run_all_tasks.pid}"
WAIT_FOR_EXIT="${WAIT_FOR_EXIT:-1}"
POLL_SECONDS="${POLL_SECONDS:-2}"
DRY_RUN="${DRY_RUN:-0}"
FORCE_REQUEST="${FORCE_REQUEST:-0}"

usage() {
  cat <<'USAGE'
Usage: ./scripts/stop_loop_gracefully.sh [options]

Options:
  --stop-file FILE  Stop request file path (default: .ralph/state/stop-after-current-task)
  --pid-file FILE   Loop PID file path (default: .ralph/state/run_all_tasks.pid)
  --wait            Wait for loop process to exit (default)
  --no-wait         Do not wait for loop process to exit
  --poll SECONDS    Poll interval while waiting (default: 2)
  --force           Write stop request even if active loop PID cannot be confirmed
  --dry-run         Show what would happen without writing stop file
  -h, --help        Show help
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --stop-file) STOP_REQUEST_FILE="$2"; shift 2 ;;
    --pid-file) PID_FILE="$2"; shift 2 ;;
    --wait) WAIT_FOR_EXIT="1"; shift ;;
    --no-wait) WAIT_FOR_EXIT="0"; shift ;;
    --poll) POLL_SECONDS="$2"; shift 2 ;;
    --force) FORCE_REQUEST="1"; shift ;;
    --dry-run) DRY_RUN="1"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

loop_pids=()
ignored_scan_pids="$(loop_scan_collect_ignored_pids)"
ignored_scan_pgids="$(loop_scan_collect_ignored_process_groups)"
while IFS= read -r pid; do
  [[ -z "$pid" ]] && continue
  loop_pids+=("$pid")
done < <(loop_scan_collect_active_loop_pids "$PID_FILE" "$ignored_scan_pids" "1" "$ignored_scan_pgids")

if [[ "$DRY_RUN" == "1" ]]; then
  echo "[stop-loop] dry-run enabled"
  echo "[stop-loop] stop request file: ${STOP_REQUEST_FILE}"
  echo "[stop-loop] loop PID file: ${PID_FILE}"
  if (( ${#loop_pids[@]} == 0 )); then
    echo "[stop-loop] no active run_all_tasks loop detected from PID file or process scan"
  else
    echo "[stop-loop] active loop PID(s): ${loop_pids[*]}"
  fi
  exit 0
fi

if (( ${#loop_pids[@]} == 0 )) && [[ "$FORCE_REQUEST" != "1" ]]; then
  echo "[stop-loop] no active loop PID detected; stop request not written." >&2
  echo "[stop-loop] if needed, rerun with --force to leave a stop marker for a legacy loop." >&2
  exit 1
fi

mkdir -p "$(dirname "$STOP_REQUEST_FILE")"
printf '%s\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" > "$STOP_REQUEST_FILE"
echo "[stop-loop] requested graceful stop via ${STOP_REQUEST_FILE}"
if (( ${#loop_pids[@]} == 0 )); then
  echo "[stop-loop] active loop PID not confirmed; request file written."
  echo "[stop-loop] if a loop is active, it will stop at its next natural breakpoint."
else
  echo "[stop-loop] active loop PID(s): ${loop_pids[*]}"
fi

if [[ "$WAIT_FOR_EXIT" != "1" ]]; then
  exit 0
fi

if (( ${#loop_pids[@]} == 0 )); then
  echo "[stop-loop] no active PID available for wait; returning after writing stop request."
  exit 0
fi

echo "[stop-loop] waiting for loop exit at next natural breakpoint..."
loop_state_wait_for_pids_to_exit "$POLL_SECONDS" "${loop_pids[@]}"

echo "[stop-loop] loop exited cleanly."
