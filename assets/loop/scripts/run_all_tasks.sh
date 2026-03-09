#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Preserve colorized operator output even when run_all_tasks.sh is invoked directly.
if [[ "${RALPH_COLORIZED:-0}" != "1" ]] && [[ -x "${script_dir}/colorize_loop_output.sh" ]]; then
  if [[ "${FORCE_COLOR:-}" == "1" || ( -z "${NO_COLOR:-}" && -t 1 ) ]]; then
    export RALPH_COLORIZED=1
    exec > >("${script_dir}/colorize_loop_output.sh")
    exec 2>&1
  fi
fi

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

metrics_lib="${repo_root}/scripts/metrics_lib.sh"
dispatcher="${repo_root}/scripts/agent_dispatcher.sh"
exit_codes="${repo_root}/scripts/exit_codes.sh"
PYTHON_BIN="${PYTHON_BIN:-}"

if [[ -f "$dispatcher" ]]; then
  source "$dispatcher"
fi
if [[ -f "$exit_codes" ]]; then
  # shellcheck disable=SC1090
  source "$exit_codes"
fi

if [[ -z "$PYTHON_BIN" ]]; then
  if [[ -n "${VIRTUAL_ENV:-}" && -x "${VIRTUAL_ENV}/bin/python" ]]; then
    PYTHON_BIN="${VIRTUAL_ENV}/bin/python"
  elif [[ -x "${repo_root}/.venv/bin/python" ]]; then
    PYTHON_BIN="${repo_root}/.venv/bin/python"
  else
    PYTHON_BIN="python3"
  fi
fi

TASKS_FILE="${TASKS_FILE:-tasks.md}"
MAX_TASKS="${MAX_TASKS:-200}"
REVIEW_ENABLED="${REVIEW_ENABLED:-1}"
PHASE_REVIEW_ENABLED="${PHASE_REVIEW_ENABLED:-1}"
REVIEW_EVERY_TASKS="${REVIEW_EVERY_TASKS:-1}"
REVIEW_CMD="${REVIEW_CMD:-./scripts/run_review_exec.sh}"
AUDIT_ENABLED="${AUDIT_ENABLED:-1}"
AUDIT_CMD="${AUDIT_CMD:-./scripts/run_audit_exec.sh}"
ARCH_REVIEW_ENABLED="${ARCH_REVIEW_ENABLED:-1}"
ARCH_REVIEW_CMD="${ARCH_REVIEW_CMD:-$REVIEW_CMD}"
ARCH_REVIEW_PROMPT_FILE="${ARCH_REVIEW_PROMPT_FILE:-ARCH_REVIEW_PROMPT.md}"
ARCH_REVIEW_MAX_RETRIES="${ARCH_REVIEW_MAX_RETRIES:-2}"
FINDINGS_PROCESS_CMD="${FINDINGS_PROCESS_CMD:-./scripts/process_findings.py}"
FINDINGS_ROOT="${FINDINGS_ROOT:-.ralph/findings}"
FINDINGS_BLOCKER_SEVERITY="${FINDINGS_BLOCKER_SEVERITY:-medium}"
FINDINGS_DEFAULT_SPEC="${FINDINGS_DEFAULT_SPEC:-REQ-009}"
FINDINGS_DEFAULT_TEST="${FINDINGS_DEFAULT_TEST:-tests/spec/test_mvp_traceability.py::MvpTraceabilityTests.test_req_009_traceability}"
LOW_FINDINGS_TO_GH_ISSUES="${LOW_FINDINGS_TO_GH_ISSUES:-1}"
ACCEPTED_RISK_TO_GH_ISSUES="${ACCEPTED_RISK_TO_GH_ISSUES:-1}"
FINAL_GATE_MAX_RETRIES="${FINAL_GATE_MAX_RETRIES:-3}"
QUOTA_WAIT_ENABLED="${QUOTA_WAIT_ENABLED:-1}"
QUOTA_WAIT_MAX_SECONDS="${QUOTA_WAIT_MAX_SECONDS:-18000}"
QUOTA_WAIT_POLL_SECONDS="${QUOTA_WAIT_POLL_SECONDS:-300}"
STOP_REQUEST_FILE="${STOP_REQUEST_FILE:-${STATE_ROOT:-.ralph/state}/stop-after-current-task}"
PID_FILE="${PID_FILE:-${STATE_ROOT:-.ralph/state}/run_all_tasks.pid}"
# Scope loop lock under STATE_ROOT when available to avoid cross-run conflicts
# in tests and concurrent temporary workspaces. If STATE_ROOT is unset, fall
# back to the historical default path.
LOCK_DIR="${LOCK_DIR:-${STATE_ROOT:-.ralph/state}/run_all_tasks.lock}"
ALLOW_PARALLEL_LOOPS="${ALLOW_PARALLEL_LOOPS:-0}"
ACTIVE_LOOP_SCAN_ENABLED="${ACTIVE_LOOP_SCAN_ENABLED:-1}"
LOG_ROOT="${LOG_ROOT:-.ralph/logs}"
LOG_PRUNE_ENABLED="${LOG_PRUNE_ENABLED:-1}"
LOG_PRUNE_DAYS="${LOG_PRUNE_DAYS:-14}"
LOG_PRUNE_MAX_MB="${LOG_PRUNE_MAX_MB:-1024}"
LOG_PRUNE_MIN_KEEP="${LOG_PRUNE_MIN_KEEP:-200}"
LOG_PRUNE_EVERY_TASKS="${LOG_PRUNE_EVERY_TASKS:-1}"
STATE_ROOT="${STATE_ROOT:-.ralph/state}"
LOOP_CHECKPOINT_ENABLED="${LOOP_CHECKPOINT_ENABLED:-1}"
LOOP_CHECKPOINT_FILE="${LOOP_CHECKPOINT_FILE:-${STATE_ROOT}/loop_checkpoint.json}"
LOOP_AUTO_RESUME_CHECKPOINT="${LOOP_AUTO_RESUME_CHECKPOINT:-1}"
LOOP_STOP_REASON_FILE="${LOOP_STOP_REASON_FILE:-${STATE_ROOT}/last_stop_reason}"
REVIEW_RESULT_FILE="${REVIEW_RESULT_FILE:-${STATE_ROOT}/latest_review_result.json}"
AUDIT_RESULT_FILE="${AUDIT_RESULT_FILE:-${STATE_ROOT}/latest_audit_result.json}"
LOOP_ALERT_CMD="${LOOP_ALERT_CMD:-}"
LOOP_FRAMEWORK_VERSION="${LOOP_FRAMEWORK_VERSION:-v2.2.0}"
WATCHDOG_ENABLED="${WATCHDOG_ENABLED:-1}"
WATCHDOG_MAX_TASK_SECONDS="${WATCHDOG_MAX_TASK_SECONDS:-5400}"
WATCHDOG_WARN_LIMIT="${WATCHDOG_WARN_LIMIT:-3}"
WATCHDOG_HARD_STOP="${WATCHDOG_HARD_STOP:-0}"
SELF_HEAL_ENABLED="${SELF_HEAL_ENABLED:-1}"
SELF_HEAL_MAX_RETRIES_PER_TASK="${SELF_HEAL_MAX_RETRIES_PER_TASK:-3}"
SELF_HEAL_RETRY_DELAY_SECONDS="${SELF_HEAL_RETRY_DELAY_SECONDS:-2}"
REVIEW_SELF_HEAL_ENABLED="${REVIEW_SELF_HEAL_ENABLED:-1}"
REVIEW_SELF_HEAL_MAX_RETRIES="${REVIEW_SELF_HEAL_MAX_RETRIES:-3}"
REVIEW_SELF_HEAL_RETRY_DELAY_SECONDS="${REVIEW_SELF_HEAL_RETRY_DELAY_SECONDS:-2}"
AGENT_FAILOVER_MAX_ATTEMPTS="${AGENT_FAILOVER_MAX_ATTEMPTS:-3}"
IMPLEMENTOR_OVERRIDE="${IMPLEMENTOR_OVERRIDE:-}"
AUDITOR_OVERRIDE="${AUDITOR_OVERRIDE:-}"
SKIP_AGENT_HEALTH_CHECKS="${SKIP_AGENT_HEALTH_CHECKS:-0}"
AGENT_SELECTION_CONFIRM="${AGENT_SELECTION_CONFIRM:-auto}"
DRY_RUN="${DRY_RUN:-0}"
LIST_AGENTS_ONLY=0

have_metrics="0"
if [[ -f "$metrics_lib" ]]; then
  # shellcheck disable=SC1090
  source "$metrics_lib"
  metrics_init || true
  have_metrics="1"
fi

usage() {
  cat <<'USAGE'
Usage: ./scripts/run_all_tasks.sh [options] [-- <run_next_task args>]

Options:
  --max-tasks N   Maximum number of tasks to attempt this run (default: 200)
  --review-every N  Run quick review every N completed tasks (default: 1)
  --no-review     Disable periodic quick reviews
  --no-phase-review Disable phase-boundary reviews
  --review-cmd CMD  Review command (default: ./scripts/run_review_exec.sh)
  --no-audit      Disable final auditor checkpoint loop
  --audit-cmd CMD Auditor command wrapper (default: ./scripts/run_audit_exec.sh)
  --no-arch-review Disable final architecture review checkpoint
  --arch-review-cmd CMD Architecture review command wrapper (default: review command)
  --arch-review-prompt FILE Architecture review prompt file (default: ARCH_REVIEW_PROMPT.md)
  --arch-review-retries N Max retries for architecture review without actionable findings (default: 2)
  --final-gate-retries N  Max retries of review+audit final gate without new tasks (default: 3)
  --quota-wait-max-seconds N  Max quota wait window before exit (default: 18000)
  --quota-wait-poll-seconds N Sleep per quota wait cycle (default: 300)
  --stop-file FILE  Stop request file path (default: .ralph/state/stop-after-current-task)
  --pid-file FILE   Loop PID file path (default: .ralph/state/run_all_tasks.pid)
  --lock-dir DIR    Lock directory path (default: .ralph/state/run_all_tasks.lock)
  --allow-parallel-loops  Allow starting even when another loop PID is active
  --active-scan     Enable active-process scan for already-running loop sessions
  --no-watchdog     Disable long-running task watchdog
  --watchdog-seconds N  Watchdog threshold in seconds (default: 5400)
  --watchdog-warn-limit N  Stop after N consecutive watchdog warnings (default: 3)
  --watchdog-hard-stop  Stop loop immediately on watchdog threshold breach
  --no-self-heal    Disable automatic retry of failed task attempts
  --self-heal-retries N  Max retries per task when task attempt fails (default: 3)
  --self-heal-delay N  Seconds to wait before each self-heal retry (default: 2)
  --no-log-prune    Disable automatic loop log pruning
  --log-prune-days N  Retain logs newer than N days when possible (default: 14)
  --log-prune-max-mb N  Approximate max retained log size in MiB (default: 1024)
  --log-prune-min-keep N  Minimum number of newest log files to keep (default: 200)
  --log-prune-every N  Run log pruning every N task iterations (default: 1)
  --implementor SELECTOR  Override implementer selection (index, bin, or full config)
  --auditor SELECTOR      Override auditor selection (index, bin, or full config)
  --list-agents           Print configured implementer/reviewer and auditor options, then exit
  --dry-run               Show selected agents + next task and exit without running
  --skip-agent-health-checks  Skip startup health checks for selected agents
  --confirm-agents        Always prompt to confirm selected agents before running
  --no-confirm-agents     Never prompt for startup agent confirmation
  -h, --help      Show help

All remaining arguments are forwarded to ./scripts/run_next_task.sh.
Examples:
  ./scripts/run_all_tasks.sh
  ./scripts/run_all_tasks.sh --max-tasks 10 -- --max 6
  ./scripts/run_all_tasks.sh -- --commit
USAGE
}

forward_args=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --max-tasks) MAX_TASKS="$2"; shift 2 ;;
    --review-every) REVIEW_EVERY_TASKS="$2"; shift 2 ;;
    --no-review) REVIEW_ENABLED="0"; shift ;;
    --no-phase-review) PHASE_REVIEW_ENABLED="0"; shift ;;
    --review-cmd) REVIEW_CMD="$2"; shift 2 ;;
    --no-audit) AUDIT_ENABLED="0"; shift ;;
    --audit-cmd) AUDIT_CMD="$2"; shift 2 ;;
    --no-arch-review) ARCH_REVIEW_ENABLED="0"; shift ;;
    --arch-review-cmd) ARCH_REVIEW_CMD="$2"; shift 2 ;;
    --arch-review-prompt) ARCH_REVIEW_PROMPT_FILE="$2"; shift 2 ;;
    --arch-review-retries) ARCH_REVIEW_MAX_RETRIES="$2"; shift 2 ;;
    --final-gate-retries) FINAL_GATE_MAX_RETRIES="$2"; shift 2 ;;
    --quota-wait-max-seconds) QUOTA_WAIT_MAX_SECONDS="$2"; shift 2 ;;
    --quota-wait-poll-seconds) QUOTA_WAIT_POLL_SECONDS="$2"; shift 2 ;;
    --stop-file) STOP_REQUEST_FILE="$2"; shift 2 ;;
    --pid-file) PID_FILE="$2"; shift 2 ;;
    --lock-dir) LOCK_DIR="$2"; shift 2 ;;
    --allow-parallel-loops) ALLOW_PARALLEL_LOOPS="1"; shift ;;
    --active-scan) ACTIVE_LOOP_SCAN_ENABLED="1"; shift ;;
    --no-watchdog) WATCHDOG_ENABLED="0"; shift ;;
    --watchdog-seconds) WATCHDOG_MAX_TASK_SECONDS="$2"; shift 2 ;;
    --watchdog-warn-limit) WATCHDOG_WARN_LIMIT="$2"; shift 2 ;;
    --watchdog-hard-stop) WATCHDOG_HARD_STOP="1"; shift ;;
    --no-self-heal) SELF_HEAL_ENABLED="0"; shift ;;
    --self-heal-retries) SELF_HEAL_MAX_RETRIES_PER_TASK="$2"; shift 2 ;;
    --self-heal-delay) SELF_HEAL_RETRY_DELAY_SECONDS="$2"; shift 2 ;;
    --no-log-prune) LOG_PRUNE_ENABLED="0"; shift ;;
    --log-prune-days) LOG_PRUNE_DAYS="$2"; shift 2 ;;
    --log-prune-max-mb) LOG_PRUNE_MAX_MB="$2"; shift 2 ;;
    --log-prune-min-keep) LOG_PRUNE_MIN_KEEP="$2"; shift 2 ;;
    --log-prune-every) LOG_PRUNE_EVERY_TASKS="$2"; shift 2 ;;
    --implementor) IMPLEMENTOR_OVERRIDE="$2"; shift 2 ;;
    --auditor) AUDITOR_OVERRIDE="$2"; shift 2 ;;
    --list-agents) LIST_AGENTS_ONLY=1; shift ;;
    --dry-run) DRY_RUN="1"; shift ;;
    --skip-agent-health-checks) SKIP_AGENT_HEALTH_CHECKS="1"; shift ;;
    --confirm-agents) AGENT_SELECTION_CONFIRM="always"; shift ;;
    --no-confirm-agents) AGENT_SELECTION_CONFIRM="never"; shift ;;
    --) shift; forward_args+=("$@"); break ;;
    -h|--help) usage; exit 0 ;;
    *) forward_args+=("$1"); shift ;;
  esac
done

if [[ ! -f "$TASKS_FILE" ]]; then
  echo "Missing tasks file: $TASKS_FILE" >&2
  exit 1
fi

is_truthy_value() {
  local value="${1:-}"
  case "$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')" in
    1|true|yes|on) return 0 ;;
    *) return 1 ;;
  esac
}

print_configured_agents() {
  echo "Configured implementer/reviewer options:"
  if declare -F list_configured_implementors >/dev/null 2>&1; then
    list_configured_implementors
  else
    echo "  (dispatcher helper unavailable)"
  fi
  echo ""
  echo "Configured auditor options:"
  if declare -F list_configured_auditors >/dev/null 2>&1; then
    list_configured_auditors
  else
    echo "  (dispatcher helper unavailable)"
  fi
}

panel_out() {
  local line="$1"
  if [[ -n "${PANEL_OUTPUT_STREAM:-}" ]]; then
    printf '%s\n' "$line" >"$PANEL_OUTPUT_STREAM"
  else
    printf '%s\n' "$line"
  fi
}

panel_prompt() {
  local text="$1"
  if [[ -n "${PANEL_OUTPUT_STREAM:-}" ]]; then
    printf '%s' "$text" >"$PANEL_OUTPUT_STREAM"
  else
    printf '%s' "$text"
  fi
}

resolve_agent_override_or_fail() {
  local role="$1"
  local selector="$2"
  local resolved
  if ! declare -F resolve_configured_agent_override >/dev/null 2>&1; then
    echo "Dispatcher override helper is unavailable for role=${role}." >&2
    return 1
  fi
  resolved="$(resolve_configured_agent_override "$role" "$selector" || true)"
  if [[ -z "$resolved" ]]; then
    echo "Invalid ${role} override: ${selector}" >&2
    print_configured_agents >&2
    return 1
  fi
  echo "$resolved"
}

validate_selected_agent_health() {
  local role="$1"
  local resolved="$2"
  local bin
  if is_truthy_value "$SKIP_AGENT_HEALTH_CHECKS"; then
    return 0
  fi
  bin="${resolved%%:*}"
  if ! check_agent_health "$bin"; then
    echo "Selected ${role} failed health check: ${resolved}" >&2
    return 1
  fi
  return 0
}

is_agent_runtime_failure() {
  local exit_code="${1:-0}"
  local reason="${2:-}"
  case "$exit_code" in
    10|11|12|13|124|125) return 0 ;;
  esac
  if is_quota_signal "$reason"; then
    return 0
  fi
  case "$(printf '%s' "$reason" | tr '[:upper:]' '[:lower:]')" in
    *timeout*|*no_output*|*missing_token*|*model_policy_violation*|*quota*|*rate_limit*) return 0 ;;
  esac
  return 1
}

mark_agent_unhealthy_for_failover() {
  local agent_bin="$1"
  local failure_reason="$2"
  local normalized
  normalized="$(printf '%s' "$failure_reason" | tr '[:upper:]' '[:lower:]')"
  if [[ "$normalized" == *quota* || "$normalized" == *rate_limit* ]]; then
    quota_tracker_record_hit "$agent_bin" || true
    health_cache_set "$agent_bin" "quota" || true
    health_memo_set "$agent_bin" "quota" || true
  else
    health_cache_set "$agent_bin" "fail" || true
    health_memo_set "$agent_bin" "fail" || true
  fi
}

role_supports_agent_failover() {
  local role="$1"
  local command_string="" command_bin="" command_name=""

  case "$role" in
    implementor|reviewer)
      command_string="${REVIEWER_CMD:-./reviewer.sh}"
      ;;
    auditor)
      command_string="${AUDITOR_CMD:-./auditor.sh}"
      ;;
    *)
      return 1
      ;;
  esac

  command_bin="${command_string%% *}"
  command_name="$(basename "$command_bin")"
  case "$command_name" in
    reviewer.sh|auditor.sh) return 0 ;;
    *) return 1 ;;
  esac
}

attempt_agent_failover() {
  local role="$1"
  local failure_reason="$2"
  local failed_bin previous_impl previous_auditor
  local reselection_reason

  previous_impl="$active_impl"
  previous_auditor="$active_auditor"
  reselection_reason="${role}:${failure_reason}"

  case "$role" in
    implementor|reviewer) failed_bin="${active_impl%%:*}" ;;
    auditor) failed_bin="${active_auditor%%:*}" ;;
    *) failed_bin="" ;;
  esac

  if [[ -n "$failed_bin" && "$failed_bin" != "NONE" ]]; then
    mark_agent_unhealthy_for_failover "$failed_bin" "$failure_reason"
  fi

  select_agents_with_mode "live" || return 1
  if [[ "$active_impl" == "NONE" || "$active_auditor" == "NONE" ]]; then
    return 1
  fi
  AGENT_HEALTH_CACHE_ENABLED=0 validate_selected_agent_health "implementor" "$active_impl" || return 1
  AGENT_HEALTH_CACHE_ENABLED=0 validate_selected_agent_health "reviewer" "$active_reviewer" || return 1
  AGENT_HEALTH_CACHE_ENABLED=0 validate_selected_agent_health "auditor" "$active_auditor" || return 1

  export LOOP_ACTIVE_IMPLEMENTOR="${active_impl}"
  export LOOP_ACTIVE_REVIEWER="${active_reviewer}"
  export LOOP_ACTIVE_AUDITOR="${active_auditor}"

  if [[ "$role" == "auditor" ]]; then
    [[ "$active_auditor" != "$previous_auditor" ]]
    return
  fi
  [[ "$active_impl" != "$previous_impl" ]]
}

select_agents_with_mode() {
  local mode="$1"
  local prior_cache_flag="${AGENT_HEALTH_CACHE_ENABLED:-1}"
  local impl_bin
  local selected_auditor_entry=""
  local selected_entry=""
  local entry entry_bin

  if is_truthy_value "$SKIP_AGENT_HEALTH_CHECKS"; then
    if [[ -n "$IMPLEMENTOR_OVERRIDE" ]]; then
      active_impl="$(resolve_agent_override_or_fail "implementor" "$IMPLEMENTOR_OVERRIDE")" || return 1
    else
      selected_entry="${IMPLEMENTOR_PRIORITY[0]:-}"
      if [[ -z "$selected_entry" ]]; then
        active_impl="NONE"
      else
        active_impl="$(entry_to_resolved "$selected_entry")"
      fi
    fi

    active_reviewer="${active_impl}"
    impl_bin="${active_impl%%:*}"

    if [[ -n "$AUDITOR_OVERRIDE" ]]; then
      active_auditor="$(resolve_agent_override_or_fail "auditor" "$AUDITOR_OVERRIDE")" || return 1
    else
      for entry in "${AUDITOR_PRIORITY[@]}"; do
        entry_bin="${entry%%:*}"
        if [[ "$entry_bin" != "$impl_bin" ]]; then
          selected_auditor_entry="$entry"
          break
        fi
      done
      if [[ -z "$selected_auditor_entry" ]]; then
        selected_auditor_entry="${AUDITOR_PRIORITY[0]:-}"
      fi
      if [[ -z "$selected_auditor_entry" ]]; then
        active_auditor="NONE"
      else
        active_auditor="$(entry_to_resolved "$selected_auditor_entry")"
      fi
    fi
    return 0
  fi

  if [[ "$mode" == "live" ]]; then
    export AGENT_HEALTH_CACHE_ENABLED=0
  fi

  if [[ -n "$IMPLEMENTOR_OVERRIDE" ]]; then
    active_impl="$(resolve_agent_override_or_fail "implementor" "$IMPLEMENTOR_OVERRIDE")" || return 1
  else
    active_impl="$(get_active_implementor || echo "NONE")"
  fi

  active_reviewer="${active_impl}"

  if [[ -n "$AUDITOR_OVERRIDE" ]]; then
    active_auditor="$(resolve_agent_override_or_fail "auditor" "$AUDITOR_OVERRIDE")" || return 1
  else
    active_auditor="$(get_active_auditor "${active_impl%%:*}" || echo "NONE")"
  fi

  if [[ "$mode" == "live" ]]; then
    export AGENT_HEALTH_CACHE_ENABLED="${prior_cache_flag}"
  fi
  return 0
}

if [[ "$LIST_AGENTS_ONLY" -eq 1 ]]; then
  print_configured_agents
  exit 0
fi

if declare -F dispatcher_health_memo_reset >/dev/null 2>&1; then
  dispatcher_health_memo_reset
fi

mkdir -p "$STATE_ROOT"
mkdir -p "$(dirname "$STOP_REQUEST_FILE")"
mkdir -p "$(dirname "$PID_FILE")"
mkdir -p "$(dirname "$LOCK_DIR")"
mkdir -p "$FINDINGS_ROOT"

cleanup_loop_lock() {
  loop_state_release_lock_dir_if_owner "$LOCK_DIR" "$$"
}

acquire_loop_lock() {
  local lock_owner_pid=""
  if is_truthy_value "$ALLOW_PARALLEL_LOOPS"; then
    return 0
  fi

  if loop_state_try_acquire_lock_dir "$LOCK_DIR" "$$"; then
    return 0
  fi

  lock_owner_pid="$(loop_state_lock_owner_pid "$LOCK_DIR")"
  if [[ -n "$lock_owner_pid" ]] && loop_state_pid_is_live "$lock_owner_pid"; then
    echo "Another loop lock is active (pid=${lock_owner_pid}, lock=${LOCK_DIR})." >&2
    echo "Use make stop-loop-graceful first, or pass --allow-parallel-loops intentionally." >&2
    return 1
  fi

  echo "Unable to acquire loop lock at ${LOCK_DIR}." >&2
  return 1
}

if ! acquire_loop_lock; then
  exit "${EXIT_LOCK_CONFLICT:-6}"
fi

ignored_scan_pids=""
ignored_scan_pgids=""
include_process_scan="0"
if is_truthy_value "$ACTIVE_LOOP_SCAN_ENABLED"; then
  ignored_scan_pids="$(loop_scan_collect_ignored_pids)"
  ignored_scan_pgids="$(loop_scan_collect_ignored_process_groups)"
  include_process_scan="1"
fi

active_loop_pids=()
while IFS= read -r active_pid; do
  [[ -z "$active_pid" ]] && continue
  active_loop_pids+=("$active_pid")
done < <(loop_scan_collect_active_loop_pids "$PID_FILE" "$ignored_scan_pids" "$include_process_scan" "$ignored_scan_pgids")

if (( ${#active_loop_pids[@]} > 0 )) && ! is_truthy_value "$ALLOW_PARALLEL_LOOPS"; then
  echo "Detected active run_all_tasks loop pid(s): ${active_loop_pids[*]}" >&2
  echo "Use make stop-loop-graceful (or kill the listed PID) before starting a new loop." >&2
  echo "Override only when intentional: --allow-parallel-loops" >&2
  exit "${EXIT_LOCK_CONFLICT:-6}"
fi

loop_state_write_pid_file "$PID_FILE" "$$"

if [[ -z "${LOOP_SESSION_ID:-}" ]]; then
  LOOP_SESSION_ID="$(date -u +"%Y%m%dT%H%M%SZ")-$$"
fi
export LOOP_SESSION_ID

panel_out "=== Expert Panel Selection ==="
panel_out "Loop framework version: ${LOOP_FRAMEWORK_VERSION}"
selection_retry_reason=""
select_agents_with_mode "cached" || exit 1

if [[ "$active_impl" == "NONE" || "$active_auditor" == "NONE" ]]; then
  selection_retry_reason="agent_availability"
fi

if [[ -z "$selection_retry_reason" ]]; then
  if ! validate_selected_agent_health "implementor" "$active_impl"; then
    selection_retry_reason="implementor_validation"
  elif ! validate_selected_agent_health "reviewer" "$active_reviewer"; then
    selection_retry_reason="reviewer_validation"
  elif ! validate_selected_agent_health "auditor" "$active_auditor"; then
    selection_retry_reason="auditor_validation"
  fi
fi

if [[ -n "$selection_retry_reason" ]] && ! is_truthy_value "$SKIP_AGENT_HEALTH_CHECKS"; then
  echo "Auto-retrying agent selection with live health checks (reason=${selection_retry_reason})." >&2
  if declare -F dispatcher_health_memo_reset >/dev/null 2>&1; then
    dispatcher_health_memo_reset
  fi
  select_agents_with_mode "live" || exit 1
  if [[ "$active_impl" == "NONE" ]]; then
    echo "ERROR: No available implementor found after live retry." >&2
    print_configured_agents >&2
    exit 1
  fi
  if [[ "$active_auditor" == "NONE" ]]; then
    echo "ERROR: No available auditor found after live retry." >&2
    print_configured_agents >&2
    exit 1
  fi
  AGENT_HEALTH_CACHE_ENABLED=0 validate_selected_agent_health "implementor" "$active_impl" || exit 1
  AGENT_HEALTH_CACHE_ENABLED=0 validate_selected_agent_health "reviewer" "$active_reviewer" || exit 1
  AGENT_HEALTH_CACHE_ENABLED=0 validate_selected_agent_health "auditor" "$active_auditor" || exit 1
fi

if [[ "$active_impl" == "NONE" ]]; then
  echo "ERROR: No available implementor found." >&2
  print_configured_agents >&2
  exit 1
fi
if [[ "$active_auditor" == "NONE" ]]; then
  echo "ERROR: No available auditor found." >&2
  print_configured_agents >&2
  exit 1
fi
if [[ "${active_auditor%%:*}" == "${active_impl%%:*}" ]]; then
  echo "ERROR: Auditor must be a third-party agent and cannot match implementor (${active_impl%%:*})." >&2
  print_configured_agents >&2
  exit 1
fi

can_prompt_agents="0"
if [[ -r /dev/tty && -w /dev/tty ]]; then
  can_prompt_agents="1"
elif [[ -t 0 && -t 1 ]]; then
  can_prompt_agents="1"
fi

should_confirm_agents="0"
if [[ "$AGENT_SELECTION_CONFIRM" == "always" ]] || { [[ "$AGENT_SELECTION_CONFIRM" == "auto" ]] && [[ "$can_prompt_agents" == "1" ]]; }; then
  should_confirm_agents="1"
fi

PANEL_OUTPUT_STREAM=""
if [[ "$should_confirm_agents" == "1" && -r /dev/tty && -w /dev/tty ]]; then
  PANEL_OUTPUT_STREAM="/dev/tty"
fi

panel_out "Implementor: ${active_impl}"
panel_out "Reviewer:    ${active_reviewer}"
panel_out "Auditor:     ${active_auditor}"
panel_out "=============================="

if [[ "$should_confirm_agents" == "1" ]]; then
  if [[ -r /dev/tty && -w /dev/tty ]]; then
    panel_prompt "Proceed with these agents? [Y/n] "
    read -r confirm_agents </dev/tty
  else
    panel_prompt "Proceed with these agents? [Y/n] "
    read -r confirm_agents
  fi
  panel_out ""
  case "${confirm_agents:-Y}" in
    [Yy]|[Yy][Ee][Ss]|"") ;;
    *)
      echo "Agent selection aborted by user." >&2
      print_configured_agents >&2
      echo "Rerun with overrides, e.g. --implementor 2 --auditor 1" >&2
      exit "${EXIT_MISSING_TOKEN:-3}"
      ;;
  esac
fi

if is_truthy_value "$DRY_RUN"; then
  next_task_id="$(awk '/^- \[ \] TASK-[0-9]+:/ {line=$0; sub(/^- \[ \] /, "", line); sub(/:.*/, "", line); print line; exit}' "$TASKS_FILE")"
  next_task_title="$(awk '/^- \[ \] TASK-[0-9]+:/ {line=$0; sub(/^- \[ \] TASK-[0-9]+:[[:space:]]*/, "", line); print line; exit}' "$TASKS_FILE")"
  open_tasks_count="$(awk '/^- \[ \] TASK-[0-9]+:/ {c++} END {print c+0}' "$TASKS_FILE")"
  echo "Dry run summary:"
  echo "- Open tasks: ${open_tasks_count}"
  echo "- Next task: ${next_task_id:-none} ${next_task_title:+- ${next_task_title}}"
  echo "- Implementor/Reviewer: ${active_impl}"
  echo "- Auditor: ${active_auditor}"
  echo "- Health checks skipped: ${SKIP_AGENT_HEALTH_CHECKS}"
  echo "- Confirmation mode: ${AGENT_SELECTION_CONFIRM}"
  exit 0
fi

# Cache selected agents for child wrappers to avoid repeated health probes.
export LOOP_ACTIVE_IMPLEMENTOR="${active_impl}"
export LOOP_ACTIVE_REVIEWER="${active_reviewer}"
export LOOP_ACTIVE_AUDITOR="${active_auditor}"

cleanup_pid_file() {
  loop_state_remove_pid_file_if_owner "$PID_FILE" "$$"
}

cleanup_loop_children() {
  # Best-effort cleanup for leaked descendants (review/audit/task wrappers, exec sessions).
  # This prevents "done but still spawning child sessions" after loop exit.
  local sig child_pids
  for sig in TERM KILL; do
    child_pids="$(ps -ax -o pid=,ppid= 2>/dev/null | awk -v p="$$" '$2==p {print $1}')"
    if [[ -z "${child_pids//[[:space:]]/}" ]]; then
      return 0
    fi
    # shellcheck disable=SC2086
    kill -"${sig}" ${child_pids} >/dev/null 2>&1 || true
    sleep 0.2
  done
}

loop_started_epoch="$(date +%s)"
loop_started_ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
loop_stop_reason="unknown"
last_open_tasks="-1"

cleanup_on_exit() {
  local exit_code="$1"
  local loop_finished_epoch loop_finished_ts loop_duration_s
  loop_finished_epoch="$(date +%s)"
  loop_finished_ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  loop_duration_s=$((loop_finished_epoch - loop_started_epoch))

  mkdir -p "$STATE_ROOT" 2>/dev/null || true
  printf '%s\n' "$loop_stop_reason" > "$LOOP_STOP_REASON_FILE" 2>/dev/null || true
  write_loop_checkpoint "loop_exit_${loop_stop_reason}" || true

  cleanup_pid_file
  cleanup_loop_lock
  if [[ "$have_metrics" == "1" ]]; then
    metrics_append_jsonl "$LOOP_SESSIONS_LOG" \
      "event_type=loop_session_end" \
      "ts_utc=${loop_finished_ts}" \
      "loop_session_id=${LOOP_SESSION_ID}" \
      "started_at_utc=${loop_started_ts}" \
      "finished_at_utc=${loop_finished_ts}" \
      "duration_s=${loop_duration_s}" \
      "stop_reason=${loop_stop_reason}" \
      "final_exit_code=${exit_code}" \
      "open_tasks_remaining=${last_open_tasks}" \
      "iterations_attempted=${iteration:-0}" || true
  fi

  local tasks_done tasks_open
  tasks_done="$(awk '/^- \[[xX]\] TASK-[0-9]+:/ {c++} END {print c+0}' "$TASKS_FILE" 2>/dev/null || echo "0")"
  tasks_open="$(awk '/^- \[ \] TASK-[0-9]+:/ {c++} END {print c+0}' "$TASKS_FILE" 2>/dev/null || echo "0")"
  echo "=== Loop Exit Summary ==="
  echo "Session: ${LOOP_SESSION_ID}"
  echo "Result: ${loop_stop_reason} (exit=${exit_code})"
  echo "Iterations: ${iteration:-0}"
  echo "Tasks completed: ${tasks_done}"
  echo "Tasks remaining: ${tasks_open}"
  echo "Duration: ${loop_duration_s}s"
  echo "Last completed task: ${last_completed_task_id:-none}"
  echo "Stop reason file: ${LOOP_STOP_REASON_FILE}"
  echo "Checkpoint file: ${LOOP_CHECKPOINT_FILE}"
  echo "Loop framework version: ${LOOP_FRAMEWORK_VERSION}"
  echo "========================="

  if [[ -n "$LOOP_ALERT_CMD" && "$loop_stop_reason" != "all_tasks_complete" ]]; then
    LOOP_ALERT_REASON="$loop_stop_reason" LOOP_ALERT_EXIT_CODE="$exit_code" \
      bash -lc "$LOOP_ALERT_CMD" >/dev/null 2>&1 || true
  fi

  cleanup_loop_children || true
}

trap 'cleanup_on_exit "$?"' EXIT

if [[ "$have_metrics" == "1" ]]; then
  metrics_append_jsonl "$LOOP_SESSIONS_LOG" \
    "event_type=loop_session_start" \
    "ts_utc=${loop_started_ts}" \
    "loop_session_id=${LOOP_SESSION_ID}" \
    "pid=$$" \
    "started_at_utc=${loop_started_ts}" \
    "max_tasks=${MAX_TASKS}" \
    "allow_parallel_loops=${ALLOW_PARALLEL_LOOPS}" \
    "active_loop_scan_enabled=${ACTIVE_LOOP_SCAN_ENABLED}" \
    "review_enabled=${REVIEW_ENABLED}" \
    "phase_review_enabled=${PHASE_REVIEW_ENABLED}" \
    "review_every_tasks=${REVIEW_EVERY_TASKS}" \
    "audit_enabled=${AUDIT_ENABLED}" \
    "audit_cmd=${AUDIT_CMD}" \
    "arch_review_enabled=${ARCH_REVIEW_ENABLED}" \
    "arch_review_cmd=${ARCH_REVIEW_CMD}" \
    "arch_review_prompt_file=${ARCH_REVIEW_PROMPT_FILE}" \
    "arch_review_max_retries=${ARCH_REVIEW_MAX_RETRIES}" \
    "findings_process_cmd=${FINDINGS_PROCESS_CMD}" \
    "findings_blocker_severity=${FINDINGS_BLOCKER_SEVERITY}" \
    "final_gate_max_retries=${FINAL_GATE_MAX_RETRIES}" \
    "quota_wait_enabled=${QUOTA_WAIT_ENABLED}" \
    "quota_wait_max_seconds=${QUOTA_WAIT_MAX_SECONDS}" \
    "quota_wait_poll_seconds=${QUOTA_WAIT_POLL_SECONDS}" \
    "watchdog_enabled=${WATCHDOG_ENABLED}" \
    "watchdog_max_task_seconds=${WATCHDOG_MAX_TASK_SECONDS}" \
    "watchdog_warn_limit=${WATCHDOG_WARN_LIMIT}" \
    "watchdog_hard_stop=${WATCHDOG_HARD_STOP}" \
    "self_heal_enabled=${SELF_HEAL_ENABLED}" \
    "self_heal_max_retries_per_task=${SELF_HEAL_MAX_RETRIES_PER_TASK}" \
    "self_heal_retry_delay_seconds=${SELF_HEAL_RETRY_DELAY_SECONDS}" \
    "log_prune_enabled=${LOG_PRUNE_ENABLED}" \
    "log_prune_days=${LOG_PRUNE_DAYS}" \
    "log_prune_max_mb=${LOG_PRUNE_MAX_MB}" \
    "log_prune_min_keep=${LOG_PRUNE_MIN_KEEP}" \
    "log_prune_every_tasks=${LOG_PRUNE_EVERY_TASKS}" \
    "lock_dir=${LOCK_DIR}" \
    "stop_file=${STOP_REQUEST_FILE}" \
    "pid_file=${PID_FILE}" || true
fi

count_open_tasks() {
  awk '/^- \[ \] TASK-[0-9]+:/ {c++} END {print c+0}' "$TASKS_FILE"
}

first_open_task_id() {
  awk '/^- \[ \] TASK-[0-9]+:/ {line=$0; sub(/^- \[ \] /, "", line); sub(/:.*/, "", line); print line; exit}' "$TASKS_FILE"
}

first_open_phase() {
  awk '/^### / {section=substr($0,5)} /^- \[ \] TASK-[0-9]+:/ {print section; exit}' "$TASKS_FILE"
}

is_truthy() {
  local value="${1:-}"
  case "$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')" in
    1|true|yes|on) return 0 ;;
    *) return 1 ;;
  esac
}

is_positive_integer() {
  local value="${1:-}"
  case "$value" in
    ""|*[!0-9]*) return 1 ;;
    *) [ "$value" -gt 0 ] ;;
  esac
}

shell_errexit_was_set() {
  [[ "$-" == *e* ]]
}

restore_shell_errexit() {
  local was_set="${1:-0}"
  if [[ "$was_set" == "1" ]]; then
    set -e
  else
    set +e
  fi
}

latest_task_detail_fields_tsv() {
  local task_id="$1"
  if [[ "$have_metrics" != "1" || ! -f "${TASK_RUNS_LOG:-}" ]]; then
    printf '\t\t\n'
    return 0
  fi
  "$PYTHON_BIN" - "$TASK_RUNS_LOG" "$task_id" "${LOOP_SESSION_ID:-}" <<'PY'
import json
import sys
from pathlib import Path

log_path = Path(sys.argv[1])
task_id = sys.argv[2]
loop_session_id = sys.argv[3]
latest = None

with log_path.open(encoding="utf-8", errors="ignore") as handle:
    for raw in handle:
        raw = raw.strip()
        if not raw:
            continue
        try:
            row = json.loads(raw)
        except json.JSONDecodeError:
            continue
        if row.get("event_type") != "task_detail":
            continue
        if row.get("task_id") != task_id:
            continue
        if loop_session_id and row.get("loop_session_id") != loop_session_id:
            continue
        latest = row

if latest is None:
    print("\t\t")
else:
    reason = str(latest.get("failure_reason", "") or "")
    failure_files = str(latest.get("required_test_touch_failure_files", "") or "")
    exit_code = str(latest.get("exit_code", "") or "")
    print(f"{reason}\t{failure_files}\t{exit_code}")
PY
}

run_log_prune() {
  local trigger="$1"
  local errexit_was_set=0
  if ! is_truthy "$LOG_PRUNE_ENABLED"; then
    return 0
  fi
  if [[ ! -x "./scripts/prune_loop_logs.sh" ]]; then
    return 0
  fi

  local prune_output prune_ec
  if shell_errexit_was_set; then
    errexit_was_set=1
  fi
  set +e
  prune_output="$(
    ./scripts/prune_loop_logs.sh \
      --root "$LOG_ROOT" \
      --days "$LOG_PRUNE_DAYS" \
      --max-mb "$LOG_PRUNE_MAX_MB" \
      --min-keep "$LOG_PRUNE_MIN_KEEP" \
      --quiet 2>&1
  )"
  prune_ec=$?
  restore_shell_errexit "$errexit_was_set"

  if [[ -n "$prune_output" ]]; then
    printf '%s\n' "$prune_output"
  fi

  if [[ "$have_metrics" == "1" ]]; then
    metrics_append_jsonl "$LOOP_SESSIONS_LOG" \
      "event_type=loop_log_prune" \
      "ts_utc=$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
      "loop_session_id=${LOOP_SESSION_ID}" \
      "trigger=${trigger}" \
      "exit_code=${prune_ec}" \
      "log_root=${LOG_ROOT}" \
      "retention_days=${LOG_PRUNE_DAYS}" \
      "max_mb=${LOG_PRUNE_MAX_MB}" \
      "min_keep=${LOG_PRUNE_MIN_KEEP}" || true
  fi
}

run_log_prune "loop_start" || true

quota_first_detected_epoch=""
latest_review_findings_file=""
latest_audit_findings_file=""
latest_review_log_file=""
latest_review_result_value=""
latest_audit_result_value=""

is_quota_signal() {
  local value="${1:-}"
  case "$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')" in
    *quota*|*rate*limit*|*token*budget*|*usage*cap*|*too*many*requests*) return 0 ;;
    *) return 1 ;;
  esac
}

handle_quota_wait() {
  local context="$1"
  if ! is_truthy "$QUOTA_WAIT_ENABLED"; then
    return 1
  fi
  if ! is_positive_integer "$QUOTA_WAIT_MAX_SECONDS"; then
    return 1
  fi
  if ! is_positive_integer "$QUOTA_WAIT_POLL_SECONDS"; then
    QUOTA_WAIT_POLL_SECONDS="300"
  fi

  local now_epoch elapsed_s
  now_epoch="$(date +%s)"
  if [[ -z "$quota_first_detected_epoch" ]]; then
    quota_first_detected_epoch="$now_epoch"
  fi
  elapsed_s=$((now_epoch - quota_first_detected_epoch))
  if (( elapsed_s >= QUOTA_WAIT_MAX_SECONDS )); then
    echo "[quota] ${context}: still quota-limited after ${elapsed_s}s (max=${QUOTA_WAIT_MAX_SECONDS}s)." >&2
    return 1
  fi

  echo "[quota] ${context}: quota/rate limit detected; sleeping ${QUOTA_WAIT_POLL_SECONDS}s before retry."
  if [[ "$have_metrics" == "1" ]]; then
    metrics_append_jsonl "$LOOP_SESSIONS_LOG" \
      "event_type=quota_wait" \
      "ts_utc=$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
      "loop_session_id=${LOOP_SESSION_ID}" \
      "context=${context}" \
      "elapsed_s=${elapsed_s}" \
      "wait_s=${QUOTA_WAIT_POLL_SECONDS}" \
      "max_wait_s=${QUOTA_WAIT_MAX_SECONDS}" || true
  fi
  sleep "$QUOTA_WAIT_POLL_SECONDS"
  return 0
}

reset_quota_wait() {
  quota_first_detected_epoch=""
}

exit_agent_failover_exhausted() {
  local message="$1"
  echo "$message" >&2
  loop_stop_reason="agent_failover_exhausted"
  exit "${EXIT_REVIEW_SELF_HEAL_EXHAUSTED:-4}"
}

maybe_handle_runtime_failover() {
  local role="$1"
  local exit_code="$2"
  local failure_reason="$3"
  local exhausted_context="$4"
  local checkpoint_reason="$5"
  local success_message="$6"
  local no_alternate_message="$7"

  if ! is_agent_runtime_failure "$exit_code" "$failure_reason"; then
    return 1
  fi
  if ! role_supports_agent_failover "$role"; then
    return 1
  fi
  if is_positive_integer "$AGENT_FAILOVER_MAX_ATTEMPTS" && (( agent_failover_attempts >= AGENT_FAILOVER_MAX_ATTEMPTS )); then
    exit_agent_failover_exhausted "Agent failover exhausted (${agent_failover_attempts}/${AGENT_FAILOVER_MAX_ATTEMPTS}) ${exhausted_context}."
  fi
  if attempt_agent_failover "$role" "$failure_reason"; then
    agent_failover_attempts=$((agent_failover_attempts + 1))
    echo "$success_message"
    write_loop_checkpoint "$checkpoint_reason"
    return 0
  fi
  exit_agent_failover_exhausted "$no_alternate_message"
}

maybe_handle_quota_wait_or_exit() {
  local exit_code="$1"
  local failure_reason="$2"
  local quota_context="$3"
  local exhausted_stop_reason="${4:-weekly_quota_exhausted}"

  if [[ "$exit_code" -ne "${EXIT_QUOTA_EXHAUSTED:-10}" ]] && ! is_quota_signal "$failure_reason"; then
    return 1
  fi
  if handle_quota_wait "$quota_context"; then
    return 0
  fi
  loop_stop_reason="$exhausted_stop_reason"
  exit "${EXIT_QUOTA_EXHAUSTED:-10}"
}

summary_json_field() {
  local summary_file="$1"
  local key="$2"
  "$PYTHON_BIN" - "$summary_file" "$key" <<'PY'
import json
import sys
from pathlib import Path

summary_file = Path(sys.argv[1])
field = sys.argv[2]
if not summary_file.is_file():
    print("")
    raise SystemExit(0)

try:
    payload = json.loads(summary_file.read_text(encoding="utf-8"))
except json.JSONDecodeError:
    print("")
    raise SystemExit(0)

value = payload.get(field, "")
if isinstance(value, bool):
    print("true" if value else "false")
else:
    print(str(value))
PY
}

result_json_field() {
  local result_file="$1"
  local key="$2"
  "$PYTHON_BIN" - "$result_file" "$key" <<'PY'
import json
import sys
from pathlib import Path

result_path = Path(sys.argv[1])
field = sys.argv[2]
if not result_path.is_file():
    print("")
    raise SystemExit(0)
try:
    payload = json.loads(result_path.read_text(encoding="utf-8"))
except json.JSONDecodeError:
    print("")
    raise SystemExit(0)
value = payload.get(field, "")
print(str(value) if value is not None else "")
PY
}

write_loop_checkpoint() {
  local checkpoint_reason="$1"
  if ! is_truthy "$LOOP_CHECKPOINT_ENABLED"; then
    return 0
  fi
  mkdir -p "$STATE_ROOT"
  "$PYTHON_BIN" - "$LOOP_CHECKPOINT_FILE" "$LOOP_SESSION_ID" "$checkpoint_reason" \
    "${iteration:-0}" "${retry_task_id:-}" "${retry_count:-0}" "${retry_reason:-}" "${retry_failure_files:-}" \
    "${review_retry_task_id:-}" "${review_retry_mode:-}" "${review_retry_count:-0}" \
    "${final_gate_retry_count:-0}" "${arch_final_retry_count:-0}" "${last_completed_task_id:-}" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" <<'PY'
import json
import sys
from pathlib import Path

out_path = Path(sys.argv[1])
payload = {
    "loop_session_id": sys.argv[2],
    "reason": sys.argv[3],
    "iteration": int(sys.argv[4]),
    "retry_task_id": sys.argv[5],
    "retry_count": int(sys.argv[6]),
    "retry_reason": sys.argv[7],
    "retry_failure_files": sys.argv[8],
    "review_retry_task_id": sys.argv[9],
    "review_retry_mode": sys.argv[10],
    "review_retry_count": int(sys.argv[11]),
    "final_gate_retry_count": int(sys.argv[12]),
    "arch_final_retry_count": int(sys.argv[13]),
    "last_completed_task_id": sys.argv[14],
    "updated_at_utc": sys.argv[15],
}
out_path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY
}

restore_loop_checkpoint_if_enabled() {
  if ! is_truthy "$LOOP_CHECKPOINT_ENABLED"; then
    return 0
  fi
  if ! is_truthy "$LOOP_AUTO_RESUME_CHECKPOINT"; then
    return 0
  fi
  if [[ ! -f "$LOOP_CHECKPOINT_FILE" ]]; then
    return 0
  fi

  local checkpoint_session checkpoint_iteration checkpoint_retry_task checkpoint_retry_count checkpoint_retry_reason checkpoint_retry_files
  local checkpoint_review_task checkpoint_review_mode checkpoint_review_count checkpoint_final_retry checkpoint_arch_retry checkpoint_last_task
  checkpoint_session="$(result_json_field "$LOOP_CHECKPOINT_FILE" "loop_session_id")"
  checkpoint_iteration="$(result_json_field "$LOOP_CHECKPOINT_FILE" "iteration")"
  checkpoint_retry_task="$(result_json_field "$LOOP_CHECKPOINT_FILE" "retry_task_id")"
  checkpoint_retry_count="$(result_json_field "$LOOP_CHECKPOINT_FILE" "retry_count")"
  checkpoint_retry_reason="$(result_json_field "$LOOP_CHECKPOINT_FILE" "retry_reason")"
  checkpoint_retry_files="$(result_json_field "$LOOP_CHECKPOINT_FILE" "retry_failure_files")"
  checkpoint_review_task="$(result_json_field "$LOOP_CHECKPOINT_FILE" "review_retry_task_id")"
  checkpoint_review_mode="$(result_json_field "$LOOP_CHECKPOINT_FILE" "review_retry_mode")"
  checkpoint_review_count="$(result_json_field "$LOOP_CHECKPOINT_FILE" "review_retry_count")"
  checkpoint_final_retry="$(result_json_field "$LOOP_CHECKPOINT_FILE" "final_gate_retry_count")"
  checkpoint_arch_retry="$(result_json_field "$LOOP_CHECKPOINT_FILE" "arch_final_retry_count")"
  checkpoint_last_task="$(result_json_field "$LOOP_CHECKPOINT_FILE" "last_completed_task_id")"

  if [[ ! "$checkpoint_iteration" =~ ^[0-9]+$ ]]; then
    checkpoint_iteration=0
  fi
  if [[ ! "$checkpoint_retry_count" =~ ^[0-9]+$ ]]; then
    checkpoint_retry_count=0
  fi
  if [[ ! "$checkpoint_review_count" =~ ^[0-9]+$ ]]; then
    checkpoint_review_count=0
  fi
  if [[ ! "$checkpoint_final_retry" =~ ^[0-9]+$ ]]; then
    checkpoint_final_retry=0
  fi
  if [[ ! "$checkpoint_arch_retry" =~ ^[0-9]+$ ]]; then
    checkpoint_arch_retry=0
  fi

  iteration="$checkpoint_iteration"
  retry_task_id="$checkpoint_retry_task"
  retry_count="$checkpoint_retry_count"
  retry_reason="$checkpoint_retry_reason"
  retry_failure_files="$checkpoint_retry_files"
  review_retry_task_id="$checkpoint_review_task"
  review_retry_mode="$checkpoint_review_mode"
  review_retry_count="$checkpoint_review_count"
  final_gate_retry_count="$checkpoint_final_retry"
  arch_final_retry_count="$checkpoint_arch_retry"
  last_completed_task_id="$checkpoint_last_task"

  if [[ -n "$checkpoint_session" && "$checkpoint_session" != "$LOOP_SESSION_ID" ]]; then
    echo "Restored checkpoint from prior session ${checkpoint_session}; resuming counters in session ${LOOP_SESSION_ID}."
  else
    echo "Restored loop checkpoint from ${LOOP_CHECKPOINT_FILE}."
  fi
}

process_findings_file() {
  local findings_file="$1"
  local source="$2"
  local mode="$3"
  local errexit_was_set=0
  if [[ -z "$findings_file" || ! -f "$findings_file" ]]; then
    echo "[findings] no findings file for ${source}:${mode}."
    printf '0\t0\t0\n'
    return 0
  fi

  local summary_file low_flag accepted_flag
  summary_file="$(mktemp)"
  low_flag=()
  accepted_flag=()
  if is_truthy "$LOW_FINDINGS_TO_GH_ISSUES"; then
    low_flag=(--create-low-issues)
  fi
  if is_truthy "$ACCEPTED_RISK_TO_GH_ISSUES"; then
    accepted_flag=(--create-accepted-risk-issues)
  fi

  if shell_errexit_was_set; then
    errexit_was_set=1
  fi
  set +e
  "$PYTHON_BIN" "$FINDINGS_PROCESS_CMD" \
    --findings-file "$findings_file" \
    --tasks-file "$TASKS_FILE" \
    --summary-file "$summary_file" \
    --source "$source" \
    --mode "$mode" \
    --loop-session-id "${LOOP_SESSION_ID}" \
    --default-spec "$FINDINGS_DEFAULT_SPEC" \
    --default-test "$FINDINGS_DEFAULT_TEST" \
    --blocker-severity "$FINDINGS_BLOCKER_SEVERITY" \
    "${low_flag[@]}" \
    "${accepted_flag[@]}"
  local process_ec=$?
  restore_shell_errexit "$errexit_was_set"
  if [[ "$process_ec" -ne 0 ]]; then
    echo "[findings] processor failed for ${source}:${mode} (${process_ec})." >&2
    rm -f "$summary_file"
    printf '0\t0\t1\n'
    return 0
  fi

  local blocking_count new_tasks_count processing_failed
  local malformed_findings_count
  blocking_count="$(summary_json_field "$summary_file" "blocking_findings")"
  new_tasks_count="$(summary_json_field "$summary_file" "new_tasks")"
  malformed_findings_count="$(summary_json_field "$summary_file" "malformed_findings")"
  processing_failed="0"
  if [[ -n "${malformed_findings_count:-}" && "${malformed_findings_count:-0}" != "0" ]]; then
    echo "[findings] malformed findings detected for ${source}:${mode} count=${malformed_findings_count}." >&2
    if [[ "$have_metrics" == "1" ]]; then
      metrics_append_jsonl "$REVIEW_RUNS_LOG" \
        "event_type=findings_malformed" \
        "ts_utc=$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
        "loop_session_id=${LOOP_SESSION_ID}" \
        "source=${source}" \
        "mode=${mode}" \
        "malformed_findings=${malformed_findings_count}" \
        "findings_file=${findings_file}" || true
    fi
  fi
  rm -f "$summary_file"
  printf '%s\t%s\t%s\n' "${blocking_count:-0}" "${new_tasks_count:-0}" "${processing_failed}"
}

latest_findings_for_source() {
  local source="$1"
  local mode="$2"
  local pattern="${FINDINGS_ROOT}/${source}-${mode}-*.jsonl"
  ls -1t $pattern 2>/dev/null | head -n 1
}

run_review() {
  local mode="$1"
  local task_id="$2"
  local phase_name="$3"
  local review_started_epoch review_started_ts review_finished_epoch review_finished_ts review_duration_s review_ec review_result
  local errexit_was_set=0
  latest_review_findings_file=""
  latest_review_result_value=""

  echo "=== Running ${mode} review (task=${task_id:-none}, phase=${phase_name:-none}) ==="
  review_started_epoch="$(date +%s)"
  review_started_ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  local review_log_tmp
  review_log_tmp="$(mktemp)"
  if shell_errexit_was_set; then
    errexit_was_set=1
  fi
  set +e
  "$REVIEW_CMD" --mode "$mode" --task "$task_id" --phase "$phase_name" 2>&1 | tee "$review_log_tmp"
  review_ec=$?
  restore_shell_errexit "$errexit_was_set"

  latest_review_result_value="$(result_json_field "$REVIEW_RESULT_FILE" "result")"
  latest_review_findings_file="$(result_json_field "$REVIEW_RESULT_FILE" "findings_file")"
  latest_review_log_file="$(result_json_field "$REVIEW_RESULT_FILE" "log_file")"
  if [[ -z "$latest_review_findings_file" ]]; then
    latest_review_findings_file="$(grep '^REVIEW_FINDINGS_FILE=' "$review_log_tmp" | tail -n 1 | cut -d= -f2)"
  fi
  if [[ -z "$latest_review_log_file" ]]; then
    latest_review_log_file="$(grep '^Log file:' "$review_log_tmp" | tail -n 1 | sed -E 's/^Log file:[[:space:]]*//')"
  fi
  rm -f "$review_log_tmp"
  if [[ -z "$latest_review_findings_file" ]]; then
    latest_review_findings_file="$(latest_findings_for_source "reviewer" "$mode" || true)"
  fi

  review_finished_epoch="$(date +%s)"
  review_finished_ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  review_duration_s=$((review_finished_epoch - review_started_epoch))
  review_result="${latest_review_result_value}"
  if [[ -z "$review_result" ]]; then
    review_result="failed"
    if [[ "$review_ec" -eq 0 ]]; then
      review_result="passed"
    elif [[ "$review_ec" -eq "${EXIT_QUOTA_EXHAUSTED:-10}" ]]; then
      review_result="quota_exhausted"
    fi
  fi
  latest_review_result_value="$review_result"

  if [[ "$have_metrics" == "1" ]]; then
    metrics_append_jsonl "$REVIEW_RUNS_LOG" \
      "event_type=loop_review_checkpoint" \
      "ts_utc=${review_finished_ts}" \
      "loop_session_id=${LOOP_SESSION_ID}" \
      "mode=${mode}" \
      "task_id=${task_id}" \
      "phase=${phase_name}" \
      "started_at_utc=${review_started_ts}" \
      "finished_at_utc=${review_finished_ts}" \
      "duration_s=${review_duration_s}" \
      "result=${review_result}" \
      "exit_code=${review_ec}" || true
  fi

  return "$review_ec"
}

run_architecture_review() {
  local arch_started_epoch arch_started_ts arch_finished_epoch arch_finished_ts arch_duration_s arch_ec arch_result
  local errexit_was_set=0
  latest_review_findings_file=""
  latest_review_log_file=""
  latest_review_result_value=""

  echo "=== Running architecture review (final checkpoint) ==="
  arch_started_epoch="$(date +%s)"
  arch_started_ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  local arch_log_tmp
  arch_log_tmp="$(mktemp)"
  if shell_errexit_was_set; then
    errexit_was_set=1
  fi
  set +e
  "$ARCH_REVIEW_CMD" --mode "architecture" --task "" --phase "final" --prompt "$ARCH_REVIEW_PROMPT_FILE" 2>&1 | tee "$arch_log_tmp"
  arch_ec=$?
  restore_shell_errexit "$errexit_was_set"

  latest_review_result_value="$(result_json_field "$REVIEW_RESULT_FILE" "result")"
  latest_review_findings_file="$(result_json_field "$REVIEW_RESULT_FILE" "findings_file")"
  latest_review_log_file="$(result_json_field "$REVIEW_RESULT_FILE" "log_file")"
  if [[ -z "$latest_review_findings_file" ]]; then
    latest_review_findings_file="$(grep '^REVIEW_FINDINGS_FILE=' "$arch_log_tmp" | tail -n 1 | cut -d= -f2)"
  fi
  if [[ -z "$latest_review_log_file" ]]; then
    latest_review_log_file="$(grep '^Log file:' "$arch_log_tmp" | tail -n 1 | sed -E 's/^Log file:[[:space:]]*//')"
  fi
  rm -f "$arch_log_tmp"
  if [[ -z "$latest_review_findings_file" ]]; then
    latest_review_findings_file="$(latest_findings_for_source "reviewer" "architecture" || true)"
  fi

  arch_finished_epoch="$(date +%s)"
  arch_finished_ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  arch_duration_s=$((arch_finished_epoch - arch_started_epoch))
  arch_result="${latest_review_result_value}"
  if [[ -z "$arch_result" ]]; then
    arch_result="failed"
    if [[ "$arch_ec" -eq 0 ]]; then
      arch_result="passed"
    elif [[ "$arch_ec" -eq "${EXIT_QUOTA_EXHAUSTED:-10}" ]]; then
      arch_result="quota_exhausted"
    fi
  fi
  latest_review_result_value="$arch_result"

  if [[ "$have_metrics" == "1" ]]; then
    metrics_append_jsonl "$REVIEW_RUNS_LOG" \
      "event_type=loop_architecture_review_checkpoint" \
      "ts_utc=${arch_finished_ts}" \
      "loop_session_id=${LOOP_SESSION_ID}" \
      "mode=architecture" \
      "task_id=" \
      "phase=final" \
      "started_at_utc=${arch_started_ts}" \
      "finished_at_utc=${arch_finished_ts}" \
      "duration_s=${arch_duration_s}" \
      "result=${arch_result}" \
      "exit_code=${arch_ec}" \
      "findings_file=${latest_review_findings_file}" \
      "log_file=${latest_review_log_file}" || true
  fi

  return "$arch_ec"
}

mark_task_open_for_review_remediation() {
  local task_id="$1"
  local tasks_file="$2"
  "$PYTHON_BIN" - "$tasks_file" "$task_id" <<'PY'
import re
import sys
from pathlib import Path

tasks_path = Path(sys.argv[1])
task_id = sys.argv[2]
pattern = re.compile(rf"^- \[([xX ])\] ({re.escape(task_id)}):")
lines = tasks_path.read_text(encoding="utf-8").splitlines()
updated = False

for i, line in enumerate(lines):
    m = pattern.match(line)
    if not m:
        continue
    if m.group(1) in ("x", "X"):
        lines[i] = line.replace(f"- [{m.group(1)}] {task_id}:", f"- [ ] {task_id}:", 1)
    updated = True
    break

if not updated:
    print("TASK_NOT_FOUND_OR_NOT_DONE")
    raise SystemExit(2)

tasks_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
print("OK")
PY
}

schedule_review_remediation_retry() {
  local mode="$1"
  local task_id="$2"
  local phase_name="$3"
  local review_ec="$4"
  local findings_file="$5"
  local review_log_file="$6"
  local -n retry_counter_ref="$7"

  if ! is_truthy "$REVIEW_SELF_HEAL_ENABLED"; then
    return 1
  fi
  if ! is_positive_integer "$REVIEW_SELF_HEAL_MAX_RETRIES"; then
    return 1
  fi
  if (( retry_counter_ref >= REVIEW_SELF_HEAL_MAX_RETRIES )); then
    return 1
  fi

  if ! mark_task_open_for_review_remediation "$task_id" "$TASKS_FILE" >/dev/null; then
    return 1
  fi

  retry_counter_ref=$((retry_counter_ref + 1))
  retry_task_id="$task_id"
  retry_count="$retry_counter_ref"
  retry_reason="review_${mode}_failed_ec_${review_ec}"
  retry_failure_files="${findings_file:-${review_log_file:-none}}"

  echo "[review-self-heal] ${mode} review failed for ${task_id}; scheduling remediation retry ${retry_counter_ref}/${REVIEW_SELF_HEAL_MAX_RETRIES}."
  if [[ -n "$review_log_file" ]]; then
    echo "[review-self-heal] review log: ${review_log_file}"
  fi
  if [[ -n "$findings_file" ]]; then
    echo "[review-self-heal] findings file: ${findings_file}"
  fi
  if [[ "$have_metrics" == "1" ]]; then
    metrics_append_jsonl "$TASK_RUNS_LOG" \
      "event_type=review_self_heal_retry_scheduled" \
      "ts_utc=$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
      "loop_session_id=${LOOP_SESSION_ID}" \
      "task_id=${task_id}" \
      "phase=${phase_name}" \
      "mode=${mode}" \
      "review_exit_code=${review_ec}" \
      "retry_count=${retry_counter_ref}" \
      "retry_limit=${REVIEW_SELF_HEAL_MAX_RETRIES}" \
      "review_log_file=${review_log_file}" \
      "findings_file=${findings_file}" || true
  fi
  if is_positive_integer "$REVIEW_SELF_HEAL_RETRY_DELAY_SECONDS"; then
    sleep "$REVIEW_SELF_HEAL_RETRY_DELAY_SECONDS"
  fi
  return 0
}

run_audit() {
  local mode="$1"
  local task_id="$2"
  local phase_name="$3"
  local audit_started_epoch audit_started_ts audit_finished_epoch audit_finished_ts audit_duration_s audit_ec audit_result
  local audit_log_path extracted_fallback
  local errexit_was_set=0
  latest_audit_findings_file=""
  latest_audit_result_value=""

  echo "=== Running ${mode} audit (task=${task_id:-none}, phase=${phase_name:-none}) ==="
  audit_started_epoch="$(date +%s)"
  audit_started_ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  local audit_log_tmp
  audit_log_tmp="$(mktemp)"
  if shell_errexit_was_set; then
    errexit_was_set=1
  fi
  set +e
  "$AUDIT_CMD" --mode "$mode" --task "$task_id" --phase "$phase_name" 2>&1 | tee "$audit_log_tmp"
  audit_ec=$?
  restore_shell_errexit "$errexit_was_set"

  latest_audit_result_value="$(result_json_field "$AUDIT_RESULT_FILE" "result")"
  latest_audit_findings_file="$(result_json_field "$AUDIT_RESULT_FILE" "findings_file")"
  audit_log_path="$(result_json_field "$AUDIT_RESULT_FILE" "log_file")"
  if [[ -z "$latest_audit_findings_file" ]]; then
    latest_audit_findings_file="$(grep '^AUDIT_FINDINGS_FILE=' "$audit_log_tmp" | tail -n 1 | cut -d= -f2)"
  fi
  if [[ -z "$audit_log_path" ]]; then
    audit_log_path="$(grep '^Log file:' "$audit_log_tmp" | tail -n 1 | sed 's/^Log file:[[:space:]]*//')"
  fi
  rm -f "$audit_log_tmp"
  if [[ -z "$latest_audit_findings_file" && -n "$audit_log_path" && -f "$audit_log_path" && -x "./scripts/extract_findings.py" ]]; then
    mkdir -p "$FINDINGS_ROOT" 2>/dev/null || true
    extracted_fallback="${FINDINGS_ROOT}/auditor-${mode}-fallback-$(date +"%Y%m%d-%H%M%S").jsonl"
    python3 ./scripts/extract_findings.py \
      --log-file "$audit_log_path" \
      --output "$extracted_fallback" \
      --source auditor \
      --mode "$mode" >/dev/null 2>&1 || true
    if [[ -s "$extracted_fallback" ]]; then
      latest_audit_findings_file="$extracted_fallback"
      echo "Recovered audit findings from log fallback: $latest_audit_findings_file"
    else
      rm -f "$extracted_fallback" >/dev/null 2>&1 || true
    fi
  fi
  if [[ -z "$latest_audit_findings_file" ]]; then
    latest_audit_findings_file="$(latest_findings_for_source "auditor" "$mode" || true)"
  fi

  audit_finished_epoch="$(date +%s)"
  audit_finished_ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  audit_duration_s=$((audit_finished_epoch - audit_started_epoch))
  audit_result="${latest_audit_result_value}"
  if [[ -z "$audit_result" ]]; then
    audit_result="failed"
    if [[ "$audit_ec" -eq 0 ]]; then
      audit_result="passed"
    elif [[ "$audit_ec" -eq "${EXIT_QUOTA_EXHAUSTED:-10}" ]]; then
      audit_result="quota_exhausted"
    fi
  fi
  latest_audit_result_value="$audit_result"

  if [[ "$have_metrics" == "1" ]]; then
    metrics_append_jsonl "$REVIEW_RUNS_LOG" \
      "event_type=loop_audit_checkpoint" \
      "ts_utc=${audit_finished_ts}" \
      "loop_session_id=${LOOP_SESSION_ID}" \
      "mode=${mode}" \
      "task_id=${task_id}" \
      "phase=${phase_name}" \
      "started_at_utc=${audit_started_ts}" \
      "finished_at_utc=${audit_finished_ts}" \
      "duration_s=${audit_duration_s}" \
      "result=${audit_result}" \
      "exit_code=${audit_ec}" \
      "findings_file=${latest_audit_findings_file}" || true
  fi

  return "$audit_ec"
}

stop_requested() {
  [[ -f "$STOP_REQUEST_FILE" ]]
}

if is_truthy "$REVIEW_ENABLED" || is_truthy "$PHASE_REVIEW_ENABLED"; then
  if [[ ! -x "$REVIEW_CMD" ]]; then
    echo "Review command is not executable: $REVIEW_CMD" >&2
    exit 1
  fi
fi

if is_truthy "$AUDIT_ENABLED"; then
  if [[ ! -x "$AUDIT_CMD" ]]; then
    echo "Audit command is not executable: $AUDIT_CMD" >&2
    exit 1
  fi
fi

if is_truthy "$ARCH_REVIEW_ENABLED"; then
  if [[ ! -x "$ARCH_REVIEW_CMD" ]]; then
    echo "Architecture review command is not executable: $ARCH_REVIEW_CMD" >&2
    exit 1
  fi
  if [[ ! -f "$ARCH_REVIEW_PROMPT_FILE" ]]; then
    echo "Architecture review prompt file missing: $ARCH_REVIEW_PROMPT_FILE" >&2
    exit 1
  fi
fi

if [[ ! -x "$FINDINGS_PROCESS_CMD" ]]; then
  echo "Findings processor is not executable: $FINDINGS_PROCESS_CMD" >&2
  exit 1
fi

tasks_since_quick_review=0
watchdog_warning_count=0
retry_task_id=""
retry_count=0
retry_reason=""
retry_failure_files=""
final_gate_retry_count=0
arch_final_retry_count=0
review_retry_task_id=""
review_retry_mode=""
review_retry_count=0
agent_failover_attempts=0
last_completed_task_id=""
iteration=0
restore_loop_checkpoint_if_enabled
write_loop_checkpoint "startup"
while true; do
  if stop_requested; then
    echo "Stop request detected via ${STOP_REQUEST_FILE}. Exiting at natural breakpoint."
    loop_stop_reason="stop_requested"
    rm -f "$STOP_REQUEST_FILE"
    exit 0
  fi
  write_loop_checkpoint "loop_top"

  open_before="$(count_open_tasks)"
  last_open_tasks="$open_before"
  if [[ "$open_before" -eq 0 ]]; then
    echo "Backlog is complete; entering final review/audit gate."

    review_blocking="0"
    review_new_tasks="0"
    audit_blocking="0"
    audit_new_tasks="0"
    review_failed_without_findings="0"
    audit_failed_without_findings="0"

	    if is_truthy "$PHASE_REVIEW_ENABLED"; then
	      set +e
	      run_review "final" "" ""
	      final_review_ec=$?
	      set -e
	      if maybe_handle_runtime_failover \
	        "reviewer" \
	        "$final_review_ec" \
	        "${latest_review_result_value:-final_review_exit_${final_review_ec}}" \
	        "during final review" \
	        "final_review_agent_failover" \
	        "Agent failover: switched reviewer/implementor after final review runtime failure." \
	        "Agent failover could not find a healthy alternate reviewer/implementor after final review failure."
	      then
	        continue
	      fi
	      if maybe_handle_quota_wait_or_exit "$final_review_ec" "${latest_review_result_value:-}" "final_review" "weekly_quota_exhausted"; then
	        continue
	      fi
	      reset_quota_wait
      IFS=$'\t' read -r review_blocking review_new_tasks review_processor_failed \
        <<< "$(process_findings_file "${latest_review_findings_file}" "reviewer" "final")"
      if [[ "$final_review_ec" -ne 0 && "$review_new_tasks" -eq 0 ]]; then
        review_failed_without_findings="1"
      fi
      if [[ "$review_processor_failed" -ne 0 ]]; then
        loop_stop_reason="findings_processor_failed"
        exit "${EXIT_FINDINGS_PROCESSOR_FAILED:-8}"
      fi
    fi

	    if is_truthy "$AUDIT_ENABLED"; then
	      set +e
	      run_audit "final" "" ""
	      final_audit_ec=$?
	      set -e
	      if maybe_handle_runtime_failover \
	        "auditor" \
	        "$final_audit_ec" \
	        "${latest_audit_result_value:-final_audit_exit_${final_audit_ec}}" \
	        "during final audit" \
	        "final_audit_agent_failover" \
	        "Agent failover: switched auditor after final audit runtime failure." \
	        "Agent failover could not find a healthy alternate auditor after final audit failure."
	      then
	        continue
	      fi
	      if maybe_handle_quota_wait_or_exit "$final_audit_ec" "${latest_audit_result_value:-}" "final_audit" "weekly_quota_exhausted"; then
	        continue
	      fi
	      reset_quota_wait
      IFS=$'\t' read -r audit_blocking audit_new_tasks audit_processor_failed \
        <<< "$(process_findings_file "${latest_audit_findings_file}" "auditor" "final")"
      if [[ "$final_audit_ec" -ne 0 && "$audit_new_tasks" -eq 0 ]]; then
        audit_failed_without_findings="1"
      fi
      if [[ "$audit_processor_failed" -ne 0 ]]; then
        loop_stop_reason="findings_processor_failed"
        exit "${EXIT_FINDINGS_PROCESSOR_FAILED:-8}"
      fi
    fi

    open_after_final="$(count_open_tasks)"
    last_open_tasks="$open_after_final"
    if (( open_after_final > 0 )); then
      echo "Final gates generated remediation backlog (${open_after_final} open tasks). Continuing loop."
      final_gate_retry_count=0
      write_loop_checkpoint "final_gate_spawned_tasks"
      continue
    fi

    if [[ "$review_failed_without_findings" -eq 1 || "$audit_failed_without_findings" -eq 1 ]]; then
      final_gate_retry_count=$((final_gate_retry_count + 1))
      if is_positive_integer "$FINAL_GATE_MAX_RETRIES" && (( final_gate_retry_count > FINAL_GATE_MAX_RETRIES )); then
        echo "Final gate failed without actionable findings after ${FINAL_GATE_MAX_RETRIES} retries." >&2
        loop_stop_reason="final_gate_failed_without_actionable_findings"
        exit "${EXIT_FINAL_GATE_EXHAUSTED:-7}"
      fi
      echo "Final gate not satisfied yet (no new tasks). retry=${final_gate_retry_count}/${FINAL_GATE_MAX_RETRIES}."
      write_loop_checkpoint "final_gate_retry"
      sleep 2
      continue
    fi
    final_gate_retry_count=0

	    if is_truthy "$ARCH_REVIEW_ENABLED"; then
	      set +e
	      run_architecture_review
	      arch_review_ec=$?
	      set -e
	      if maybe_handle_runtime_failover \
	        "reviewer" \
	        "$arch_review_ec" \
	        "${latest_review_result_value:-architecture_review_exit_${arch_review_ec}}" \
	        "during architecture review" \
	        "architecture_review_agent_failover" \
	        "Agent failover: switched reviewer/implementor after architecture review runtime failure." \
	        "Agent failover could not find a healthy alternate reviewer/implementor after architecture review failure."
	      then
	        continue
	      fi
	      if maybe_handle_quota_wait_or_exit "$arch_review_ec" "${latest_review_result_value:-}" "architecture_review" "weekly_quota_exhausted"; then
	        continue
	      fi
	      reset_quota_wait
      IFS=$'\t' read -r arch_blocking arch_new_tasks arch_processor_failed \
        <<< "$(process_findings_file "${latest_review_findings_file}" "reviewer" "architecture")"
      if [[ "$arch_processor_failed" -ne 0 ]]; then
        loop_stop_reason="findings_processor_failed"
        exit "${EXIT_FINDINGS_PROCESSOR_FAILED:-8}"
      fi
      open_after_arch="$(count_open_tasks)"
      last_open_tasks="$open_after_arch"
      if (( open_after_arch > 0 )); then
        echo "Architecture review generated remediation backlog (${open_after_arch} open tasks). Continuing loop."
        arch_final_retry_count=0
        write_loop_checkpoint "architecture_review_spawned_tasks"
        continue
      fi
      if [[ "$arch_review_ec" -ne 0 && "$arch_new_tasks" -eq 0 ]]; then
        arch_final_retry_count=$((arch_final_retry_count + 1))
        if is_positive_integer "$ARCH_REVIEW_MAX_RETRIES" && (( arch_final_retry_count > ARCH_REVIEW_MAX_RETRIES )); then
          echo "Architecture review failed without actionable findings after ${ARCH_REVIEW_MAX_RETRIES} retries." >&2
          if [[ -n "${latest_review_log_file}" ]]; then
            echo "Architecture review log: ${latest_review_log_file}" >&2
          fi
          loop_stop_reason="architecture_review_failed_without_actionable_findings"
          exit "${EXIT_ARCH_REVIEW_EXHAUSTED:-9}"
        fi
        echo "Architecture review not satisfied yet (no new tasks). retry=${arch_final_retry_count}/${ARCH_REVIEW_MAX_RETRIES}."
        write_loop_checkpoint "architecture_review_retry"
        sleep 2
        continue
      fi
      arch_final_retry_count=0
    fi

    issue_report_path=".ralph/reports/loop-issues-${LOOP_SESSION_ID}.md"
    if [[ -x "./scripts/loop_issue_report.py" ]]; then
      "$PYTHON_BIN" ./scripts/loop_issue_report.py --session "$LOOP_SESSION_ID" --output "$issue_report_path" || true
      echo "Loop issue report: ${issue_report_path}"
    fi

    echo "All tasks are complete and final review/audit/architecture gates passed."
    loop_stop_reason="all_tasks_complete"
    exit "${EXIT_SUCCESS:-0}"
  fi

  iteration=$((iteration + 1))
  write_loop_checkpoint "task_iteration_${iteration}"
  if (( iteration > MAX_TASKS )); then
    echo "Stopped after MAX_TASKS=${MAX_TASKS} attempts." >&2
    loop_stop_reason="max_tasks_reached"
    exit "${EXIT_REVIEW_FAIL:-2}"
  fi

  task_before="$(first_open_task_id)"
  phase_before="$(first_open_phase)"
  if [[ "$task_before" != "$review_retry_task_id" ]]; then
    review_retry_task_id=""
    review_retry_mode=""
    review_retry_count=0
  fi
  if [[ "$task_before" != "$retry_task_id" ]]; then
    retry_task_id="$task_before"
    retry_count=0
    retry_reason=""
    retry_failure_files=""
  fi
  task_started_epoch="$(date +%s)"
  task_started_ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  echo "=== Task loop iteration ${iteration}; open tasks remaining: ${open_before} ==="
  if (( retry_count > 0 )); then
    echo "[self-heal] retrying ${task_before} (attempt ${retry_count}/${SELF_HEAL_MAX_RETRIES_PER_TASK}) reason=${retry_reason:-unknown}"
  fi
  set +e
  TASK_RETRY_COUNT="$retry_count" \
  TASK_RETRY_REASON="$retry_reason" \
  TASK_RETRY_FAILURE_FILES="$retry_failure_files" \
    ./scripts/run_next_task.sh ${forward_args[@]+"${forward_args[@]}"}
  task_ec=$?
  set -e
  task_finished_epoch="$(date +%s)"
  task_finished_ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  task_duration_s=$((task_finished_epoch - task_started_epoch))

  open_after="$(count_open_tasks)"
  last_open_tasks="$open_after"
  completed_this_round=$((open_before - open_after))

  watchdog_triggered="0"
  if is_truthy "$WATCHDOG_ENABLED" && is_positive_integer "$WATCHDOG_MAX_TASK_SECONDS"; then
    if (( task_duration_s > WATCHDOG_MAX_TASK_SECONDS )); then
      watchdog_warning_count=$((watchdog_warning_count + 1))
      echo "[watchdog] task ${task_before} ran ${task_duration_s}s (> ${WATCHDOG_MAX_TASK_SECONDS}s). warning ${watchdog_warning_count}." >&2
      if [[ "$have_metrics" == "1" ]]; then
        metrics_append_jsonl "$TASK_RUNS_LOG" \
          "event_type=loop_watchdog_warning" \
          "ts_utc=${task_finished_ts}" \
          "loop_session_id=${LOOP_SESSION_ID}" \
          "task_id=${task_before}" \
          "phase=${phase_before}" \
          "iteration=${iteration}" \
          "duration_s=${task_duration_s}" \
          "watchdog_threshold_s=${WATCHDOG_MAX_TASK_SECONDS}" \
          "warning_count=${watchdog_warning_count}" \
          "watchdog_warn_limit=${WATCHDOG_WARN_LIMIT}" \
          "watchdog_hard_stop=${WATCHDOG_HARD_STOP}" || true
      fi
      if is_truthy "$WATCHDOG_HARD_STOP"; then
        watchdog_triggered="1"
      elif is_positive_integer "$WATCHDOG_WARN_LIMIT" && (( watchdog_warning_count >= WATCHDOG_WARN_LIMIT )); then
        watchdog_triggered="1"
      fi
    else
      watchdog_warning_count=0
    fi
  fi

  detailed_failure_reason=""
  detailed_failure_files=""
  if [[ "$task_ec" -ne 0 ]]; then
    IFS=$'\t' read -r detailed_failure_reason detailed_failure_files _detail_exit_code \
      <<< "$(latest_task_detail_fields_tsv "$task_before")"
    if [[ -z "$detailed_failure_reason" ]]; then
      detailed_failure_reason="run_next_task_exit_${task_ec}"
    fi
  fi

  if [[ "$have_metrics" == "1" ]]; then
    task_result="passed"
    task_failure_reason="none"
    if [[ "$task_ec" -ne 0 ]]; then
      task_result="failed"
      task_failure_reason="$detailed_failure_reason"
    fi
    metrics_append_jsonl "$TASK_RUNS_LOG" \
      "event_type=task_attempt" \
      "ts_utc=${task_finished_ts}" \
      "loop_session_id=${LOOP_SESSION_ID}" \
      "task_id=${task_before}" \
      "phase=${phase_before}" \
      "iteration=${iteration}" \
      "started_at_utc=${task_started_ts}" \
      "finished_at_utc=${task_finished_ts}" \
      "duration_s=${task_duration_s}" \
      "result=${task_result}" \
      "exit_code=${task_ec}" \
      "failure_reason=${task_failure_reason}" \
      "failure_files=${detailed_failure_files}" \
      "retry_count=${retry_count}" \
      "open_before=${open_before}" \
      "open_after=${open_after}" \
      "completed_count=${completed_this_round}" || true
  fi

	  if [[ "$task_ec" -ne 0 ]]; then
	    if maybe_handle_runtime_failover \
	      "implementor" \
	      "$task_ec" \
	      "${detailed_failure_reason:-run_next_task_exit_${task_ec}}" \
	      "for task execution" \
	      "task_agent_failover" \
	      "Agent failover: switched implementor after task runtime failure (task=${task_before})." \
	      "Agent failover could not find a healthy alternate implementor after task failure."
	    then
	      continue
	    fi
	    if maybe_handle_quota_wait_or_exit "$task_ec" "$detailed_failure_reason" "task_${task_before}" "weekly_quota_exhausted"; then
	      continue
	    fi
	    reset_quota_wait

    allow_self_heal="0"
    if is_truthy "$SELF_HEAL_ENABLED" && is_positive_integer "$SELF_HEAL_MAX_RETRIES_PER_TASK"; then
      if (( retry_count < SELF_HEAL_MAX_RETRIES_PER_TASK )); then
        allow_self_heal="1"
      fi
    fi

    if [[ "$allow_self_heal" == "1" ]]; then
      retry_count=$((retry_count + 1))
      retry_reason="$detailed_failure_reason"
      retry_failure_files="$detailed_failure_files"
      echo "[self-heal] ${task_before} failed (reason=${retry_reason}). scheduling retry ${retry_count}/${SELF_HEAL_MAX_RETRIES_PER_TASK}."
      if [[ -n "$retry_failure_files" ]]; then
        echo "[self-heal] failure files hint: ${retry_failure_files}"
      fi
      if [[ "$have_metrics" == "1" ]]; then
        metrics_append_jsonl "$TASK_RUNS_LOG" \
          "event_type=self_heal_retry_scheduled" \
          "ts_utc=${task_finished_ts}" \
          "loop_session_id=${LOOP_SESSION_ID}" \
          "task_id=${task_before}" \
          "phase=${phase_before}" \
          "iteration=${iteration}" \
          "exit_code=${task_ec}" \
          "failure_reason=${retry_reason}" \
          "failure_files=${retry_failure_files}" \
          "retry_count=${retry_count}" \
          "retry_limit=${SELF_HEAL_MAX_RETRIES_PER_TASK}" || true
      fi
      if is_positive_integer "$SELF_HEAL_RETRY_DELAY_SECONDS"; then
        sleep "$SELF_HEAL_RETRY_DELAY_SECONDS"
      fi
      write_loop_checkpoint "task_self_heal_retry_scheduled"
      continue
    fi

    loop_stop_reason="task_attempt_failed_after_retries"
    echo "Loop stopping: ${task_before} failed after ${SELF_HEAL_MAX_RETRIES_PER_TASK} retries." >&2
    echo "Failure reason: ${detailed_failure_reason}" >&2
    if [[ -n "$detailed_failure_files" ]]; then
      echo "Failure file hints: ${detailed_failure_files}" >&2
    fi
    echo "Inspect logs under: ${LOG_ROOT}/${task_before}" >&2
    exit "$task_ec"
  fi

  reset_quota_wait
  agent_failover_attempts=0
  last_completed_task_id="$task_before"
  retry_task_id=""
  retry_count=0
  retry_reason=""
  retry_failure_files=""
  write_loop_checkpoint "task_completed"

  if [[ "$watchdog_triggered" == "1" ]]; then
    echo "[watchdog] threshold exceeded; stopping loop for operator review." >&2
    loop_stop_reason="watchdog_threshold_exceeded"
    exit "${EXIT_WATCHDOG:-5}"
  fi

  if (( open_after >= open_before )); then
    echo "No backlog progress detected (open_before=${open_before}, open_after=${open_after}). Stopping." >&2
    loop_stop_reason="no_backlog_progress"
    exit "${EXIT_MISSING_TOKEN:-3}"
  fi

  tasks_since_quick_review=$((tasks_since_quick_review + completed_this_round))

  if is_truthy "$PHASE_REVIEW_ENABLED"; then
    if (( open_after == 0 )); then
      :
    else
      phase_after="$(first_open_phase)"
	      if [[ -n "$phase_before" && -n "$phase_after" && "$phase_after" != "$phase_before" ]]; then
	        set +e
	        run_review "phase" "${task_before:-}" "${phase_before:-}"
	        phase_review_ec=$?
	        set -e
	        if maybe_handle_runtime_failover \
	          "reviewer" \
	          "$phase_review_ec" \
	          "${latest_review_result_value:-phase_review_exit_${phase_review_ec}}" \
	          "during phase review" \
	          "phase_review_agent_failover" \
	          "Agent failover: switched reviewer/implementor after phase review runtime failure." \
	          "Agent failover could not find a healthy alternate reviewer/implementor after phase review failure."
	        then
	          continue
	        fi
	        if maybe_handle_quota_wait_or_exit "$phase_review_ec" "${latest_review_result_value:-}" "phase_review" "weekly_quota_exhausted"; then
	          continue
	        fi
	        reset_quota_wait
        IFS=$'\t' read -r phase_blocking phase_new_tasks phase_processor_failed \
          <<< "$(process_findings_file "${latest_review_findings_file}" "reviewer" "phase")"
        if [[ "$phase_processor_failed" -ne 0 ]]; then
          loop_stop_reason="findings_processor_failed"
          exit "${EXIT_FINDINGS_PROCESSOR_FAILED:-8}"
        fi
        if [[ "$phase_review_ec" -ne 0 && "$phase_new_tasks" -eq 0 ]]; then
          if [[ "$review_retry_task_id" != "$task_before" || "$review_retry_mode" != "phase" ]]; then
            review_retry_task_id="$task_before"
            review_retry_mode="phase"
            review_retry_count=0
          fi
          if schedule_review_remediation_retry "phase" "$task_before" "$phase_before" "$phase_review_ec" "${latest_review_findings_file}" "${latest_review_log_file}" review_retry_count; then
            tasks_since_quick_review=0
            write_loop_checkpoint "phase_review_self_heal_retry"
            continue
          fi
          echo "Loop stopping: phase review remediation exhausted for ${task_before} after ${REVIEW_SELF_HEAL_MAX_RETRIES} retries." >&2
          echo "Failure reason: review_failed_without_actionable_findings" >&2
          echo "Review exit code: ${phase_review_ec}" >&2
          if [[ -n "${latest_review_log_file}" ]]; then
            echo "Review log: ${latest_review_log_file}" >&2
          fi
          if [[ -n "${latest_review_findings_file}" ]]; then
            echo "Findings file: ${latest_review_findings_file}" >&2
          fi
          loop_stop_reason="review_self_heal_exhausted"
          exit "${EXIT_REVIEW_SELF_HEAL_EXHAUSTED:-4}"
        fi
        if (( phase_new_tasks > 0 )); then
          echo "Phase review appended ${phase_new_tasks} remediation task(s)."
          review_retry_task_id=""
          review_retry_mode=""
          review_retry_count=0
        fi
      fi
    fi
  fi

  if is_truthy "$REVIEW_ENABLED" && is_positive_integer "$REVIEW_EVERY_TASKS"; then
	    if (( tasks_since_quick_review >= REVIEW_EVERY_TASKS )); then
	      set +e
	      run_review "quick" "${task_before:-}" "${phase_before:-}"
	      quick_review_ec=$?
	      set -e
	      if maybe_handle_runtime_failover \
	        "reviewer" \
	        "$quick_review_ec" \
	        "${latest_review_result_value:-quick_review_exit_${quick_review_ec}}" \
	        "during quick review" \
	        "quick_review_agent_failover" \
	        "Agent failover: switched reviewer/implementor after quick review runtime failure." \
	        "Agent failover could not find a healthy alternate reviewer/implementor after quick review failure."
	      then
	        continue
	      fi
	      if maybe_handle_quota_wait_or_exit "$quick_review_ec" "${latest_review_result_value:-}" "quick_review" "weekly_quota_exhausted"; then
	        continue
	      fi
	      reset_quota_wait
      IFS=$'\t' read -r quick_blocking quick_new_tasks quick_processor_failed \
        <<< "$(process_findings_file "${latest_review_findings_file}" "reviewer" "quick")"
      if [[ "$quick_processor_failed" -ne 0 ]]; then
        loop_stop_reason="findings_processor_failed"
        exit "${EXIT_FINDINGS_PROCESSOR_FAILED:-8}"
      fi
      if [[ "$quick_review_ec" -ne 0 && "$quick_new_tasks" -eq 0 ]]; then
        if [[ "$review_retry_task_id" != "$task_before" || "$review_retry_mode" != "quick" ]]; then
          review_retry_task_id="$task_before"
          review_retry_mode="quick"
          review_retry_count=0
        fi
        if schedule_review_remediation_retry "quick" "$task_before" "$phase_before" "$quick_review_ec" "${latest_review_findings_file}" "${latest_review_log_file}" review_retry_count; then
          tasks_since_quick_review=0
          write_loop_checkpoint "quick_review_self_heal_retry"
          continue
        fi
        echo "Loop stopping: quick review remediation exhausted for ${task_before} after ${REVIEW_SELF_HEAL_MAX_RETRIES} retries." >&2
        echo "Failure reason: review_failed_without_actionable_findings" >&2
        echo "Review exit code: ${quick_review_ec}" >&2
        if [[ -n "${latest_review_log_file}" ]]; then
          echo "Review log: ${latest_review_log_file}" >&2
        fi
        if [[ -n "${latest_review_findings_file}" ]]; then
          echo "Findings file: ${latest_review_findings_file}" >&2
        fi
        loop_stop_reason="review_self_heal_exhausted"
        exit "${EXIT_REVIEW_SELF_HEAL_EXHAUSTED:-4}"
      fi
      if (( quick_new_tasks > 0 )); then
        echo "Quick review appended ${quick_new_tasks} remediation task(s)."
        review_retry_task_id=""
        review_retry_mode=""
        review_retry_count=0
      fi
      tasks_since_quick_review=0
    fi
  fi

  if is_truthy "$LOG_PRUNE_ENABLED" && is_positive_integer "$LOG_PRUNE_EVERY_TASKS"; then
    if (( iteration % LOG_PRUNE_EVERY_TASKS == 0 )); then
      run_log_prune "post_task" || true
    fi
  fi

  if stop_requested; then
    echo "Stop request detected via ${STOP_REQUEST_FILE}. Exiting at natural breakpoint."
    loop_stop_reason="stop_requested"
    rm -f "$STOP_REQUEST_FILE"
    exit "${EXIT_SUCCESS:-0}"
  fi
done
