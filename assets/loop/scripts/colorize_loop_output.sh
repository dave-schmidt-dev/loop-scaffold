#!/usr/bin/env bash
set -euo pipefail

# Colorize Ralph/Codex loop output from stdin.
# Usage:
#   some_command 2>&1 | ./scripts/colorize_loop_output.sh

use_color="0"
if [[ "${FORCE_COLOR:-}" == "1" ]]; then
  use_color="1"
elif [[ "${FORCE_COLOR:-}" == "0" ]]; then
  use_color="0"
elif [[ -n "${NO_COLOR:-}" ]]; then
  use_color="0"
elif [[ -t 1 || -t 2 ]]; then
  use_color="1"
fi

if [[ "$use_color" != "1" ]]; then
  cat
  exit 0
fi

RESET=$'\033[0m'
BOLD=$'\033[1m'

BLUE=$'\033[34m'
CYAN=$'\033[36m'
MAGENTA=$'\033[35m'
GREEN=$'\033[32m'
YELLOW=$'\033[33m'
RED=$'\033[31m'

awk \
  -v RESET="$RESET" \
  -v BOLD="$BOLD" \
  -v BLUE="$BLUE" \
  -v CYAN="$CYAN" \
  -v MAGENTA="$MAGENTA" \
  -v GREEN="$GREEN" \
  -v YELLOW="$YELLOW" \
  -v RED="$RED" \
  '
function paint(color, text) {
  print BOLD color text RESET
  fflush()
}

{
  line = $0
  lower = tolower(line)

  if (line == "DONE" || line == "REVIEW_PASS") {
    paint(GREEN, line)
    next
  }

  if (line == "REVIEW_FAIL") {
    paint(RED, line)
    next
  }

  if (lower ~ /(error|failed|traceback|exception|syntax error|no backlog progress detected|max iterations reached|missing completion gate file|invalid gate content)/) {
    paint(RED, line)
    next
  }

  if (lower ~ /(warning|warn|retry|fallback|still running|stopped after|max_tasks)/) {
    paint(YELLOW, line)
    next
  }

  is_blue = 0
  if (line ~ /^===[[:space:]]/) is_blue = 1
  if (line ~ /^Running[[:space:]]TASK-/) is_blue = 1
  if (line ~ /^Spec[[:space:]]refs:/) is_blue = 1
  if (line ~ /^Test[[:space:]]selectors:/) is_blue = 1
  if (line ~ /^Logs:/) is_blue = 1
  if (line ~ /^Check[[:space:]]output[[:space:]]saved[[:space:]]to:/) is_blue = 1
  if (line ~ /^Running[[:space:]]agent[[:space:]]command:/) is_blue = 1
  if (line ~ /^Reviewer[[:space:]]command:/) is_blue = 1
  if (line ~ /^Log[[:space:]]file:/) is_blue = 1
  if (line ~ /\[agent\.sh\]/) is_blue = 1
  if (line ~ /\[reviewer\.sh\]/) is_blue = 1
  if (line ~ /\[lint-agent\]/) is_blue = 1
  if (line ~ /\[lint-baseline\]/) is_blue = 1
  if (is_blue) {
    paint(BLUE, line)
    next
  }

  if (line ~ /\/bin\/(zsh|bash)[[:space:]]-lc[[:space:]]'\''/ || line ~ /^\$[[:space:]]/) {
    paint(MAGENTA, line)
    next
  }

  is_cyan = 0
  if (line ~ /^I[[:space:]]/) is_cyan = 1
  if (line ~ /^I.?m[[:space:]]/) is_cyan = 1
  if (line ~ /^Implemented[[:space:]]TASK-/) is_cyan = 1
  if (line ~ /^Validation:/) is_cyan = 1
  if (line ~ /^Gate[[:space:]]file:/) is_cyan = 1
  if (line ~ /^What[[:space:]]I[[:space:]]changed:/) is_cyan = 1
  if (is_cyan) {
    paint(CYAN, line)
    next
  }

  print line
  fflush()
}
'
