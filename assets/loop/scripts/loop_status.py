#!/usr/bin/env python3
"""Print current Ralph loop status from local state and metrics files."""

from __future__ import annotations

import argparse
import csv
import json
import os
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

DEFAULT_REPO_ROOT = Path(__file__).resolve().parents[1]


@dataclass
class BacklogStatus:
    done: int
    open: int
    total: int
    next_task: str
    next_phase: str


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def load_backlog_status(path: Path) -> BacklogStatus:
    done = 0
    open_count = 0
    next_task = "none"
    next_phase = "none"
    current_phase = "none"

    if not path.is_file():
        return BacklogStatus(
            done=0, open=0, total=0, next_task=next_task, next_phase=next_phase
        )

    with path.open(encoding="utf-8", errors="replace") as handle:
        for raw in handle:
            line = raw.rstrip("\n")
            if line.startswith("### "):
                current_phase = line[4:].strip() or "none"
                continue
            if line.startswith("- [x] TASK-") or line.startswith("- [X] TASK-"):
                done += 1
                continue
            if line.startswith("- [ ] TASK-"):
                open_count += 1
                if next_task == "none":
                    task_id = line.split(":", 1)[0].replace("- [ ] ", "").strip()
                    next_task = task_id or "none"
                    next_phase = current_phase or "none"

    return BacklogStatus(
        done=done,
        open=open_count,
        total=done + open_count,
        next_task=next_task,
        next_phase=next_phase,
    )


def read_jsonl(path: Path) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    if not path.is_file():
        return rows
    with path.open(encoding="utf-8", errors="replace") as handle:
        for raw in handle:
            raw = raw.strip()
            if not raw:
                continue
            try:
                data = json.loads(raw)
            except json.JSONDecodeError:
                continue
            if isinstance(data, dict):
                rows.append(data)
    return rows


def parse_pid_file(path: Path) -> int | None:
    if not path.is_file():
        return None
    try:
        raw = path.read_text(encoding="utf-8", errors="replace").strip()
        return int(raw) if raw else None
    except ValueError:
        return None


def pid_is_alive(pid: int) -> bool:
    if pid <= 0:
        return False
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def load_latest_session(metrics_root: Path) -> dict[str, Any] | None:
    sessions = read_jsonl(metrics_root / "loop_sessions.jsonl")
    if not sessions:
        return None

    starts: dict[str, dict[str, Any]] = {}
    ends: dict[str, dict[str, Any]] = {}
    for entry in sessions:
        session_id = str(entry.get("loop_session_id", "")).strip()
        if not session_id:
            continue
        event_type = entry.get("event_type")
        if event_type == "loop_session_start":
            starts[session_id] = entry
        elif event_type == "loop_session_end":
            ends[session_id] = entry

    if not starts:
        return None

    latest_start = max(
        starts.values(),
        key=lambda row: str(row.get("started_at_utc", row.get("ts_utc", ""))),
    )
    session_id = str(latest_start.get("loop_session_id", ""))
    merged = dict(latest_start)
    if session_id in ends:
        merged["session_end"] = ends[session_id]
    return merged


def load_last_event(path: Path, accepted_types: set[str]) -> dict[str, Any] | None:
    rows = read_jsonl(path)
    for row in reversed(rows):
        event_type = str(row.get("event_type", ""))
        if event_type in accepted_types:
            return row
    return None


def load_token_stats(path: Path) -> tuple[int, int, int]:
    if not path.is_file():
        return (0, 0, 0)
    rows = 0
    known_rows = 0
    token_sum = 0
    with path.open(encoding="utf-8", errors="replace", newline="") as handle:
        reader = csv.DictReader(handle)
        for row in reader:
            rows += 1
            raw = (row.get("tokens_used") or "").strip()
            if raw.isdigit():
                known_rows += 1
                token_sum += int(raw)
    return (rows, known_rows, token_sum)


def print_file_line_count(path: Path, label: str) -> None:
    if not path.is_file():
        print(f"- {label}: missing")
        return
    line_count = 0
    with path.open(encoding="utf-8", errors="replace") as handle:
        for _ in handle:
            line_count += 1
    size_kb = path.stat().st_size / 1024.0
    print(f"- {label}: {line_count} line(s), {size_kb:.1f} KiB")


def read_small_text(path: Path) -> str:
    if not path.is_file():
        return ""
    return path.read_text(encoding="utf-8", errors="replace").strip()


def read_json_file(path: Path) -> dict[str, Any] | None:
    if not path.is_file():
        return None
    try:
        obj = json.loads(path.read_text(encoding="utf-8", errors="replace"))
    except json.JSONDecodeError:
        return None
    if isinstance(obj, dict):
        return obj
    return None


def directory_size_bytes(root: Path) -> int:
    if not root.exists():
        return 0
    total = 0
    for current, _, files in os.walk(root):
        current_root = Path(current)
        for name in files:
            file_path = current_root / name
            try:
                total += file_path.stat().st_size
            except OSError:
                continue
    return total


def resolve_path(
    explicit: str | None, env_name: str, fallback: Path, repo_root: Path
) -> Path:
    candidate = explicit or os.environ.get(env_name, "")
    if not candidate:
        return fallback
    value = Path(candidate)
    if not value.is_absolute():
        value = repo_root / value
    return value.resolve()


def main() -> int:
    parser = argparse.ArgumentParser(description="Print a Ralph loop status snapshot.")
    parser.add_argument("--repo-root", default=str(DEFAULT_REPO_ROOT))
    parser.add_argument("--tasks-file")
    parser.add_argument("--state-root")
    parser.add_argument("--metrics-root")
    args = parser.parse_args()

    repo_root = Path(args.repo_root).resolve()
    tasks_file = resolve_path(
        args.tasks_file, "TASKS_FILE", repo_root / "tasks.md", repo_root
    )
    state_root = resolve_path(
        args.state_root, "STATE_ROOT", repo_root / ".ralph" / "state", repo_root
    )
    metrics_root = resolve_path(
        args.metrics_root,
        "METRICS_ROOT",
        repo_root / ".ralph" / "metrics",
        repo_root,
    )

    backlog = load_backlog_status(tasks_file)
    pid_file = state_root / "run_all_tasks.pid"
    stop_file = state_root / "stop-after-current-task"
    stop_reason_file = state_root / "last_stop_reason"
    checkpoint_file = state_root / "loop_checkpoint.json"
    checkpoint_payload = read_json_file(checkpoint_file)
    stop_reason_value = read_small_text(stop_reason_file) or "none"
    loop_pid = parse_pid_file(pid_file)
    loop_alive = pid_is_alive(loop_pid) if loop_pid is not None else False
    latest_session = load_latest_session(metrics_root)
    last_task_event = load_last_event(
        metrics_root / "task_runs.jsonl",
        {"task_attempt", "task_detail", "ralph_iteration"},
    )
    last_review_event = load_last_event(
        metrics_root / "review_runs.jsonl",
        {"review_checkpoint", "loop_review_checkpoint"},
    )
    token_rows, token_known_rows, token_sum = load_token_stats(
        metrics_root / "token_ledger.csv"
    )

    print(f"Loop status snapshot (UTC): {utc_now_iso()}")
    print("")
    print("Backlog")
    print(f"- Completed: {backlog.done}/{backlog.total}")
    print(f"- Open: {backlog.open}")
    print(f"- Next task: {backlog.next_task}")
    print(f"- Next phase: {backlog.next_phase}")
    print("")
    print("Process State")
    if loop_pid is None:
        print(f"- PID file: missing ({pid_file})")
        print("- Active loop: no")
    else:
        print(f"- PID file: {pid_file} -> {loop_pid}")
        print(f"- Active loop: {'yes' if loop_alive else 'no'}")
    print(f"- Stop requested: {'yes' if stop_file.is_file() else 'no'} ({stop_file})")
    print(f"- Last stop reason: {stop_reason_value} ({stop_reason_file})")
    if checkpoint_payload:
        print(
            "- Checkpoint: "
            f"iteration={checkpoint_payload.get('iteration', '')} "
            f"retry_task={checkpoint_payload.get('retry_task_id', '') or 'none'} "
            f"review_retry={checkpoint_payload.get('review_retry_count', '')} "
            f"updated={checkpoint_payload.get('updated_at_utc', '')}"
        )
    else:
        print(f"- Checkpoint: none ({checkpoint_file})")
    print("")
    print("Latest Session")
    if not latest_session:
        print("- No loop session events found")
    else:
        end_event = latest_session.get("session_end")
        print(f"- Session ID: {latest_session.get('loop_session_id', '')}")
        print(
            f"- Started: {latest_session.get('started_at_utc', latest_session.get('ts_utc', ''))}"
        )
        if isinstance(end_event, dict):
            print(
                f"- Finished: {end_event.get('finished_at_utc', end_event.get('ts_utc', ''))}"
            )
            print(f"- Stop reason: {end_event.get('stop_reason', '')}")
            print(f"- Final exit: {end_event.get('final_exit_code', '')}")
            print(
                f"- Iterations attempted: {end_event.get('iterations_attempted', '')}"
            )
        else:
            print("- Finished: running or missing end event")
    print("")
    print("Recent Activity")
    if last_task_event:
        print(
            "- Last task event: "
            f"{last_task_event.get('event_type', '')} "
            f"task={last_task_event.get('task_id', '')} "
            f"result={last_task_event.get('result', last_task_event.get('status', ''))} "
            f"ts={last_task_event.get('ts_utc', '')}"
        )
    else:
        print("- Last task event: none")
    if last_review_event:
        print(
            "- Last review event: "
            f"{last_review_event.get('event_type', '')} "
            f"mode={last_review_event.get('mode', '')} "
            f"result={last_review_event.get('result', '')} "
            f"ts={last_review_event.get('ts_utc', '')}"
        )
    else:
        print("- Last review event: none")
    print(
        f"- Token rows: {token_rows} (known token rows: {token_known_rows}, sum: {token_sum})"
    )
    print("")
    print("Metrics Files")
    print_file_line_count(metrics_root / "loop_sessions.jsonl", "loop_sessions.jsonl")
    print_file_line_count(metrics_root / "task_runs.jsonl", "task_runs.jsonl")
    print_file_line_count(metrics_root / "review_runs.jsonl", "review_runs.jsonl")
    print_file_line_count(metrics_root / "token_ledger.csv", "token_ledger.csv")
    ralph_bytes = directory_size_bytes(repo_root / ".ralph")
    print(f"- .ralph disk usage: {ralph_bytes / (1024.0 * 1024.0):.2f} MiB")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
