#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
cd "$repo_root"

metrics_lib="${repo_root}/scripts/metrics_lib.sh"
exit_codes="${repo_root}/scripts/exit_codes.sh"
checkpoint_exec_lib="${repo_root}/scripts/checkpoint_exec_lib.sh"

TASKS_FILE="${TASKS_FILE:-tasks.md}"
MODE="${MODE:-quick}"
TASK_ID="${TASK_ID:-}"
PHASE_NAME="${PHASE_NAME:-}"
REVIEW_PROMPT_FILE="${REVIEW_PROMPT_FILE:-REVIEW_PROMPT.md}"
REVIEWER_CMD="${REVIEWER_CMD:-./reviewer.sh}"
REVIEW_LOG_ROOT="${REVIEW_LOG_ROOT:-.ralph/reviews}"
FINDINGS_ROOT="${FINDINGS_ROOT:-.ralph/findings}"
STATE_ROOT="${STATE_ROOT:-.ralph/state}"
REVIEW_RESULT_FILE="${REVIEW_RESULT_FILE:-${STATE_ROOT}/latest_review_result.json}"
REVIEW_SNIPPET_LINES="${REVIEW_SNIPPET_LINES:-120}"
REVIEW_EXEC_TIMEOUT_SECONDS="${REVIEW_EXEC_TIMEOUT_SECONDS:-900}"
REVIEW_EXEC_HEARTBEAT_SECONDS="${REVIEW_EXEC_HEARTBEAT_SECONDS:-20}"
REVIEW_OUTER_TIMEOUT_SECONDS="${REVIEW_OUTER_TIMEOUT_SECONDS:-}"
REVIEW_PRECHECK_CMD="${REVIEW_PRECHECK_CMD:-make check-fast}"
REVIEW_PRECHECK_LINES="${REVIEW_PRECHECK_LINES:-120}"

if [[ -f "$exit_codes" ]]; then
  # shellcheck disable=SC1090
  source "$exit_codes"
fi

if [[ ! -f "$checkpoint_exec_lib" ]]; then
  echo "Missing required checkpoint exec helper: $checkpoint_exec_lib" >&2
  exit 1
fi
# shellcheck disable=SC1090
source "$checkpoint_exec_lib"

have_metrics="0"
if [[ -f "$metrics_lib" ]]; then
  # shellcheck disable=SC1090
  source "$metrics_lib"
  metrics_init || true
  have_metrics="1"
fi

usage() {
  cat <<'USAGE'
Usage: ./scripts/run_review_exec.sh [options]

Options:
  --mode MODE        Review mode: quick | phase | final | architecture (default: quick)
  --task TASK-###    Optional focus task ID
  --phase NAME       Optional phase/section label
  --prompt FILE      Review prompt file (default: REVIEW_PROMPT.md)
  --reviewer CMD     Reviewer command (default: ./reviewer.sh)
  --log-root DIR     Review log directory (default: .ralph/reviews)
  --findings-root DIR Findings output directory (default: .ralph/findings)
  -h, --help         Show help
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode) MODE="$2"; shift 2 ;;
    --task) TASK_ID="$2"; shift 2 ;;
    --phase) PHASE_NAME="$2"; shift 2 ;;
    --prompt) REVIEW_PROMPT_FILE="$2"; shift 2 ;;
    --reviewer) REVIEWER_CMD="$2"; shift 2 ;;
    --log-root) REVIEW_LOG_ROOT="$2"; shift 2 ;;
    --findings-root) FINDINGS_ROOT="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

# Shared secure temp dir + mkfifo stream handling lives in checkpoint_exec_lib.sh.
CHECKPOINT_LABEL="Review"
CHECKPOINT_SOURCE="reviewer"
CHECKPOINT_MODE="$MODE"
CHECKPOINT_TASK_ID="$TASK_ID"
CHECKPOINT_PHASE_NAME="$PHASE_NAME"
CHECKPOINT_PROMPT_FILE="$REVIEW_PROMPT_FILE"
CHECKPOINT_AGENT_CMD="$REVIEWER_CMD"
CHECKPOINT_AGENT_LABEL="Reviewer"
CHECKPOINT_LOG_ROOT="$REVIEW_LOG_ROOT"
CHECKPOINT_LOG_PREFIX="review"
CHECKPOINT_FINDINGS_ROOT="$FINDINGS_ROOT"
CHECKPOINT_RESULT_FILE="$REVIEW_RESULT_FILE"
CHECKPOINT_SNIPPET_LINES="$REVIEW_SNIPPET_LINES"
CHECKPOINT_EXEC_TIMEOUT_SECONDS="$REVIEW_EXEC_TIMEOUT_SECONDS"
CHECKPOINT_EXEC_HEARTBEAT_SECONDS="$REVIEW_EXEC_HEARTBEAT_SECONDS"
CHECKPOINT_OUTER_TIMEOUT_SECONDS="$REVIEW_OUTER_TIMEOUT_SECONDS"
CHECKPOINT_PRECHECK_CMD="$REVIEW_PRECHECK_CMD"
CHECKPOINT_PRECHECK_LINES="$REVIEW_PRECHECK_LINES"
CHECKPOINT_PRECHECK_PREFIX="run_review_exec"
CHECKPOINT_CONTEXT_HEADING="Review Context"
CHECKPOINT_FINDINGS_ENV_NAME="REVIEW_FINDINGS_FILE"
CHECKPOINT_PASS_TOKEN="REVIEW_PASS"
CHECKPOINT_FAIL_TOKEN="REVIEW_FAIL"
CHECKPOINT_MISSING_TOKEN_TITLE="Reviewer finished without REVIEW_PASS/REVIEW_FAIL token"
CHECKPOINT_MISSING_TOKEN_FILE="reviewer.sh"
CHECKPOINT_MISSING_TOKEN_FIX_HINT="Emit a final REVIEW_PASS or REVIEW_FAIL token on completion."
CHECKPOINT_EVENT_TYPE="review_checkpoint"
CHECKPOINT_COMMAND_EXIT_FIELD="reviewer_command_exit_code"
CHECKPOINT_TIMEOUT_ENV_NAME="REVIEW_TIMEOUT_SECONDS"
CHECKPOINT_RECENT_LOG_COUNT="3"
CHECKPOINT_INCLUDE_TASK_METADATA="1"

checkpoint_exec_run

checkpoint_exec_emit_final_message \
  "Review" \
  "$MODE" \
  "$CHECKPOINT_EXEC_FINAL_EC" \
  "$CHECKPOINT_EXEC_LOG_FILE" \
  "REVIEW_PASS" \
  "REVIEW_FAIL"
exit "$CHECKPOINT_EXEC_FINAL_EC"
