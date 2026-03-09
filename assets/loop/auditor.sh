#!/usr/bin/env bash
set -euo pipefail

# Generic auditor wrapper for third-party audit checkpoints.
# Dynamically selects a distinct healthy auditor agent.

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
metrics_lib="${script_dir}/scripts/metrics_lib.sh"
dispatcher="${script_dir}/scripts/agent_dispatcher.sh"
exit_codes="${script_dir}/scripts/exit_codes.sh"

# Ensure we have the dispatcher functions
if [[ -f "$dispatcher" ]]; then
    source "$dispatcher"
else
    echo "ERROR: Dispatcher not found at $dispatcher" >&2
    exit 1
fi

if [[ -f "$exit_codes" ]]; then
    # shellcheck disable=SC1090
    source "$exit_codes"
fi

# Read prompt from file (preferred) or stdin
prompt=""
if [[ $# -gt 0 && -f "$1" ]]; then
    prompt=$(cat "$1")
else
    prompt="$(cat)"
fi

if [[ -z "${prompt//[[:space:]]/}" ]]; then
  echo "Empty prompt; auditor.sh requires a non-empty prompt." >&2
  exit 1
fi

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

# Get active implementor to ensure distinction if possible
impl_resolved="${LOOP_ACTIVE_IMPLEMENTOR:-}"
if [[ -z "$impl_resolved" ]]; then
    impl_resolved=$(get_active_implementor)
fi
impl_bin=""
if [[ -n "$impl_resolved" ]]; then
    IFS=':' read -r impl_bin _ <<< "$impl_resolved"
fi

# Try to find a healthy auditor (distinct from implementor if possible)
resolved="${LOOP_ACTIVE_AUDITOR:-}"
if [[ -z "$resolved" ]]; then
    resolved=$(get_active_auditor "$impl_bin")
fi
if [[ -z "$resolved" ]]; then
    echo "CRITICAL: No available auditor agents found!" >&2
    exit 1
fi

resolved_parse "$resolved" AGENT_BIN AGENT_CMD AGENT_EXTRA_ARGS
WORKDIR="${WORKDIR:-$(pwd)}"
AUDITOR_TIMEOUT_SECONDS="${AUDITOR_TIMEOUT_SECONDS:-900}"
AUDITOR_NO_OUTPUT_TIMEOUT_SECONDS="${AUDITOR_NO_OUTPUT_TIMEOUT_SECONDS:-300}"

echo "[auditor.sh] attempting audit with: ${AGENT_BIN} ${AGENT_CMD} ${AGENT_EXTRA_ARGS}"
echo "[auditor.sh] startup watchdog: ${AUDITOR_NO_OUTPUT_TIMEOUT_SECONDS}s without output (hard timeout: ${AUDITOR_TIMEOUT_SECONDS}s)"

tmp_output="$(mktemp)"
prompt_file="$(mktemp)"
echo "$prompt" > "$prompt_file"
trap 'rm -f "$tmp_output" "$prompt_file"' EXIT

set +e
case "$AGENT_BIN" in
    codex)
        cat "$prompt_file" | run_with_timeout_internal "$AUDITOR_TIMEOUT_SECONDS" "cd \"$WORKDIR\" && $AGENT_BIN $AGENT_CMD $AGENT_EXTRA_ARGS -" "$AUDITOR_NO_OUTPUT_TIMEOUT_SECONDS" 2>&1 | tee "$tmp_output"
        ;;
    gemini|agent|copilot|vibe)
        run_with_timeout_internal "$AUDITOR_TIMEOUT_SECONDS" "PROMPT_FILE=\"$prompt_file\"; cd \"$WORKDIR\" && $AGENT_BIN $AGENT_CMD \"\$(cat \"\$PROMPT_FILE\")\" $AGENT_EXTRA_ARGS" "$AUDITOR_NO_OUTPUT_TIMEOUT_SECONDS" 2>&1 | tee "$tmp_output"
        ;;
    *)
        cat "$prompt_file" | run_with_timeout_internal "$AUDITOR_TIMEOUT_SECONDS" "cd \"$WORKDIR\" && $AGENT_BIN $AGENT_CMD $AGENT_EXTRA_ARGS" "$AUDITOR_NO_OUTPUT_TIMEOUT_SECONDS" 2>&1 | tee "$tmp_output"
        ;;
esac
auditor_ec=$?
set -e

# Metrics logging
if [[ -f "$metrics_lib" ]]; then
    # shellcheck disable=SC1090
    source "$metrics_lib" && metrics_init || true
    token_value="$(metrics_extract_tokens_used "$tmp_output" || true)"
    metrics_append_token_row "auditor" "${LOOP_REVIEW_TASK:-}" "${LOOP_REVIEW_MODE:-}" "${token_value:-}" "$auditor_ec" || true
fi

# Policy: free Copilot models are only allowed for health checks, never active audit execution.
if [[ "$AGENT_BIN" == "copilot" ]] && copilot_forbidden_runtime_model_seen "$tmp_output"; then
    echo "MODEL_POLICY_VIOLATION: copilot runtime matched COPILOT_FORBIDDEN_RUNTIME_MODELS during audit." >&2
    rm -f "$tmp_output"
    exit "${EXIT_MODEL_POLICY_VIOLATION:-13}"
fi

# Final check for decision token (accept token as standalone word anywhere in output).
decision_token="$(
  python3 - "$tmp_output" <<'PY'
import re
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8", errors="ignore")
matches = re.findall(r"\b(AUDIT_PASS|AUDIT_FAIL)\b", text)
print(matches[-1] if matches else "")
PY
)"
if [[ -n "$decision_token" ]]; then
    echo "$decision_token"
    rm -f "$tmp_output"
    if [[ "$decision_token" == "AUDIT_PASS" ]]; then
        exit "${EXIT_SUCCESS:-0}"
    fi
    exit "${EXIT_REVIEW_FAIL:-2}"
fi

if grep -Eq "^NO_OUTPUT_TIMEOUT$" "$tmp_output"; then
    echo "CRITICAL: Auditor ${AGENT_BIN} produced no output for ${AUDITOR_NO_OUTPUT_TIMEOUT_SECONDS}s." >&2
    rm -f "$tmp_output"
    exit "${EXIT_WRAPPER_NO_OUTPUT:-125}"
fi
if grep -Eq "^TIMEOUT$" "$tmp_output"; then
    echo "CRITICAL: Auditor ${AGENT_BIN} exceeded hard timeout (${AUDITOR_TIMEOUT_SECONDS}s)." >&2
    rm -f "$tmp_output"
    exit 124
fi

echo "CRITICAL: Auditor ${AGENT_BIN} failed to produce a valid token (EC=${auditor_ec}). Check logs." >&2
rm -f "$tmp_output"
exit "${EXIT_MISSING_TOKEN:-3}"
