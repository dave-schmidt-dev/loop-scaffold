#!/usr/bin/env bash
# Shared execution helpers for review/audit checkpoint wrappers.

checkpoint_exec_require_file() {
  local file_path="$1"
  if [[ ! -f "$file_path" ]]; then
    echo "Missing required file: $file_path" >&2
    exit 1
  fi
}

checkpoint_exec_require_command() {
  local cmd_string="$1"
  local label="$2"
  local cmd_bin="${cmd_string%% *}"
  if [[ -z "$cmd_bin" ]]; then
    echo "${label} command is empty." >&2
    exit 2
  fi
  if [[ "$cmd_bin" == */* ]]; then
    checkpoint_exec_require_file "$cmd_bin"
  elif ! command -v "$cmd_bin" >/dev/null 2>&1; then
    echo "${label} command not found on PATH: $cmd_bin" >&2
    exit 1
  fi
}

checkpoint_exec_default_outer_timeout() {
  local exec_timeout="$1"
  if [[ "$exec_timeout" =~ ^[0-9]+$ ]] && [[ "$exec_timeout" -gt 0 ]]; then
    printf '%s\n' "$((exec_timeout + 15))"
  else
    printf '0\n'
  fi
}

checkpoint_exec_collect_backlog_stats() {
  local tasks_file="$1"
  local done_count open_count first_open_task first_open_phase
  done_count="$(awk '/^- \[[xX]\] TASK-[0-9]+:/ {c++} END {print c+0}' "$tasks_file")"
  open_count="$(awk '/^- \[ \] TASK-[0-9]+:/ {c++} END {print c+0}' "$tasks_file")"
  first_open_task="$(awk '/^- \[ \] TASK-[0-9]+:/ {line=$0; sub(/^- \[ \] /, "", line); sub(/:.*/, "", line); print line; exit}' "$tasks_file")"
  first_open_phase="$(awk '/^### / {section=substr($0,5)} /^- \[ \] TASK-[0-9]+:/ {print section; exit}' "$tasks_file")"
  printf '%s\t%s\t%s\t%s\n' "$done_count" "$open_count" "$first_open_task" "$first_open_phase"
}

checkpoint_exec_collect_task_metadata() {
  local tasks_file="$1"
  local task_id="$2"
  local task_specs="" task_tests=""

  if [[ -n "$task_id" ]]; then
    task_specs="$(awk -v id="$task_id" '
      $0 ~ "^- \\[[ xX]\\] " id ":" {in_task=1; next}
      in_task && /^- \[[ xX]\] TASK-[0-9]+:/ {exit}
      in_task && /^  - spec:/ {
        sub(/^  - spec:[[:space:]]*/, "")
        print
        exit
      }
    ' "$tasks_file")"
    task_tests="$(awk -v id="$task_id" '
      $0 ~ "^- \\[[ xX]\\] " id ":" {in_task=1; next}
      in_task && /^- \[[ xX]\] TASK-[0-9]+:/ {exit}
      in_task && /^  - test:/ {
        sub(/^  - test:[[:space:]]*/, "")
        print
        exit
      }
    ' "$tasks_file")"
  fi

  printf '%s\t%s\n' "$task_specs" "$task_tests"
}

checkpoint_exec_write_result_json() {
  local result_file="$1"
  local source="$2"
  local result="$3"
  local exit_code="$4"
  local findings_path="$5"
  local duration_s="$6"
  local ts_utc="$7"
  local log_path="$8"
  local command_exit_code="$9"
  mkdir -p "$(dirname "$result_file")"
  python3 - "$result_file" "$source" "$result" "$exit_code" "$findings_path" "$log_path" "$duration_s" "$ts_utc" "$command_exit_code" <<'PY'
import json
import sys
from pathlib import Path

out = Path(sys.argv[1])
payload = {
    "source": sys.argv[2],
    "result": sys.argv[3],
    "exit_code": int(sys.argv[4]),
    "findings_file": sys.argv[5],
    "log_file": sys.argv[6],
    "duration_s": int(sys.argv[7]),
    "ts_utc": sys.argv[8],
    "command_exit_code": int(sys.argv[9]),
}
out.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY
}

checkpoint_exec_append_missing_token_finding() {
  local log_file="$1"
  local output_file="$2"
  local source="$3"
  local source_mode="$4"
  local title="$5"
  local file_label="$6"
  local fix_hint="$7"
  python3 - "$log_file" "$output_file" "$source" "$source_mode" "$title" "$file_label" "$fix_hint" <<'PY'
import json
import sys
from pathlib import Path

log_path = Path(sys.argv[1])
out_path = Path(sys.argv[2])
source = sys.argv[3]
mode = sys.argv[4]
title = sys.argv[5]
file_label = sys.argv[6]
fix_hint = sys.argv[7]
tail = ""
if log_path.is_file():
    lines = log_path.read_text(encoding="utf-8", errors="ignore").splitlines()
    tail = "\n".join(lines[-40:]).strip()
if not tail:
    tail = f"No {source} log lines available."

obj = {
    "source": source,
    "mode": mode,
    "title": title,
    "severity": "medium",
    "evidence": tail[:1200],
    "file": file_label,
    "fix_hint": fix_hint,
    "task_link": "REQ-013",
}
with out_path.open("a", encoding="utf-8") as handle:
    handle.write(json.dumps(obj, ensure_ascii=True) + "\n")
PY
}

checkpoint_exec_classify_result() {
  local pass_token="$1"
  local fail_token="$2"
  local command_ec="$3"
  local log_file="$4"
  local result="missing_token"
  local final_ec="${EXIT_MISSING_TOKEN:-3}"

  if rg -n "^${pass_token}$" "$log_file" >/dev/null 2>&1; then
    result="pass"
    final_ec="${EXIT_SUCCESS:-0}"
  elif rg -n "^${fail_token}$" "$log_file" >/dev/null 2>&1; then
    result="fail"
    final_ec="${EXIT_REVIEW_FAIL:-2}"
  elif [[ "$command_ec" -eq 124 ]]; then
    result="timed_out"
    final_ec="${EXIT_TIMEOUT:-11}"
  elif [[ "$command_ec" -eq "${EXIT_WRAPPER_NO_OUTPUT:-125}" ]]; then
    result="no_output_timed_out"
    final_ec="${EXIT_NO_OUTPUT_TIMEOUT:-12}"
  elif [[ "$command_ec" -eq "${EXIT_MODEL_POLICY_VIOLATION:-13}" ]]; then
    result="model_policy_violation"
    final_ec="${EXIT_MODEL_POLICY_VIOLATION:-13}"
  elif rg -n "(rate limit|quota|usage cap|token budget|try again in|too many requests)" "$log_file" >/dev/null 2>&1; then
    result="quota_exhausted"
    final_ec="${EXIT_QUOTA_EXHAUSTED:-10}"
  elif [[ "$command_ec" -eq "${EXIT_QUOTA_EXHAUSTED:-10}" ]]; then
    result="quota_exhausted"
    final_ec="${EXIT_QUOTA_EXHAUSTED:-10}"
  fi

  printf '%s\t%s\n' "$result" "$final_ec"
}

checkpoint_exec_emit_final_message() {
  local label="$1"
  local mode="$2"
  local final_ec="$3"
  local log_file="$4"
  local pass_token="$5"
  local fail_token="$6"

  if [[ "$final_ec" -eq "${EXIT_SUCCESS:-0}" ]]; then
    echo "${label} passed (${mode})."
    return 0
  fi
  if [[ "$final_ec" -eq "${EXIT_REVIEW_FAIL:-2}" ]]; then
    echo "${label} failed (${mode}). See ${log_file}" >&2
    return 0
  fi
  if [[ "$final_ec" -eq "${EXIT_QUOTA_EXHAUSTED:-10}" ]]; then
    echo "${label} quota exhausted (${mode}). See ${log_file}" >&2
    return 0
  fi
  if [[ "$final_ec" -eq "${EXIT_TIMEOUT:-11}" ]]; then
    echo "${label} timed out (${mode}). See ${log_file}" >&2
    return 0
  fi
  if [[ "$final_ec" -eq "${EXIT_NO_OUTPUT_TIMEOUT:-12}" ]]; then
    echo "${label} failed due to no output timeout (${mode}). See ${log_file}" >&2
    return 0
  fi
  if [[ "$final_ec" -eq "${EXIT_MODEL_POLICY_VIOLATION:-13}" ]]; then
    echo "${label} failed due to model policy violation (${mode}). See ${log_file}" >&2
    return 0
  fi
  echo "${label} did not emit ${pass_token}/${fail_token} token. See ${log_file}" >&2
}

checkpoint_exec_run() {
  local done_count open_count first_open_task first_open_phase
  local task_specs="" task_tests=""
  local outer_timeout_value=""
  local timestamp="" started_epoch="" started_ts="" finished_epoch="" finished_ts="" duration_s=""
  local tmpdir="" context_file="" precheck_log="" full_prompt_file=""
  local precheck_ec=0
  local stream_fifo="" tee_pid="" agent_pid="" agent_command="" agent_cmd_escaped=""
  local command_ec=0 result="" final_ec=""
  local found_logs=0
  local recent_log=""

  checkpoint_exec_require_file "$TASKS_FILE"
  checkpoint_exec_require_file "$CHECKPOINT_PROMPT_FILE"
  checkpoint_exec_require_file "./scripts/extract_findings.py"
  checkpoint_exec_require_command "$CHECKPOINT_AGENT_CMD" "$CHECKPOINT_AGENT_LABEL"

  IFS=$'\t' read -r done_count open_count first_open_task first_open_phase \
    <<< "$(checkpoint_exec_collect_backlog_stats "$TASKS_FILE")"

  if [[ "${CHECKPOINT_INCLUDE_TASK_METADATA:-0}" == "1" ]]; then
    IFS=$'\t' read -r task_specs task_tests \
      <<< "$(checkpoint_exec_collect_task_metadata "$TASKS_FILE" "${CHECKPOINT_TASK_ID:-}")"
  fi

  mkdir -p "$CHECKPOINT_LOG_ROOT" "$CHECKPOINT_FINDINGS_ROOT" "$STATE_ROOT"

  outer_timeout_value="${CHECKPOINT_OUTER_TIMEOUT_SECONDS:-}"
  if [[ -z "$outer_timeout_value" ]]; then
    outer_timeout_value="$(checkpoint_exec_default_outer_timeout "${CHECKPOINT_EXEC_TIMEOUT_SECONDS:-0}")"
  fi

  timestamp="$(date +"%Y%m%d-%H%M%S")"
  CHECKPOINT_EXEC_LOG_FILE="${CHECKPOINT_LOG_ROOT}/${CHECKPOINT_LOG_PREFIX}-${CHECKPOINT_MODE}-${timestamp}.log"
  CHECKPOINT_EXEC_FINDINGS_FILE="${CHECKPOINT_FINDINGS_ROOT}/${CHECKPOINT_SOURCE}-${CHECKPOINT_MODE}-${timestamp}.jsonl"
  started_epoch="$(date +%s)"
  started_ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  tmpdir="$(mktemp -d)"
  context_file="${tmpdir}/${CHECKPOINT_LOG_PREFIX}_context.md"
  precheck_log="${tmpdir}/${CHECKPOINT_LOG_PREFIX}_precheck.log"
  full_prompt_file="${tmpdir}/${CHECKPOINT_LOG_PREFIX}_full_prompt.md"

  set +e
  echo "[${CHECKPOINT_PRECHECK_PREFIX}] precheck starting: ${CHECKPOINT_PRECHECK_CMD}" >&2
  bash -lc "$CHECKPOINT_PRECHECK_CMD" >"$precheck_log" 2>&1
  precheck_ec=$?
  echo "[${CHECKPOINT_PRECHECK_PREFIX}] precheck finished (exit=${precheck_ec})." >&2
  set -e

  {
    echo "## ${CHECKPOINT_CONTEXT_HEADING}"
    echo "- Mode: ${CHECKPOINT_MODE}"
    echo "- Focus task: ${CHECKPOINT_TASK_ID:-none}"
    echo "- Focus phase: ${CHECKPOINT_PHASE_NAME:-none}"
    echo "- Completed tasks: ${done_count}"
    echo "- Open tasks: ${open_count}"
    echo "- Next open task: ${first_open_task:-none}"
    echo "- Next open phase: ${first_open_phase:-none}"
    if [[ -n "$task_specs" ]]; then
      echo "- Focus task specs: ${task_specs}"
    fi
    if [[ -n "$task_tests" ]]; then
      echo "- Focus task tests: ${task_tests}"
    fi
    echo "- Precomputed quality gate command: ${CHECKPOINT_PRECHECK_CMD}"
    echo "- Precomputed quality gate exit code: ${precheck_ec}"
    echo
    echo "## Precomputed Quality Gate Output"
    echo '```'
    tail -n "${CHECKPOINT_PRECHECK_LINES}" "$precheck_log"
    echo '```'
    echo
    echo "## Recent Agent Log Snippets"
    found_logs=0
    while IFS= read -r recent_log; do
      found_logs=1
      echo
      echo "### $(basename "$recent_log")"
      echo '```'
      tail -n "${CHECKPOINT_SNIPPET_LINES}" "$recent_log"
      echo '```'
    done < <(ls -1t ${CHECKPOINT_AGENT_LOG_GLOB:-${LOG_ROOT:-.ralph/logs}/TASK-*/*.agent.log} 2>/dev/null | head -n "${CHECKPOINT_RECENT_LOG_COUNT}")
    if [[ "$found_logs" -eq 0 ]]; then
      echo "- No agent logs found."
    fi
  } > "$context_file"

  {
    cat "$CHECKPOINT_PROMPT_FILE"
    echo
    cat "$context_file"
  } > "$full_prompt_file"

  set +e
  echo "=== ${CHECKPOINT_LABEL} ${CHECKPOINT_MODE} (${timestamp}) ===" | tee -a "$CHECKPOINT_EXEC_LOG_FILE"
  echo "Log file: ${CHECKPOINT_EXEC_LOG_FILE}" | tee -a "$CHECKPOINT_EXEC_LOG_FILE"
  echo "${CHECKPOINT_AGENT_LABEL} command: ${CHECKPOINT_AGENT_CMD}" | tee -a "$CHECKPOINT_EXEC_LOG_FILE"
  echo "Outer timeout: ${outer_timeout_value}s (heartbeat: ${CHECKPOINT_EXEC_HEARTBEAT_SECONDS}s)" | tee -a "$CHECKPOINT_EXEC_LOG_FILE"
  echo "" | tee -a "$CHECKPOINT_EXEC_LOG_FILE"

  read -r -a checkpoint_agent_parts <<< "$CHECKPOINT_AGENT_CMD"
  checkpoint_agent_parts+=("$full_prompt_file")
  agent_cmd_escaped=""
  for part in "${checkpoint_agent_parts[@]}"; do
    agent_cmd_escaped+=" $(printf '%q' "$part")"
  done
  agent_command="cd \"$repo_root\" && LOOP_REVIEW_MODE=$(printf '%q' "$CHECKPOINT_MODE") LOOP_REVIEW_TASK=$(printf '%q' "$CHECKPOINT_TASK_ID") ${CHECKPOINT_TIMEOUT_ENV_NAME}=$(printf '%q' "$CHECKPOINT_EXEC_TIMEOUT_SECONDS")${agent_cmd_escaped}"

  stream_fifo="${tmpdir}/${CHECKPOINT_LOG_PREFIX}.stream.fifo"
  mkfifo "$stream_fifo"
  tee -a "$CHECKPOINT_EXEC_LOG_FILE" <"$stream_fifo" &
  tee_pid="$!"

  if [[ "$outer_timeout_value" =~ ^[0-9]+$ ]] && [[ "$outer_timeout_value" -gt 0 ]]; then
    python3 ./scripts/timeout_wrapper.py "$outer_timeout_value" "$agent_command" 0 >"$stream_fifo" 2>&1 &
  else
    bash -lc "$agent_command" >"$stream_fifo" 2>&1 &
  fi
  agent_pid="$!"
  wait "$agent_pid"
  command_ec=$?
  rm -f "$stream_fifo"
  wait "$tee_pid" 2>/dev/null || true
  set -e

  touch "$CHECKPOINT_EXEC_FINDINGS_FILE"
  python3 ./scripts/extract_findings.py \
    --log-file "$CHECKPOINT_EXEC_LOG_FILE" \
    --output "$CHECKPOINT_EXEC_FINDINGS_FILE" \
    --source "$CHECKPOINT_SOURCE" \
    --mode "$CHECKPOINT_MODE" >/dev/null || true

  finished_epoch="$(date +%s)"
  finished_ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  duration_s=$((finished_epoch - started_epoch))

  IFS=$'\t' read -r result final_ec \
    <<< "$(checkpoint_exec_classify_result "$CHECKPOINT_PASS_TOKEN" "$CHECKPOINT_FAIL_TOKEN" "$command_ec" "$CHECKPOINT_EXEC_LOG_FILE")"

  if [[ "$result" == "missing_token" ]]; then
    checkpoint_exec_append_missing_token_finding \
      "$CHECKPOINT_EXEC_LOG_FILE" \
      "$CHECKPOINT_EXEC_FINDINGS_FILE" \
      "$CHECKPOINT_SOURCE" \
      "$CHECKPOINT_MODE" \
      "$CHECKPOINT_MISSING_TOKEN_TITLE" \
      "$CHECKPOINT_MISSING_TOKEN_FILE" \
      "$CHECKPOINT_MISSING_TOKEN_FIX_HINT"
  fi

  if [[ "${have_metrics:-0}" == "1" ]]; then
    metrics_append_jsonl "${CHECKPOINT_METRICS_LOG_FILE:-$REVIEW_RUNS_LOG}" \
      "event_type=${CHECKPOINT_EVENT_TYPE}" \
      "ts_utc=${finished_ts}" \
      "started_at_utc=${started_ts}" \
      "finished_at_utc=${finished_ts}" \
      "duration_s=${duration_s}" \
      "loop_session_id=${LOOP_SESSION_ID:-}" \
      "mode=${CHECKPOINT_MODE}" \
      "focus_task=${CHECKPOINT_TASK_ID}" \
      "focus_phase=${CHECKPOINT_PHASE_NAME}" \
      "open_tasks=${open_count}" \
      "completed_tasks=${done_count}" \
      "${CHECKPOINT_COMMAND_EXIT_FIELD}=${command_ec}" \
      "result=${result}" \
      "final_exit_code=${final_ec}" \
      "log_file=${CHECKPOINT_EXEC_LOG_FILE}" \
      "findings_file=${CHECKPOINT_EXEC_FINDINGS_FILE}" || true
  fi

  echo "${CHECKPOINT_FINDINGS_ENV_NAME}=${CHECKPOINT_EXEC_FINDINGS_FILE}"
  checkpoint_exec_write_result_json \
    "$CHECKPOINT_RESULT_FILE" \
    "$CHECKPOINT_SOURCE" \
    "$result" \
    "$final_ec" \
    "$CHECKPOINT_EXEC_FINDINGS_FILE" \
    "$duration_s" \
    "$finished_ts" \
    "$CHECKPOINT_EXEC_LOG_FILE" \
    "$command_ec"

  CHECKPOINT_EXEC_RESULT="$result"
  CHECKPOINT_EXEC_FINAL_EC="$final_ec"
  CHECKPOINT_EXEC_COMMAND_EC="$command_ec"
  CHECKPOINT_EXEC_STARTED_TS="$started_ts"
  CHECKPOINT_EXEC_FINISHED_TS="$finished_ts"
  CHECKPOINT_EXEC_DURATION_S="$duration_s"
  CHECKPOINT_EXEC_OUTER_TIMEOUT_SECONDS="$outer_timeout_value"

  rm -rf "$tmpdir"
  return 0
}
