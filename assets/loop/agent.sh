#!/usr/bin/env bash
set -euo pipefail

# Generic agent wrapper for Ralph loops.
# Dynamically selects the best available agent from your priority pool.

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
metrics_lib="${script_dir}/scripts/metrics_lib.sh"
dispatcher="${script_dir}/scripts/agent_dispatcher.sh"
exit_codes="${script_dir}/scripts/exit_codes.sh"

source "$dispatcher"
if [[ -f "$exit_codes" ]]; then
  # shellcheck disable=SC1090
  source "$exit_codes"
fi

# Resolve the active implementor. If pre-selected by run_all_tasks, reuse it.
resolved="${LOOP_ACTIVE_IMPLEMENTOR:-}"
if [[ -z "$resolved" ]]; then
    resolved=$(get_active_implementor)
fi
if [[ -z "$resolved" ]]; then
    echo "CRITICAL: No available implementor agents found in your priority list!" >&2
    exit 1
fi

resolved_parse "$resolved" AGENT_BIN AGENT_CMD AGENT_EXTRA_ARGS
WORKDIR="${WORKDIR:-$(pwd)}"
AGENT_HEARTBEAT_SECONDS="${AGENT_HEARTBEAT_SECONDS:-20}"
LOCAL_AUDIT_ON_AGENT_FAILURE="${LOCAL_AUDIT_ON_AGENT_FAILURE:-1}"
LOCAL_AUDIT_FALLBACK_ANY_FAILURE="${LOCAL_AUDIT_FALLBACK_ANY_FAILURE:-0}"
LOCAL_AUDIT_CMD="${LOCAL_AUDIT_CMD:-make check}"

echo "[agent.sh] using active implementor: ${AGENT_BIN} ${AGENT_CMD}${AGENT_EXTRA_ARGS:+ ${AGENT_EXTRA_ARGS}}"

have_metrics="0"
if [[ -f "$metrics_lib" ]]; then
  # shellcheck disable=SC1090
  source "$metrics_lib"
  metrics_init || true
  have_metrics="1"
fi

prompt="$(cat)"
if [[ -z "${prompt//[[:space:]]/}" ]]; then
  echo "Empty prompt on stdin; agent.sh requires a non-empty prompt." >&2
  exit 1
fi

is_truthy() {
  local value="${1:-}"
  local lower_value
  lower_value="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')"
  case "$lower_value" in
    1|true|yes|on) return 0 ;;
    *) return 1 ;;
  esac
}

copilot_forbidden_runtime_model_seen() {
  local log_file="$1"
  local denylist="${COPILOT_FORBIDDEN_RUNTIME_MODELS:-}"
  local entry
  [[ -z "${denylist//[[:space:]]/}" ]] && return 1
  IFS=',' read -r -a denied_models <<< "$denylist"
  for entry in "${denied_models[@]}"; do
    entry="$(printf '%s' "$entry" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
    [[ -z "$entry" ]] && continue
    if grep -Eqi "(^|[[:space:]])${entry}([[:space:]]|$)" "$log_file"; then
      return 0
    fi
  done
  return 1
}

is_infra_subagent_failure() {
  local log_file="$1"
  grep -Eqi \
    "attempt to write a readonly database|failed to write snapshot|operation not permitted|stream disconnected before completion|could not resolve host|error sending request for url|sandbox\(denied|quota|rate limit|usage cap|exhausted" \
    "$log_file"
}

run_agent_once() {
    local output_file="$1"
    local timeout_val=1800 # 30 mins for implementation tasks
    local base_cmd="$AGENT_BIN"
    [[ -n "$AGENT_CMD" ]] && base_cmd+=" $AGENT_CMD"
    [[ -n "$AGENT_EXTRA_ARGS" ]] && base_cmd+=" $AGENT_EXTRA_ARGS"

    case "$AGENT_BIN" in
        codex)
            # Codex reads the prompt from stdin when passed a trailing '-'.
            echo "$prompt" | run_with_timeout_internal "$timeout_val" "$base_cmd -" 2>&1 | tee "$output_file"
            ;;
        gemini|agent|copilot|vibe)
            # These CLIs take the prompt via an explicit flag before the remaining args.
            run_with_timeout_internal "$timeout_val" "$AGENT_BIN $AGENT_CMD \"$prompt\" ${AGENT_EXTRA_ARGS}" 2>&1 | tee "$output_file"
            ;;
        *)
            echo "$prompt" | run_with_timeout_internal "$timeout_val" "$base_cmd" 2>&1 | tee "$output_file"
            ;;
    esac

    local -a pipe_statuses=("${PIPESTATUS[@]}")
    local ec=1
    if (( ${#pipe_statuses[@]} >= 3 )); then
        ec="${pipe_statuses[1]}"
    elif (( ${#pipe_statuses[@]} >= 2 )); then
        ec="${pipe_statuses[0]}"
    elif (( ${#pipe_statuses[@]} >= 1 )); then
        ec="${pipe_statuses[0]}"
    fi
    return "$ec"
}

emitted_done_token() {
    local log_file="$1"
    grep -Eq '^DONE$' "$log_file"
}

tmp_output="$(mktemp)"
trap 'rm -f "$tmp_output"' EXIT

set +e
run_agent_once "$tmp_output"
agent_ec=$?
set -e

if [[ "$have_metrics" == "1" ]]; then
  token_value="$(metrics_extract_tokens_used "$tmp_output" || true)"
  metrics_append_token_row "coder" "${CURRENT_TASK_ID:-}" "" "${token_value:-}" "$agent_ec" || true
fi

# Policy: free Copilot models are only allowed for health checks, never active task execution.
if [[ "$AGENT_BIN" == "copilot" ]] && copilot_forbidden_runtime_model_seen "$tmp_output"; then
  echo "MODEL_POLICY_VIOLATION: copilot runtime matched COPILOT_FORBIDDEN_RUNTIME_MODELS during implementation." >&2
  exit "${EXIT_MODEL_POLICY_VIOLATION:-13}"
fi

if [[ "$agent_ec" -eq 0 ]]; then
  exit 0
fi

# Codex can return non-zero if an intermediate command failed even when the
# loop task completed successfully. Honor explicit completion token.
if emitted_done_token "$tmp_output"; then
  echo "Agent exited non-zero but emitted DONE; continuing as success." >&2
  exit 0
fi

if is_truthy "$LOCAL_AUDIT_ON_AGENT_FAILURE"; then
  if is_truthy "$LOCAL_AUDIT_FALLBACK_ANY_FAILURE" || is_infra_subagent_failure "$tmp_output"; then
    echo "Agent exec failed; running local audit mode: ${LOCAL_AUDIT_CMD}" >&2
    bash -lc "$LOCAL_AUDIT_CMD"
    exit $?
  fi
fi

exit "$agent_ec"
