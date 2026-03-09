#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "Usage: $0 <project-root> [--force]"
  exit 1
fi

target_root="$1"
force="${2:-}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skill_root="$(cd "${script_dir}/.." && pwd)"
assets_root="${skill_root}/assets/loop"

if [[ ! -d "$target_root" ]]; then
  echo "Target project root does not exist: $target_root" >&2
  exit 1
fi

copy_file() {
  local src="$1"
  local dst="$2"
  mkdir -p "$(dirname "$dst")"
  if [[ -e "$dst" && "$force" != "--force" ]]; then
    echo "Skip existing file: $dst"
    return
  fi
  cp "$src" "$dst"
  echo "Installed: $dst"
}

copy_file "${assets_root}/ralph.sh" "${target_root}/ralph.sh"
copy_file "${assets_root}/agent.sh" "${target_root}/agent.sh"
copy_file "${assets_root}/reviewer.sh" "${target_root}/reviewer.sh"
copy_file "${assets_root}/PROMPT.md" "${target_root}/PROMPT.md"
copy_file "${assets_root}/REVIEW_PROMPT.md" "${target_root}/REVIEW_PROMPT.md"
copy_file "${assets_root}/ARCH_REVIEW_PROMPT.md" "${target_root}/ARCH_REVIEW_PROMPT.md"
copy_file "${assets_root}/auditor.sh" "${target_root}/auditor.sh"
copy_file "${assets_root}/AUDIT_PROMPT.md" "${target_root}/AUDIT_PROMPT.md"
copy_file "${assets_root}/scripts/run_next_task.sh" "${target_root}/scripts/run_next_task.sh"
copy_file "${assets_root}/scripts/run_all_tasks.sh" "${target_root}/scripts/run_all_tasks.sh"
copy_file "${assets_root}/scripts/run_review_exec.sh" "${target_root}/scripts/run_review_exec.sh"
copy_file "${assets_root}/scripts/run_audit_exec.sh" "${target_root}/scripts/run_audit_exec.sh"
copy_file "${assets_root}/scripts/agent_dispatcher.sh" "${target_root}/scripts/agent_dispatcher.sh"
copy_file "${assets_root}/scripts/exit_codes.sh" "${target_root}/scripts/exit_codes.sh"
copy_file "${assets_root}/scripts/checkpoint_exec_lib.sh" "${target_root}/scripts/checkpoint_exec_lib.sh"
copy_file "${assets_root}/scripts/loop_state.sh" "${target_root}/scripts/loop_state.sh"
copy_file "${assets_root}/scripts/loop_process_scan.sh" "${target_root}/scripts/loop_process_scan.sh"
copy_file "${assets_root}/scripts/timeout_wrapper.py" "${target_root}/scripts/timeout_wrapper.py"
copy_file "${assets_root}/scripts/stop_loop_gracefully.sh" "${target_root}/scripts/stop_loop_gracefully.sh"
copy_file "${assets_root}/scripts/metrics_lib.sh" "${target_root}/scripts/metrics_lib.sh"
copy_file "${assets_root}/scripts/colorize_loop_output.sh" "${target_root}/scripts/colorize_loop_output.sh"
copy_file "${assets_root}/scripts/automate_next.sh" "${target_root}/scripts/automate_next.sh"
copy_file "${assets_root}/scripts/loop_status.py" "${target_root}/scripts/loop_status.py"
copy_file "${assets_root}/scripts/loop_report.py" "${target_root}/scripts/loop_report.py"
copy_file "${assets_root}/scripts/loop_checklist.py" "${target_root}/scripts/loop_checklist.py"
copy_file "${assets_root}/scripts/extract_findings.py" "${target_root}/scripts/extract_findings.py"
copy_file "${assets_root}/scripts/process_findings.py" "${target_root}/scripts/process_findings.py"
copy_file "${assets_root}/scripts/prune_loop_logs.sh" "${target_root}/scripts/prune_loop_logs.sh"

chmod +x \
  "${target_root}/ralph.sh" \
  "${target_root}/agent.sh" \
  "${target_root}/reviewer.sh" \
  "${target_root}/auditor.sh" \
  "${target_root}/scripts/run_next_task.sh" \
  "${target_root}/scripts/run_all_tasks.sh" \
  "${target_root}/scripts/run_review_exec.sh" \
  "${target_root}/scripts/run_audit_exec.sh" \
  "${target_root}/scripts/agent_dispatcher.sh" \
  "${target_root}/scripts/exit_codes.sh" \
  "${target_root}/scripts/checkpoint_exec_lib.sh" \
  "${target_root}/scripts/loop_state.sh" \
  "${target_root}/scripts/loop_process_scan.sh" \
  "${target_root}/scripts/timeout_wrapper.py" \
  "${target_root}/scripts/stop_loop_gracefully.sh" \
  "${target_root}/scripts/metrics_lib.sh" \
  "${target_root}/scripts/colorize_loop_output.sh" \
  "${target_root}/scripts/automate_next.sh" \
  "${target_root}/scripts/extract_findings.py" \
  "${target_root}/scripts/process_findings.py" \
  "${target_root}/scripts/prune_loop_logs.sh"

chmod +x \
  "${target_root}/scripts/loop_status.py" \
  "${target_root}/scripts/loop_report.py" \
  "${target_root}/scripts/loop_checklist.py"

echo ""
echo "Loop assets installed."
echo "Next:"
echo "1) Ensure Makefile automate-next/run-all-tasks targets call:"
echo "   ./scripts/automate_next.sh"
echo "   ./scripts/run_all_tasks.sh"
echo "2) Ensure Makefile review-exec/stop-loop-graceful targets call:"
echo "   ./scripts/run_review_exec.sh --mode quick"
echo "   ./scripts/stop_loop_gracefully.sh"
echo "3) Run: make check"
