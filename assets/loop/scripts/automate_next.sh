#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Force color by default for operator loops unless explicitly overridden.
if [[ -z "${FORCE_COLOR:-}" ]]; then
  export FORCE_COLOR=1
fi

# Preserve run_next_task exit status with pipefail enabled.
"${script_dir}/run_next_task.sh" "$@" 2>&1 | "${script_dir}/colorize_loop_output.sh"
