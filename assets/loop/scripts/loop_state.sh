#!/usr/bin/env bash
# Shared loop state helpers for PID files, lock directories, and graceful waits.

loop_state_pid_is_live() {
  local pid="${1:-}"
  [[ "$pid" =~ ^[0-9]+$ ]] || return 1
  kill -0 "$pid" 2>/dev/null
}

loop_state_process_group_for_pid() {
  local pid="${1:-}"
  local pgid=""
  [[ "$pid" =~ ^[0-9]+$ ]] || return 0
  pgid="$(ps -o pgid= -p "$pid" 2>/dev/null | tr -d '[:space:]' || true)"
  case "$pgid" in
    ''|*[!0-9]*) return 0 ;;
    *) printf '%s\n' "$pgid" ;;
  esac
}

loop_state_read_pid_file() {
  local pid_file="${1:-}"
  local pid_value=""
  [[ -n "$pid_file" && -f "$pid_file" ]] || return 0
  pid_value="$(tr -d '[:space:]' < "$pid_file" 2>/dev/null || true)"
  case "$pid_value" in
    ''|*[!0-9]*) return 0 ;;
    *) printf '%s\n' "$pid_value" ;;
  esac
}

loop_state_write_pid_file() {
  local pid_file="${1:-}"
  local pid_value="${2:-}"
  [[ -n "$pid_file" ]] || return 1
  mkdir -p "$(dirname "$pid_file")"
  printf '%s\n' "$pid_value" > "$pid_file"
}

loop_state_remove_pid_file_if_owner() {
  local pid_file="${1:-}"
  local owner_pid="${2:-}"
  local current_pid=""
  current_pid="$(loop_state_read_pid_file "$pid_file")"
  if [[ -n "$current_pid" && "$current_pid" == "$owner_pid" ]]; then
    rm -f "$pid_file"
  fi
}

loop_state_lock_owner_pid() {
  local lock_dir="${1:-}"
  loop_state_read_pid_file "${lock_dir}/pid"
}

loop_state_prune_stale_lock_dir() {
  local lock_dir="${1:-}"
  local owner_pid=""
  [[ -d "$lock_dir" ]] || return 0
  owner_pid="$(loop_state_lock_owner_pid "$lock_dir")"
  if [[ -n "$owner_pid" ]] && loop_state_pid_is_live "$owner_pid"; then
    return 1
  fi
  rm -rf "$lock_dir" 2>/dev/null || true
  return 0
}

loop_state_try_acquire_lock_dir() {
  local lock_dir="${1:-}"
  local owner_pid="${2:-}"
  [[ -n "$lock_dir" ]] || return 1

  mkdir -p "$(dirname "$lock_dir")"
  if mkdir "$lock_dir" 2>/dev/null; then
    loop_state_write_pid_file "${lock_dir}/pid" "$owner_pid"
    return 0
  fi

  if loop_state_prune_stale_lock_dir "$lock_dir"; then
    if mkdir "$lock_dir" 2>/dev/null; then
      loop_state_write_pid_file "${lock_dir}/pid" "$owner_pid"
      return 0
    fi
  fi

  return 1
}

loop_state_release_lock_dir_if_owner() {
  local lock_dir="${1:-}"
  local owner_pid="${2:-}"
  local lock_owner=""
  [[ -d "$lock_dir" ]] || return 0
  lock_owner="$(loop_state_lock_owner_pid "$lock_dir")"
  if [[ -z "$lock_owner" || "$lock_owner" == "$owner_pid" ]]; then
    rm -rf "$lock_dir"
  fi
}

loop_state_wait_for_pids_to_exit() {
  local poll_seconds="${1:-2}"
  shift || true
  local pid=""
  local active=0

  while true; do
    active=0
    for pid in "$@"; do
      if loop_state_pid_is_live "$pid"; then
        active=1
        break
      fi
    done
    if [[ "$active" -eq 0 ]]; then
      return 0
    fi
    sleep "$poll_seconds"
  done
}
