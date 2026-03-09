#!/usr/bin/env bash
# Shared loop process detection helpers for run/stop orchestration scripts.

if [[ -z "${LOOP_STATE_LIB_SOURCED:-}" ]]; then
  loop_scan_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  loop_state_lib="${loop_scan_script_dir}/loop_state.sh"
  if [[ -f "$loop_state_lib" ]]; then
    # shellcheck disable=SC1090
    source "$loop_state_lib"
    LOOP_STATE_LIB_SOURCED=1
  fi
fi

loop_scan_collect_ignored_pids() {
  local ignored=":$$:"
  local cursor="$$"
  local parent=""

  if ! command -v ps >/dev/null 2>&1; then
    printf '%s\n' "$ignored"
    return 0
  fi

  while true; do
    parent="$(ps -o ppid= -p "$cursor" 2>/dev/null | tr -d '[:space:]' || true)"
    if [[ -z "$parent" || ! "$parent" =~ ^[0-9]+$ || "$parent" -le 1 ]]; then
      break
    fi
    ignored="${ignored}${parent}:"
    cursor="$parent"
  done
  printf '%s\n' "$ignored"
}

loop_scan_collect_ignored_process_groups() {
  local ignored=":"
  local cursor="$$"
  local parent=""
  local pgid=""

  while true; do
    pgid="$(loop_state_process_group_for_pid "$cursor")"
    if [[ -n "$pgid" && "$ignored" != *":${pgid}:"* ]]; then
      ignored="${ignored}${pgid}:"
    fi
    parent="$(ps -o ppid= -p "$cursor" 2>/dev/null | tr -d '[:space:]' || true)"
    if [[ -z "$parent" || ! "$parent" =~ ^[0-9]+$ || "$parent" -le 1 ]]; then
      break
    fi
    cursor="$parent"
  done
  printf '%s\n' "$ignored"
}

loop_scan_list_run_all_tasks_pids() {
  if ! command -v ps >/dev/null 2>&1; then
    return 0
  fi

  ps -ax -o pid=,pgid=,command= 2>/dev/null \
    | awk '
      function is_allowed_prefix(tok) {
        if (tok == "env") return 1
        if (tok == "sudo") return 1
        if (tok == "command") return 1
        if (tok == "nohup") return 1
        if (tok == "setsid") return 1
        if (tok ~ /^[A-Za-z_][A-Za-z0-9_]*=.*/) return 1
        if (tok ~ /^-[-[:alnum:]]*$/) return 1
        if (tok ~ /(^|\/)(bash|zsh|sh|ksh|dash)$/) return 1
        return 0
      }
      function is_loop_invocation(cmd,    n, i, j, token, target) {
        n = split(cmd, token, /[[:space:]]+/)
        target = 0
        for (i = 1; i <= n; i++) {
          if (token[i] ~ /(^|\/)scripts\/run_all_tasks\.sh$/ || token[i] == "run_all_tasks.sh") {
            target = i
            break
          }
        }
        if (target == 0) {
          return 0
        }
        for (j = 1; j < target; j++) {
          if (!is_allowed_prefix(token[j])) {
            return 0
          }
        }
        return 1
      }
      {
        pid = $1
        pgid = $2
        $1 = ""
        $2 = ""
        sub(/^[[:space:]]+/, "", $0)
        if (is_loop_invocation($0)) {
          print pid "\t" pgid
        }
      }
    '
}

loop_scan_list_live_run_all_tasks_pids() {
  local ignored_pids="${1:-}"
  local ignored_pgids="${2:-}"
  local seen=":"
  local pid=""
  local pgid=""

  while IFS=$'\t' read -r pid pgid; do
    [[ -z "$pid" ]] && continue
    [[ ! "$pid" =~ ^[0-9]+$ ]] && continue
    if [[ -n "$ignored_pids" && "$ignored_pids" == *":${pid}:"* ]]; then
      continue
    fi
    if [[ -n "$ignored_pgids" && -n "$pgid" && "$ignored_pgids" == *":${pgid}:"* ]]; then
      continue
    fi
    if [[ "$seen" == *":${pid}:"* ]]; then
      continue
    fi
    if loop_state_pid_is_live "$pid"; then
      seen="${seen}${pid}:"
      printf '%s\n' "$pid"
    fi
  done < <(loop_scan_list_run_all_tasks_pids || true)
}

loop_scan_collect_active_loop_pids() {
  local pid_file="${1:-}"
  local ignored_pids="${2:-}"
  local include_process_scan="${3:-1}"
  local ignored_pgids="${4:-}"
  local seen=":"
  local pid=""
  local pgid=""

  pid="$(loop_state_read_pid_file "$pid_file")"
  pgid="$(loop_state_process_group_for_pid "$pid")"
  if [[ -n "$pid" ]] && loop_state_pid_is_live "$pid"; then
    if [[ -n "$ignored_pids" && "$ignored_pids" == *":${pid}:"* ]]; then
      :
    elif [[ -n "$ignored_pgids" && -n "$pgid" && "$ignored_pgids" == *":${pgid}:"* ]]; then
      :
    else
      seen="${seen}${pid}:"
      printf '%s\n' "$pid"
    fi
  fi

  if [[ "$include_process_scan" != "1" ]]; then
    return 0
  fi

  while IFS= read -r pid; do
    [[ -z "$pid" ]] && continue
    if [[ "$seen" == *":${pid}:"* ]]; then
      continue
    fi
    seen="${seen}${pid}:"
    printf '%s\n' "$pid"
  done < <(loop_scan_list_live_run_all_tasks_pids "$ignored_pids" "$ignored_pgids")
}
