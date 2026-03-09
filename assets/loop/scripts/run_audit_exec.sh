#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
cd "$repo_root"

metrics_lib="${repo_root}/scripts/metrics_lib.sh"
exit_codes="${repo_root}/scripts/exit_codes.sh"
checkpoint_exec_lib="${repo_root}/scripts/checkpoint_exec_lib.sh"

TASKS_FILE="${TASKS_FILE:-tasks.md}"
MODE="${MODE:-final}"
TASK_ID="${TASK_ID:-}"
PHASE_NAME="${PHASE_NAME:-}"
AUDIT_PROMPT_FILE="${AUDIT_PROMPT_FILE:-AUDIT_PROMPT.md}"
AUDITOR_CMD="${AUDITOR_CMD:-./auditor.sh}"
AUDIT_LOG_ROOT="${AUDIT_LOG_ROOT:-.ralph/reviews}"
FINDINGS_ROOT="${FINDINGS_ROOT:-.ralph/findings}"
STATE_ROOT="${STATE_ROOT:-.ralph/state}"
AUDIT_RESULT_FILE="${AUDIT_RESULT_FILE:-${STATE_ROOT}/latest_audit_result.json}"
AUDIT_SNIPPET_LINES="${AUDIT_SNIPPET_LINES:-160}"
AUDIT_EXEC_TIMEOUT_SECONDS="${AUDIT_EXEC_TIMEOUT_SECONDS:-1200}"
AUDIT_EXEC_HEARTBEAT_SECONDS="${AUDIT_EXEC_HEARTBEAT_SECONDS:-20}"
AUDIT_OUTER_TIMEOUT_SECONDS="${AUDIT_OUTER_TIMEOUT_SECONDS:-}"
AUDIT_PRECHECK_CMD="${AUDIT_PRECHECK_CMD:-make check-fast}"
AUDIT_PRECHECK_LINES="${AUDIT_PRECHECK_LINES:-160}"
AUDIT_AUTOREMEDIATE_ON_FAIL="${AUDIT_AUTOREMEDIATE_ON_FAIL:-1}"
AUDIT_AUTORESUME_ON_REMEDIATION="${AUDIT_AUTORESUME_ON_REMEDIATION:-1}"
AUDIT_AUTORESUME_CMD="${AUDIT_AUTORESUME_CMD:-./scripts/run_all_tasks.sh}"
FINDINGS_PROCESS_CMD="${FINDINGS_PROCESS_CMD:-./scripts/process_findings.py}"
FINDINGS_BLOCKER_SEVERITY="${FINDINGS_BLOCKER_SEVERITY:-medium}"
FINDINGS_DEFAULT_SPEC="${FINDINGS_DEFAULT_SPEC:-REQ-009}"
FINDINGS_DEFAULT_TEST="${FINDINGS_DEFAULT_TEST:-tests/spec/test_mvp_traceability.py::MvpTraceabilityTests.test_req_009_traceability}"
AUDIT_AUTOREMEDIATION_CREATED=0

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
Usage: ./scripts/run_audit_exec.sh [options]

Options:
  --mode MODE        Audit mode: final (default: final)
  --task TASK-###    Optional focus task ID
  --phase NAME       Optional phase/section label
  --prompt FILE      Audit prompt file (default: AUDIT_PROMPT.md)
  --auditor CMD      Auditor command (default: ./auditor.sh)
  --log-root DIR     Audit log directory (default: .ralph/reviews)
  --findings-root DIR Findings output directory (default: .ralph/findings)
  -h, --help         Show help
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode) MODE="$2"; shift 2 ;;
    --task) TASK_ID="$2"; shift 2 ;;
    --phase) PHASE_NAME="$2"; shift 2 ;;
    --prompt) AUDIT_PROMPT_FILE="$2"; shift 2 ;;
    --auditor) AUDITOR_CMD="$2"; shift 2 ;;
    --log-root) AUDIT_LOG_ROOT="$2"; shift 2 ;;
    --findings-root) FINDINGS_ROOT="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

maybe_autoremediate_findings() {
  local should_run="${1:-0}"
  local summary_file=""
  local new_tasks=""

  if [[ "$should_run" != "1" ]]; then
    return 0
  fi
  if [[ ! -f "$CHECKPOINT_EXEC_FINDINGS_FILE" || ! -s "$CHECKPOINT_EXEC_FINDINGS_FILE" ]]; then
    return 0
  fi
  if [[ ! -f "$TASKS_FILE" ]]; then
    return 0
  fi
  if [[ ! -x "$FINDINGS_PROCESS_CMD" ]]; then
    return 0
  fi

  summary_file="$(mktemp)"
  if ! "$FINDINGS_PROCESS_CMD" \
    --findings-file "$CHECKPOINT_EXEC_FINDINGS_FILE" \
    --tasks-file "$TASKS_FILE" \
    --summary-file "$summary_file" \
    --source "auditor" \
    --mode "$MODE" \
    --default-spec "$FINDINGS_DEFAULT_SPEC" \
    --default-test "$FINDINGS_DEFAULT_TEST" \
    --blocker-severity "$FINDINGS_BLOCKER_SEVERITY" >/dev/null 2>&1; then
    rm -f "$summary_file"
    return 0
  fi

  new_tasks="$(python3 - "$summary_file" <<'PY'
import json
import sys
from pathlib import Path

try:
    obj = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
except Exception:
    print("0")
    raise SystemExit(0)
print(str(obj.get("new_tasks", 0)))
PY
)"
  rm -f "$summary_file"
  if [[ "$new_tasks" =~ ^[0-9]+$ ]] && [[ "$new_tasks" -gt 0 ]]; then
    AUDIT_AUTOREMEDIATION_CREATED="$new_tasks"
    echo "Auto-remediation: created ${new_tasks} task(s) from audit findings."
  fi
}

maybe_autoresume_loop() {
  if [[ "$AUDIT_AUTOREMEDIATION_CREATED" =~ ^[0-9]+$ ]] && [[ "$AUDIT_AUTOREMEDIATION_CREATED" -gt 0 ]]; then
    if [[ -n "${LOOP_SESSION_ID:-}" ]]; then
      return 0
    fi
    if [[ "$AUDIT_AUTORESUME_ON_REMEDIATION" == "1" && -n "$AUDIT_AUTORESUME_CMD" ]]; then
      echo "Auto-resume: launching loop command after audit remediation: ${AUDIT_AUTORESUME_CMD}"
      exec bash -lc "$AUDIT_AUTORESUME_CMD"
    fi
  fi
}

# Shared secure temp dir + mkfifo stream handling lives in checkpoint_exec_lib.sh.
CHECKPOINT_LABEL="Audit"
CHECKPOINT_SOURCE="auditor"
CHECKPOINT_MODE="$MODE"
CHECKPOINT_TASK_ID="$TASK_ID"
CHECKPOINT_PHASE_NAME="$PHASE_NAME"
CHECKPOINT_PROMPT_FILE="$AUDIT_PROMPT_FILE"
CHECKPOINT_AGENT_CMD="$AUDITOR_CMD"
CHECKPOINT_AGENT_LABEL="Auditor"
CHECKPOINT_LOG_ROOT="$AUDIT_LOG_ROOT"
CHECKPOINT_LOG_PREFIX="audit"
CHECKPOINT_FINDINGS_ROOT="$FINDINGS_ROOT"
CHECKPOINT_RESULT_FILE="$AUDIT_RESULT_FILE"
CHECKPOINT_SNIPPET_LINES="$AUDIT_SNIPPET_LINES"
CHECKPOINT_EXEC_TIMEOUT_SECONDS="$AUDIT_EXEC_TIMEOUT_SECONDS"
CHECKPOINT_EXEC_HEARTBEAT_SECONDS="$AUDIT_EXEC_HEARTBEAT_SECONDS"
CHECKPOINT_OUTER_TIMEOUT_SECONDS="$AUDIT_OUTER_TIMEOUT_SECONDS"
CHECKPOINT_PRECHECK_CMD="$AUDIT_PRECHECK_CMD"
CHECKPOINT_PRECHECK_LINES="$AUDIT_PRECHECK_LINES"
CHECKPOINT_PRECHECK_PREFIX="run_audit_exec"
CHECKPOINT_CONTEXT_HEADING="Audit Context"
CHECKPOINT_FINDINGS_ENV_NAME="AUDIT_FINDINGS_FILE"
CHECKPOINT_PASS_TOKEN="AUDIT_PASS"
CHECKPOINT_FAIL_TOKEN="AUDIT_FAIL"
CHECKPOINT_MISSING_TOKEN_TITLE="Auditor finished without AUDIT_PASS/AUDIT_FAIL token"
CHECKPOINT_MISSING_TOKEN_FILE="auditor.sh"
CHECKPOINT_MISSING_TOKEN_FIX_HINT="Emit a final AUDIT_PASS or AUDIT_FAIL token on completion."
CHECKPOINT_EVENT_TYPE="audit_checkpoint"
CHECKPOINT_COMMAND_EXIT_FIELD="auditor_command_exit_code"
CHECKPOINT_TIMEOUT_ENV_NAME="AUDITOR_TIMEOUT_SECONDS"
CHECKPOINT_RECENT_LOG_COUNT="5"
CHECKPOINT_INCLUDE_TASK_METADATA="0"

checkpoint_exec_run

if [[ "$CHECKPOINT_EXEC_FINAL_EC" -eq "${EXIT_SUCCESS:-0}" ]]; then
  echo "Audit passed (${MODE})."
  exit "$CHECKPOINT_EXEC_FINAL_EC"
fi

if [[ "$CHECKPOINT_EXEC_FINAL_EC" -eq "${EXIT_REVIEW_FAIL:-2}" ]]; then
  if [[ "$AUDIT_AUTOREMEDIATE_ON_FAIL" == "1" ]]; then
    maybe_autoremediate_findings "1"
    maybe_autoresume_loop
  fi
  echo "Audit failed (${MODE}). See ${CHECKPOINT_EXEC_LOG_FILE}" >&2
  exit "$CHECKPOINT_EXEC_FINAL_EC"
fi

if [[ "$CHECKPOINT_EXEC_FINAL_EC" -eq "${EXIT_QUOTA_EXHAUSTED:-10}" ]]; then
  echo "Audit quota exhausted (${MODE}). See ${CHECKPOINT_EXEC_LOG_FILE}" >&2
  exit "$CHECKPOINT_EXEC_FINAL_EC"
fi

if [[ "$CHECKPOINT_EXEC_FINAL_EC" -eq "${EXIT_TIMEOUT:-11}" ]]; then
  if [[ "$AUDIT_AUTOREMEDIATE_ON_FAIL" == "1" ]]; then
    maybe_autoremediate_findings "1"
    maybe_autoresume_loop
  fi
  echo "Audit timed out (${MODE}). See ${CHECKPOINT_EXEC_LOG_FILE}" >&2
  exit "$CHECKPOINT_EXEC_FINAL_EC"
fi

if [[ "$CHECKPOINT_EXEC_FINAL_EC" -eq "${EXIT_NO_OUTPUT_TIMEOUT:-12}" ]]; then
  if [[ "$AUDIT_AUTOREMEDIATE_ON_FAIL" == "1" ]]; then
    maybe_autoremediate_findings "1"
    maybe_autoresume_loop
  fi
  echo "Audit failed due to no output timeout (${MODE}). See ${CHECKPOINT_EXEC_LOG_FILE}" >&2
  exit "$CHECKPOINT_EXEC_FINAL_EC"
fi

if [[ "$CHECKPOINT_EXEC_FINAL_EC" -eq "${EXIT_MODEL_POLICY_VIOLATION:-13}" ]]; then
  if [[ "$AUDIT_AUTOREMEDIATE_ON_FAIL" == "1" ]]; then
    maybe_autoremediate_findings "1"
    maybe_autoresume_loop
  fi
  echo "Audit failed due to model policy violation (${MODE}). See ${CHECKPOINT_EXEC_LOG_FILE}" >&2
  exit "$CHECKPOINT_EXEC_FINAL_EC"
fi

if [[ "$AUDIT_AUTOREMEDIATE_ON_FAIL" == "1" ]]; then
  maybe_autoremediate_findings "1"
  maybe_autoresume_loop
fi
echo "Audit did not emit AUDIT_PASS/AUDIT_FAIL token. See ${CHECKPOINT_EXEC_LOG_FILE}" >&2
exit "$CHECKPOINT_EXEC_FINAL_EC"
