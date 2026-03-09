#!/usr/bin/env bash
set -euo pipefail

# Shared metrics helpers for loop/session/task logging.

metrics_init() {
  METRICS_ROOT="${METRICS_ROOT:-.ralph/metrics}"
  LOOP_SESSIONS_LOG="${LOOP_SESSIONS_LOG:-${METRICS_ROOT}/loop_sessions.jsonl}"
  TASK_RUNS_LOG="${TASK_RUNS_LOG:-${METRICS_ROOT}/task_runs.jsonl}"
  REVIEW_RUNS_LOG="${REVIEW_RUNS_LOG:-${METRICS_ROOT}/review_runs.jsonl}"
  TOKEN_LEDGER_FILE="${TOKEN_LEDGER_FILE:-${METRICS_ROOT}/token_ledger.csv}"

  mkdir -p "$METRICS_ROOT"
  if [[ ! -f "$TOKEN_LEDGER_FILE" ]]; then
    printf '%s\n' "ts_utc,session_id,role,task_id,review_mode,tokens_used,codex_exit" > "$TOKEN_LEDGER_FILE"
  fi
}

metrics_now_utc() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

metrics_append_jsonl() {
  local file_path="$1"
  shift
  python3 - "$file_path" "$@" <<'PY'
import json
import re
import sys

file_path = sys.argv[1]
pairs = sys.argv[2:]
payload = {}

for pair in pairs:
    if "=" not in pair:
        continue
    key, value = pair.split("=", 1)
    value = value.strip()
    lower = value.lower()
    if lower == "true":
        payload[key] = True
    elif lower == "false":
        payload[key] = False
    elif lower == "null":
        payload[key] = None
    elif re.fullmatch(r"-?\d+", value):
        payload[key] = int(value)
    elif re.fullmatch(r"-?\d+\.\d+", value):
        payload[key] = float(value)
    else:
        payload[key] = value

with open(file_path, "a", encoding="utf-8") as handle:
    handle.write(json.dumps(payload, sort_keys=True) + "\n")
PY
}

metrics_extract_tokens_used() {
  local transcript_file="$1"
  python3 - "$transcript_file" <<'PY'
import re
import sys

path = sys.argv[1]
ansi = re.compile(r"\x1b\[[0-9;]*m")
try:
    lines = [ansi.sub("", line.rstrip("\n")) for line in open(path, encoding="utf-8", errors="ignore")]
except FileNotFoundError:
    print("")
    raise SystemExit(0)

token_value = ""
for idx, line in enumerate(lines):
    if line.strip().lower() != "tokens used":
        continue
    for candidate in lines[idx + 1 : idx + 6]:
        value = candidate.strip().replace(",", "")
        if re.fullmatch(r"\d+", value):
            token_value = value
            break

print(token_value)
PY
}

metrics_append_token_row() {
  metrics_init
  local role="$1"
  local task_id="${2:-}"
  local review_mode="${3:-}"
  local tokens_used="${4:-}"
  local codex_exit="${5:-}"
  local ts_utc
  ts_utc="$(metrics_now_utc)"
  local session_id="${LOOP_SESSION_ID:-}"
  python3 - "$TOKEN_LEDGER_FILE" "$ts_utc" "$session_id" "$role" "$task_id" "$review_mode" "$tokens_used" "$codex_exit" <<'PY'
import csv
import sys

file_path, ts_utc, session_id, role, task_id, review_mode, tokens_used, codex_exit = sys.argv[1:]
with open(file_path, "a", newline="", encoding="utf-8") as handle:
    writer = csv.writer(handle)
    writer.writerow([ts_utc, session_id, role, task_id, review_mode, tokens_used, codex_exit])
PY
}

metrics_extract_check_summary_tsv() {
  local check_output_file="$1"
  python3 - "$check_output_file" <<'PY'
import re
import sys

path = sys.argv[1]
ansi = re.compile(r"\x1b\[[0-9;]*m")
text = ""
try:
    text = open(path, encoding="utf-8", errors="ignore").read()
except FileNotFoundError:
    pass

clean = ansi.sub("", text)
lines = clean.splitlines()

def first_int(pattern: str):
    match = re.search(pattern, clean, flags=re.IGNORECASE)
    return int(match.group(1)) if match else ""

tests_run = first_int(r"\bRan\s+(\d+)\s+tests?\b")
passed_count = first_int(r"\b(\d+)\s+passed\b")
failed_count = first_int(r"\b(\d+)\s+failed\b")
skipped_count = first_int(r"\b(\d+)\s+skipped\b")
error_count = first_int(r"\b(\d+)\s+errors?\b")

failed_match = re.search(r"\bFAILED\s*\(([^)]+)\)", clean, flags=re.IGNORECASE)
if failed_match:
    details = failed_match.group(1)
    if failed_count == "":
        failure_m = re.search(r"failures?=(\d+)", details, flags=re.IGNORECASE)
        if failure_m:
            failed_count = int(failure_m.group(1))
    if error_count == "":
        error_m = re.search(r"errors?=(\d+)", details, flags=re.IGNORECASE)
        if error_m:
            error_count = int(error_m.group(1))
    if skipped_count == "":
        skip_m = re.search(r"skipped=(\d+)", details, flags=re.IGNORECASE)
        if skip_m:
            skipped_count = int(skip_m.group(1))

ok = bool(re.search(r"(^|\n)\s*OK\b", clean))
if not ok and passed_count != "" and (failed_count in ("", 0)) and (error_count in ("", 0)):
    ok = True

error_patterns = [
    r"^FAILED[^\n]*$",
    r"^ERROR[^\n]*$",
    r"^E\s{2,}.*$",
    r"^Traceback \(most recent call last\):$",
    r"AssertionError.*$",
]
top_error = ""
for line in lines:
    stripped = line.strip()
    if not stripped:
        continue
    for pattern in error_patterns:
        if re.search(pattern, stripped):
            top_error = stripped[:240]
            break
    if top_error:
        break

if not top_error:
    for line in lines:
        stripped = line.strip()
        if re.search(r"\b(error|failed|exception)\b", stripped, flags=re.IGNORECASE):
            top_error = stripped[:240]
            break

fields = [
    str(tests_run),
    str(passed_count),
    str(failed_count),
    str(skipped_count),
    "true" if ok else "false",
    top_error.replace("\t", " ") if top_error else "",
]
print("\t".join(fields))
PY
}

metrics_write_manifest() {
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

metrics_compare_manifests_tsv() {
  local before_manifest="$1"
  local after_manifest="$2"
  python3 - "$before_manifest" "$after_manifest" <<'PY'
import sys

before_file, after_file = sys.argv[1], sys.argv[2]

def load(path):
    data = {}
    try:
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
    except FileNotFoundError:
        return {}
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
