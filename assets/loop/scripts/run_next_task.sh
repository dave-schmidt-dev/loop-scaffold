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

metrics_lib="${repo_root}/scripts/metrics_lib.sh"

TASKS_FILE="${TASKS_FILE:-tasks.md}"
HISTORY_FILE="${HISTORY_FILE:-HISTORY.md}"
CHECK_CMD="${CHECK_CMD:-make check}"
MAX_ITERS="${MAX_ITERS:-4}"
AGENT_CMD="${AGENT_CMD:-./agent.sh}"
BASE_PROMPT_FILE="${BASE_PROMPT_FILE:-PROMPT.md}"
LOG_ROOT="${LOG_ROOT:-.ralph/logs}"
AUTO_COMMIT="${AUTO_COMMIT:-0}"
TASK_ID="${TASK_ID:-}"
REQUIRED_TEST_TOUCH_GATE="${REQUIRED_TEST_TOUCH_GATE:-1}"
STATE_ROOT="${STATE_ROOT:-.ralph/state}"
TASKS_LOCK_DIR="${TASKS_LOCK_DIR:-${STATE_ROOT}/tasks_md.lockdir}"
TASKS_LOCK_TIMEOUT_SECONDS="${TASKS_LOCK_TIMEOUT_SECONDS:-15}"
EXIT_CODES_FILE="${EXIT_CODES_FILE:-./scripts/exit_codes.sh}"

if [[ -f "$EXIT_CODES_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$EXIT_CODES_FILE"
fi

have_metrics="0"
if [[ -f "$metrics_lib" ]]; then
  # shellcheck disable=SC1090
  source "$metrics_lib"
  metrics_init || true
  have_metrics="1"
fi

usage() {
  cat <<'USAGE'
Usage: ./scripts/run_next_task.sh [options]

Options:
  --task TASK-###    Run a specific open task instead of next open task.
  --max N            Ralph loop max iterations (default: 4).
  --check CMD        Check command (default: make check).
  --commit           Auto-commit when complete (skips if repo was dirty before run).
  --no-commit        Disable auto-commit (default).
  -h, --help         Show help.

Environment overrides:
  TASKS_FILE, HISTORY_FILE, CHECK_CMD, MAX_ITERS, AGENT_CMD,
  BASE_PROMPT_FILE, LOG_ROOT, AUTO_COMMIT, TASK_ID, REQUIRED_TEST_TOUCH_GATE
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task) TASK_ID="$2"; shift 2 ;;
    --max) MAX_ITERS="$2"; shift 2 ;;
    --check) CHECK_CMD="$2"; shift 2 ;;
    --commit) AUTO_COMMIT="1"; shift ;;
    --no-commit) AUTO_COMMIT="0"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

require_file() {
  local file_path="$1"
  if [[ ! -f "$file_path" ]]; then
    echo "Missing required file: $file_path" >&2
    exit 1
  fi
}

require_file "$TASKS_FILE"
require_file "$BASE_PROMPT_FILE"
require_file "./ralph.sh"
require_file "./agent.sh"

has_local_git_repo="0"
if [[ -e "${repo_root}/.git" ]]; then
  has_local_git_repo="1"
fi

compute_project_fingerprint() {
  (
    find . -type f \
      ! -path "./.ralph/*" \
      ! -path "./.git/*" \
      ! -path "./tasks.md" \
      ! -path "./HISTORY.md" \
      ! -path "./__pycache__/*" \
      ! -name "*.pyc" \
      | LC_ALL=C sort \
      | while IFS= read -r file_path; do
          shasum "$file_path"
        done
  ) | shasum | awk '{print $1}'
}

count_open_tasks() {
  awk '/^- \[ \] TASK-[0-9]+:/ {c++} END {print c+0}' "$TASKS_FILE"
}

is_truthy() {
  local value="${1:-}"
  case "$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')" in
    1|true|yes|on) return 0 ;;
    *) return 1 ;;
  esac
}

write_manifest() {
  local output_file="$1"
  (
    find . -type f \
      ! -path "./.ralph/*" \
      ! -path "./.git/*" \
      ! -path "./tasks.md" \
      ! -path "./HISTORY.md" \
      ! -path "./__pycache__/*" \
      ! -name "*.pyc" \
      | LC_ALL=C sort \
      | while IFS= read -r file_path; do
          hash_value="$(shasum "$file_path" | awk '{print $1}')"
          printf '%s\t%s\n' "$file_path" "$hash_value"
        done
  ) > "$output_file"
}

compare_manifest_counts_tsv() {
  local before_manifest="$1"
  local after_manifest="$2"
  python3 - "$before_manifest" "$after_manifest" <<'PY'
import sys

before_file, after_file = sys.argv[1], sys.argv[2]

def load(path):
    data = {}
    with open(path, encoding="utf-8", errors="ignore") as handle:
        for raw in handle:
            raw = raw.rstrip("\n")
            if not raw:
                continue
            try:
                file_path, file_hash = raw.split("\t", 1)
            except ValueError:
                continue
            data[file_path] = file_hash
    return data

before = load(before_file)
after = load(after_file)

added = sum(1 for path in after if path not in before)
removed = sum(1 for path in before if path not in after)
modified = sum(1 for path, value in after.items() if path in before and before[path] != value)
changed_total = added + removed + modified

print(f"{changed_total}\t{added}\t{removed}\t{modified}")
PY
}

write_changed_paths_file() {
  local before_manifest="$1"
  local after_manifest="$2"
  local output_file="$3"
  python3 - "$before_manifest" "$after_manifest" "$output_file" <<'PY'
import sys

before_file, after_file, output_file = sys.argv[1], sys.argv[2], sys.argv[3]

def load(path):
    data = {}
    with open(path, encoding="utf-8", errors="ignore") as handle:
        for raw in handle:
            raw = raw.rstrip("\n")
            if not raw:
                continue
            try:
                file_path, file_hash = raw.split("\t", 1)
            except ValueError:
                continue
            data[file_path] = file_hash
    return data

before = load(before_file)
after = load(after_file)
paths = sorted(
    {path for path in before if path not in after}
    | {path for path in after if path not in before}
    | {path for path, value in after.items() if path in before and before[path] != value}
)

with open(output_file, "w", encoding="utf-8") as handle:
    for path in paths:
        handle.write(path + "\n")
PY
}

extract_required_test_files() {
  local selectors="$1"
  printf '%s\n' "$selectors" \
    | tr ',' '\n' \
    | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' \
    | sed -E 's/::.*$//' \
    | awk 'NF > 0 && !seen[$0]++ { print }'
}

extract_required_spec_ids() {
  local spec_csv="$1"
  printf '%s\n' "$spec_csv" \
    | tr ',' '\n' \
    | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' \
    | tr '[:lower:]' '[:upper:]' \
    | awk 'NF > 0 && !seen[$0]++ { print }'
}

selector_files_cover_required_specs() {
  local spec_csv="$1"
  shift
  local selector_files=("$@")
  local req_id req_covered selector_file
  local -a req_ids=()

  while IFS= read -r req_id; do
    [[ -z "$req_id" ]] && continue
    req_ids+=("$req_id")
  done < <(extract_required_spec_ids "$spec_csv")

  if (( ${#req_ids[@]} == 0 )); then
    return 1
  fi
  if (( ${#selector_files[@]} == 0 )); then
    return 1
  fi

  for req_id in "${req_ids[@]}"; do
    req_covered="false"
    for selector_file in "${selector_files[@]}"; do
      if [[ -f "$selector_file" ]] && rg -n -i "covers:[[:space:]]*${req_id}" "$selector_file" >/dev/null 2>&1; then
        req_covered="true"
        break
      fi
    done
    if [[ "$req_covered" != "true" ]]; then
      return 1
    fi
  done
  return 0
}

task_match=""
if [[ -n "$TASK_ID" ]]; then
  task_match="$(awk -v id="$TASK_ID" '$0 ~ "^- \\[ \\] " id ":" {print NR ":" $0; exit}' "$TASKS_FILE")"
  if [[ -z "$task_match" ]]; then
    if awk -v id="$TASK_ID" '$0 ~ "^- \\[[xX]\\] " id ":" {found=1} END {exit !found}' "$TASKS_FILE"; then
      echo "Task $TASK_ID is already completed." >&2
      exit 1
    fi
    echo "Could not find open task $TASK_ID in $TASKS_FILE." >&2
    exit 1
  fi
else
  task_match="$(awk '/^- \[ \] TASK-[0-9]+:/ {print NR ":" $0; exit}' "$TASKS_FILE")"
  if [[ -z "$task_match" ]]; then
    echo "No open tasks found in $TASKS_FILE." >&2
    exit 0
  fi
fi

task_line_num="${task_match%%:*}"
task_line="${task_match#*:}"
task_id="$(printf '%s\n' "$task_line" | sed -E 's/^- \[[ xX]\] (TASK-[0-9]+):.*/\1/')"
task_title="$(printf '%s\n' "$task_line" | sed -E 's/^- \[[ xX]\] TASK-[0-9]+:[[:space:]]*//')"

task_started_epoch="$(date +%s)"
task_started_ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
open_before_task="$(count_open_tasks)"
open_after_task="$open_before_task"
task_result="failed"
task_failure_reason="unknown"
task_exit_code="1"
ralph_duration_s="0"
final_check_duration_s="0"
check_passed="false"
tests_run=""
tests_passed=""
tests_failed=""
tests_skipped=""
top_error_signature=""
done_gate_present="false"
done_gate_valid="false"
changed_files_count="0"
added_files_count="0"
removed_files_count="0"
modified_files_count="0"
auto_commit_result="not_requested"
required_test_touch_gate_enforced="false"
required_test_selector_files=""
required_test_file_touched="false"
required_test_touch_failure_files=""
required_test_files_count="0"

manifest_before="$(mktemp)"
manifest_after="$(mktemp)"
changed_paths_file="$(mktemp)"
final_check_output_file=""
tasks_lock_acquired="0"

release_tasks_lock() {
  if [[ "$tasks_lock_acquired" != "1" ]]; then
    return
  fi
  loop_state_release_lock_dir_if_owner "$TASKS_LOCK_DIR" "$$"
  tasks_lock_acquired="0"
}

acquire_tasks_lock() {
  local started_epoch now_epoch wait_s
  wait_s="0.1"
  mkdir -p "$(dirname "$TASKS_LOCK_DIR")"
  if [[ ! "$TASKS_LOCK_TIMEOUT_SECONDS" =~ ^[0-9]+$ ]] || [[ "$TASKS_LOCK_TIMEOUT_SECONDS" -lt 1 ]]; then
    TASKS_LOCK_TIMEOUT_SECONDS=15
  fi
  started_epoch="$(date +%s)"

  while ! loop_state_try_acquire_lock_dir "$TASKS_LOCK_DIR" "$$"; do
    now_epoch="$(date +%s)"
    if (( now_epoch - started_epoch >= TASKS_LOCK_TIMEOUT_SECONDS )); then
      return 1
    fi
    sleep "$wait_s"
  done

  tasks_lock_acquired="1"
  return 0
}

cleanup_tmp_metrics_files() {
  release_tasks_lock
  rm -f "$manifest_before" "$manifest_after" "$changed_paths_file"
}

trap cleanup_tmp_metrics_files EXIT

emit_task_metrics() {
  if [[ "$have_metrics" != "1" ]]; then
    return
  fi
  local finished_epoch finished_ts duration_s
  finished_epoch="$(date +%s)"
  finished_ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  duration_s=$((finished_epoch - task_started_epoch))
  metrics_append_jsonl "$TASK_RUNS_LOG" \
    "event_type=task_detail" \
    "ts_utc=${finished_ts}" \
    "loop_session_id=${LOOP_SESSION_ID:-}" \
    "task_id=${task_id}" \
    "task_title=${task_title}" \
    "requirement_ids=${task_specs:-}" \
    "test_selectors=${task_tests:-}" \
    "started_at_utc=${task_started_ts}" \
    "finished_at_utc=${finished_ts}" \
    "duration_s=${duration_s}" \
    "agent_time_s=${ralph_duration_s}" \
    "check_time_s=${final_check_duration_s}" \
    "result=${task_result}" \
    "exit_code=${task_exit_code}" \
    "failure_reason=${task_failure_reason}" \
    "open_before=${open_before_task}" \
    "open_after=${open_after_task}" \
    "check_passed=${check_passed}" \
    "tests_run=${tests_run}" \
    "tests_passed=${tests_passed}" \
    "tests_failed=${tests_failed}" \
    "tests_skipped=${tests_skipped}" \
    "top_error_signature=${top_error_signature}" \
    "done_gate_present=${done_gate_present}" \
    "done_gate_valid=${done_gate_valid}" \
    "changed_files_count=${changed_files_count}" \
    "added_files_count=${added_files_count}" \
    "removed_files_count=${removed_files_count}" \
    "modified_files_count=${modified_files_count}" \
    "required_test_touch_gate_enforced=${required_test_touch_gate_enforced}" \
    "required_test_selector_files=${required_test_selector_files}" \
    "required_test_files_count=${required_test_files_count}" \
    "required_test_file_touched=${required_test_file_touched}" \
    "required_test_touch_failure_files=${required_test_touch_failure_files}" \
    "auto_commit_result=${auto_commit_result}" \
    "log_dir=${task_log_dir:-}" || true
}

extract_field() {
  local field_name="$1"
  awk -v start="$task_line_num" -v field="$field_name" '
    NR > start {
      if ($0 ~ /^- \[[ xX]\] TASK-[0-9]+:/) exit
      if ($0 ~ "^  - " field ":") {
        sub("^  - " field ":[[:space:]]*", "")
        print
        exit
      }
    }
  ' "$TASKS_FILE"
}

task_specs="$(extract_field "spec")"
task_tests="$(extract_field "test")"

if [[ -z "$task_specs" || -z "$task_tests" ]]; then
  echo "Task $task_id is missing required spec/test fields." >&2
  task_failure_reason="missing_spec_or_test_fields"
  task_exit_code="1"
  emit_task_metrics
  exit 1
fi

required_test_files=()
while IFS= read -r selector_file; do
  [[ -z "$selector_file" ]] && continue
  required_test_files+=("$selector_file")
done < <(extract_required_test_files "$task_tests")

required_test_files_count="${#required_test_files[@]}"
if (( required_test_files_count > 0 )); then
  required_test_selector_files="$(printf '%s\n' "${required_test_files[@]}" | paste -sd, -)"
fi

mkdir -p .ralph "$LOG_ROOT"
task_prompt_file=".ralph/current-${task_id}.prompt.md"
task_log_dir="$LOG_ROOT/${task_id}"
task_gate_dir=".ralph/state"
task_gate_file="${task_gate_dir}/${task_id}.done"
mkdir -p "$task_log_dir"
mkdir -p "$task_gate_dir"
preexisting_done_gate="0"
if [[ -f "$task_gate_file" && "$(tr -d '\r\n' < "$task_gate_file")" == "DONE" ]]; then
  preexisting_done_gate="1"
fi
rm -f "$task_gate_file"

{
  cat "$BASE_PROMPT_FILE"
  if [[ -n "${TASK_RETRY_REASON:-}" || -n "${TASK_RETRY_FAILURE_FILES:-}" || -n "${TASK_RETRY_COUNT:-}" ]]; then
    cat <<EOF

## Retry Context
- Retry count: ${TASK_RETRY_COUNT:-0}
- Retry reason: ${TASK_RETRY_REASON:-none}
- Failure file hints: ${TASK_RETRY_FAILURE_FILES:-none}
- If this retry follows a review failure, use the hints above (review log/findings file) to identify concrete remediation steps before coding.
EOF
  fi
  cat <<EOF

## Task Context
- Task ID: ${task_id}
- Title: ${task_title}
- Requirement IDs: ${task_specs}
- Required test selectors: ${task_tests}

## Instructions
- Implement only this task unless a direct dependency blocks it.
- Follow the current requirements in SPEC.md for: ${task_specs}
- Update/add tests so this task is truly covered.
- Ensure at least one required selector test file is changed: ${task_tests}
- Run the check command before you finish: \`${CHECK_CMD}\`
- Only after implementation is complete and checks pass, write this gate file exactly once:
  \`${task_gate_file}\`
  with content: \`DONE\`
EOF
} > "$task_prompt_file"

repo_dirty_before="0"
if [[ "$AUTO_COMMIT" == "1" && "$has_local_git_repo" == "1" ]]; then
  if [[ -n "$(git status --porcelain)" ]]; then
    repo_dirty_before="1"
  fi
fi

write_manifest "$manifest_before"

project_fingerprint_before="$(compute_project_fingerprint)"

echo "Running ${task_id}: ${task_title}"
echo "Spec refs: ${task_specs}"
echo "Test selectors: ${task_tests}"
echo "Logs: ${task_log_dir}"

# Force at least one agent iteration by requiring per-task gate file.
task_check_cmd="${CHECK_CMD} && test -f \"${task_gate_file}\""

export CURRENT_TASK_ID="$task_id"
ralph_started_epoch="$(date +%s)"
set +e
./ralph.sh \
  --workdir "$repo_root" \
  --check "$task_check_cmd" \
  --prompt "$task_prompt_file" \
  --agent "$AGENT_CMD" \
  --max "$MAX_ITERS" \
  --log-dir "$task_log_dir"
ralph_ec=$?
set -e
ralph_finished_epoch="$(date +%s)"
ralph_duration_s=$((ralph_finished_epoch - ralph_started_epoch))
if [[ "$ralph_ec" -ne 0 ]]; then
  task_failure_reason="ralph_iteration_failed"
  task_exit_code="$ralph_ec"
  open_after_task="$(count_open_tasks)"
  emit_task_metrics
  exit "$ralph_ec"
fi

# Confirm one final passing base check before state updates.
final_check_output_file="${task_log_dir}/final-check-$(date +"%Y%m%d-%H%M%S").txt"
final_check_started_epoch="$(date +%s)"
set +e
final_check_output="$(bash -lc "$CHECK_CMD" 2>&1)"
final_check_ec=$?
set -e
final_check_finished_epoch="$(date +%s)"
final_check_duration_s=$((final_check_finished_epoch - final_check_started_epoch))
printf '%s\n' "$final_check_output" | tee "$final_check_output_file"
if [[ "$have_metrics" == "1" ]]; then
  IFS=$'\t' read -r tests_run tests_passed tests_failed tests_skipped check_ok_value top_error_signature \
    <<< "$(metrics_extract_check_summary_tsv "$final_check_output_file")"
  if [[ "${check_ok_value:-false}" == "true" ]]; then
    check_passed="true"
  fi
fi
if [[ "$final_check_ec" -ne 0 ]]; then
  task_failure_reason="check_command_failed"
  task_exit_code="$final_check_ec"
  open_after_task="$(count_open_tasks)"
  emit_task_metrics
  exit "$final_check_ec"
fi
check_passed="true"

if [[ ! -f "$task_gate_file" ]]; then
  echo "Missing completion gate file for ${task_id}: ${task_gate_file}" >&2
  task_failure_reason="missing_done_gate_file"
  task_exit_code="1"
  open_after_task="$(count_open_tasks)"
  emit_task_metrics
  exit 1
fi
done_gate_present="true"

if [[ "$(tr -d '\r\n' < "$task_gate_file")" != "DONE" ]]; then
  echo "Invalid gate content in ${task_gate_file}. Expected: DONE" >&2
  task_failure_reason="invalid_done_gate_content"
  task_exit_code="1"
  open_after_task="$(count_open_tasks)"
  emit_task_metrics
  exit 1
fi
done_gate_valid="true"

project_fingerprint_after="$(compute_project_fingerprint)"
if [[ "$project_fingerprint_before" == "$project_fingerprint_after" ]]; then
  if [[ "$preexisting_done_gate" == "1" ]]; then
    echo "No new in-project changes for ${task_id}, but an existing DONE gate was present. Syncing stale task status." >&2
  else
    echo "No substantive in-project file changes detected for ${task_id}. Refusing to mark task done." >&2
    task_failure_reason="no_substantive_project_changes"
    task_exit_code="1"
    open_after_task="$(count_open_tasks)"
    emit_task_metrics
    exit 1
  fi
fi

write_manifest "$manifest_after"
IFS=$'\t' read -r changed_files_count added_files_count removed_files_count modified_files_count \
  <<< "$(compare_manifest_counts_tsv "$manifest_before" "$manifest_after")"
write_changed_paths_file "$manifest_before" "$manifest_after" "$changed_paths_file"

if is_truthy "$REQUIRED_TEST_TOUCH_GATE"; then
  required_test_touch_gate_enforced="true"
  if [[ "$preexisting_done_gate" == "1" && "${changed_files_count:-0}" == "0" ]]; then
    echo "Required test touch gate skipped for ${task_id}: preexisting DONE gate with no new file changes." >&2
    required_test_file_touched="true"
  elif (( required_test_files_count == 0 )); then
    echo "Task ${task_id} has no selector files resolvable from test field: ${task_tests}" >&2
    task_failure_reason="required_test_selector_parse_failed"
    task_exit_code="1"
    required_test_touch_failure_files="${task_tests}"
    open_after_task="$(count_open_tasks)"
    emit_task_metrics
    exit 1
  else
    required_test_file_touched="false"
    missing_required_files=()
    for required_file in "${required_test_files[@]}"; do
      if rg -n -x -F -- "$required_file" "$changed_paths_file" >/dev/null 2>&1; then
        required_test_file_touched="true"
      else
        missing_required_files+=("$required_file")
      fi
    done

    if [[ "$required_test_file_touched" != "true" ]]; then
      if selector_files_cover_required_specs "$task_specs" "${required_test_files[@]}"; then
        echo "Required test touch gate bypassed for ${task_id}: selector files already cover required spec IDs (${task_specs})." >&2
        required_test_file_touched="true"
      else
        required_test_touch_failure_files="$(printf '%s\n' "${missing_required_files[@]}" | paste -sd, -)"
        echo "Required test touch gate failed for ${task_id}; none of the selector files changed: ${required_test_touch_failure_files}" >&2
        task_failure_reason="required_test_file_not_touched"
        task_exit_code="1"
        open_after_task="$(count_open_tasks)"
        emit_task_metrics
        exit 1
      fi
    fi
  fi
else
  required_test_touch_gate_enforced="false"
fi

tmp_tasks="$(mktemp)"
if ! acquire_tasks_lock; then
  echo "Unable to acquire tasks lock at ${TASKS_LOCK_DIR}." >&2
  task_failure_reason="tasks_lock_timeout"
  task_exit_code="${EXIT_LOCK_CONFLICT:-6}"
  open_after_task="$(count_open_tasks)"
  emit_task_metrics
  exit "${EXIT_LOCK_CONFLICT:-6}"
fi
awk -v start="$task_line_num" '
  BEGIN { in_task = 0 }
  NR == start {
    sub(/^- \[[ xX]\]/, "- [x]")
    in_task = 1
  }
  NR > start && in_task && $0 ~ /^- \[[ xX]\] TASK-[0-9]+:/ {
    in_task = 0
  }
  in_task && $0 ~ /^  - status:/ {
    $0 = "  - status: done"
  }
  { print }
' "$TASKS_FILE" > "$tmp_tasks"
mv "$tmp_tasks" "$TASKS_FILE"
release_tasks_lock

history_entry="Automated loop completed ${task_id}: ${task_title}"
today="$(date +%Y-%m-%d)"

if [[ ! -f "$HISTORY_FILE" ]]; then
  {
    echo "# HISTORY"
    echo ""
    echo "## ${today}"
    echo "- ${history_entry}"
  } > "$HISTORY_FILE"
else
  tmp_history="$(mktemp)"
  awk -v date="$today" -v entry="- ${history_entry}" '
    BEGIN {
      seen_date = 0
      inserted = 0
      in_date_section = 0
    }
    {
      if ($0 == "## " date) {
        seen_date = 1
        in_date_section = 1
        print
        next
      }
      if (in_date_section && $0 ~ /^## / && !inserted) {
        print entry
        inserted = 1
        in_date_section = 0
      }
      print
    }
    END {
      if (seen_date && !inserted) {
        print entry
      } else if (!seen_date) {
        if (NR > 0) print ""
        print "## " date
        print entry
      }
    }
  ' "$HISTORY_FILE" > "$tmp_history"
  mv "$tmp_history" "$HISTORY_FILE"
fi

if [[ "$AUTO_COMMIT" == "1" ]]; then
  if [[ "$has_local_git_repo" != "1" ]]; then
    echo "Auto-commit skipped: no local .git repository at ${repo_root}."
    auto_commit_result="skipped_no_local_git"
  elif [[ "$repo_dirty_before" == "1" ]]; then
    echo "Auto-commit skipped: repository had existing uncommitted changes before run."
    auto_commit_result="skipped_repo_dirty_before"
  else
    git add -A
    if git diff --cached --quiet; then
      echo "Auto-commit skipped: no staged changes."
      auto_commit_result="skipped_no_staged_changes"
    else
      git commit -m "feat: complete ${task_id} - ${task_title}"
      echo "Committed: ${task_id}"
      auto_commit_result="committed"
    fi
  fi
fi

open_after_task="$(count_open_tasks)"
task_result="passed"
task_failure_reason="none"
task_exit_code="0"
emit_task_metrics

echo "Completed ${task_id} and marked it done in ${TASKS_FILE}."
