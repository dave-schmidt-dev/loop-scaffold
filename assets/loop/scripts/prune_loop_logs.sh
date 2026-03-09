#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=".ralph/logs"
RETENTION_DAYS="${LOG_PRUNE_DAYS:-14}"
MAX_MB="${LOG_PRUNE_MAX_MB:-1024}"
MIN_KEEP_FILES="${LOG_PRUNE_MIN_KEEP:-200}"
DRY_RUN="0"
QUIET="0"

usage() {
  cat <<'USAGE'
Usage: ./scripts/prune_loop_logs.sh [options]

Options:
  --root DIR        Root log directory (default: .ralph/logs)
  --days N          Keep files newer than N days when possible (default: 14)
  --max-mb N        Cap retained log size in MiB (default: 1024)
  --min-keep N      Keep at least N newest files (default: 200)
  --dry-run         Print what would be deleted without deleting files
  --quiet           Suppress informational output
  -h, --help        Show help

Environment overrides:
  LOG_PRUNE_DAYS, LOG_PRUNE_MAX_MB, LOG_PRUNE_MIN_KEEP
USAGE
}

is_non_negative_int() {
  local value="${1:-}"
  case "$value" in
    ""|*[!0-9]*) return 1 ;;
    *) return 0 ;;
  esac
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT_DIR="$2"; shift 2 ;;
    --days) RETENTION_DAYS="$2"; shift 2 ;;
    --max-mb) MAX_MB="$2"; shift 2 ;;
    --min-keep) MIN_KEEP_FILES="$2"; shift 2 ;;
    --dry-run) DRY_RUN="1"; shift ;;
    --quiet) QUIET="1"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

if ! is_non_negative_int "$RETENTION_DAYS"; then
  echo "Invalid --days value: ${RETENTION_DAYS}" >&2
  exit 2
fi
if ! is_non_negative_int "$MAX_MB"; then
  echo "Invalid --max-mb value: ${MAX_MB}" >&2
  exit 2
fi
if ! is_non_negative_int "$MIN_KEEP_FILES"; then
  echo "Invalid --min-keep value: ${MIN_KEEP_FILES}" >&2
  exit 2
fi

python3 - "$ROOT_DIR" "$RETENTION_DAYS" "$MAX_MB" "$MIN_KEEP_FILES" "$DRY_RUN" "$QUIET" <<'PY'
from __future__ import annotations

import os
import sys
import time
from pathlib import Path

root = Path(sys.argv[1]).resolve()
retention_days = int(sys.argv[2])
max_mb = int(sys.argv[3])
min_keep_files = int(sys.argv[4])
dry_run = sys.argv[5] == "1"
quiet = sys.argv[6] == "1"

if not root.exists():
    if not quiet:
        print(f"[log-prune] root missing: {root}")
    raise SystemExit(0)

if not root.is_dir():
    print(f"[log-prune] root is not a directory: {root}", file=sys.stderr)
    raise SystemExit(1)

now = int(time.time())
cutoff = now - (retention_days * 86400)
max_bytes = max_mb * 1024 * 1024

files: list[tuple[int, int, Path]] = []
for dirpath, _, filenames in os.walk(root):
    for name in filenames:
        path = Path(dirpath) / name
        try:
            stat = path.stat()
        except OSError:
            continue
        files.append((int(stat.st_mtime), int(stat.st_size), path))

if not files:
    if not quiet:
        print(f"[log-prune] no files under {root}")
    raise SystemExit(0)

files.sort(key=lambda item: item[0], reverse=True)

keep: list[tuple[int, int, Path]] = []
drop: list[tuple[int, int, Path]] = []
retained_bytes = 0

for index, item in enumerate(files):
    mtime, size, path = item
    if index < min_keep_files:
        keep.append(item)
        retained_bytes += size
        continue

    old_enough = mtime < cutoff
    would_exceed_cap = (retained_bytes + size) > max_bytes
    if old_enough or would_exceed_cap:
        drop.append(item)
    else:
        keep.append(item)
        retained_bytes += size

deleted_count = 0
freed_bytes = 0

if dry_run:
    deleted_count = len(drop)
    freed_bytes = sum(size for _, size, _ in drop)
else:
    for _, size, path in drop:
        try:
            path.unlink()
            deleted_count += 1
            freed_bytes += size
        except OSError:
            continue

    # Remove empty directories from deepest to shallowest.
    for dirpath, dirnames, filenames in os.walk(root, topdown=False):
        if dirnames or filenames:
            continue
        if Path(dirpath) == root:
            continue
        try:
            Path(dirpath).rmdir()
        except OSError:
            pass

total_bytes = sum(size for _, size, _ in files)
remaining_bytes = max(total_bytes - freed_bytes, 0)
freed_mb = freed_bytes / (1024 * 1024)
remaining_mb = remaining_bytes / (1024 * 1024)

if not quiet or deleted_count > 0:
    mode = "dry-run" if dry_run else "applied"
    print(
        f"[log-prune] {mode} root={root} files_total={len(files)} "
        f"deleted={deleted_count} kept={len(files) - deleted_count} "
        f"freed_mb={freed_mb:.2f} remaining_mb={remaining_mb:.2f}"
    )
PY
