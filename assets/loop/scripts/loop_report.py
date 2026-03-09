#!/usr/bin/env python3
"""Generate a markdown report for a Ralph loop session."""

from __future__ import annotations

import argparse
import csv
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[1]
TASKS_FILE = REPO_ROOT / "tasks.md"
METRICS_ROOT = REPO_ROOT / ".ralph" / "metrics"
DEFAULT_REPORT_DIR = REPO_ROOT / ".ralph" / "reports"


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate a loop-session markdown report."
    )
    parser.add_argument(
        "--session",
        default="",
        help="Loop session id (default: latest session in loop_sessions.jsonl).",
    )
    parser.add_argument(
        "--output",
        default="",
        help="Output markdown path (default: .ralph/reports/loop-report-<session>.md).",
    )
    return parser.parse_args()


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


def get_latest_session_id(loop_sessions: list[dict[str, Any]]) -> str:
    starts = [
        row for row in loop_sessions if row.get("event_type") == "loop_session_start"
    ]
    if not starts:
        return ""
    latest = max(
        starts, key=lambda row: str(row.get("started_at_utc", row.get("ts_utc", "")))
    )
    return str(latest.get("loop_session_id", "")).strip()


def safe_int(value: Any) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return 0


def parse_backlog(path: Path) -> tuple[int, int, int, str, str]:
    done = 0
    open_count = 0
    next_task = "none"
    next_phase = "none"
    phase = "none"
    if not path.is_file():
        return (0, 0, 0, next_task, next_phase)
    with path.open(encoding="utf-8", errors="replace") as handle:
        for raw in handle:
            line = raw.rstrip("\n")
            if line.startswith("### "):
                phase = line[4:].strip() or "none"
                continue
            if line.startswith("- [x] TASK-") or line.startswith("- [X] TASK-"):
                done += 1
            elif line.startswith("- [ ] TASK-"):
                open_count += 1
                if next_task == "none":
                    next_task = (
                        line.split(":", 1)[0].replace("- [ ] ", "").strip() or "none"
                    )
                    next_phase = phase
    return (done, open_count, done + open_count, next_task, next_phase)


def md_table(headers: list[str], rows: list[list[str]]) -> str:
    if not rows:
        return "_No rows._"
    header_row = "| " + " | ".join(headers) + " |"
    divider_row = "| " + " | ".join(["---"] * len(headers)) + " |"
    data_rows = ["| " + " | ".join(row) + " |" for row in rows]
    return "\n".join([header_row, divider_row, *data_rows])


def load_token_rows(session_id: str, path: Path) -> list[dict[str, str]]:
    if not path.is_file():
        return []
    out: list[dict[str, str]] = []
    with path.open(encoding="utf-8", errors="replace", newline="") as handle:
        for row in csv.DictReader(handle):
            if (row.get("session_id") or "").strip() == session_id:
                out.append(row)
    return out


def main() -> int:
    args = parse_args()
    loop_sessions = read_jsonl(METRICS_ROOT / "loop_sessions.jsonl")
    if not loop_sessions:
        print("No loop session metrics found at .ralph/metrics/loop_sessions.jsonl")
        return 1

    session_id = args.session.strip() or get_latest_session_id(loop_sessions)
    if not session_id:
        print("No loop session start events found.")
        return 1

    start_event = None
    end_event = None
    for row in loop_sessions:
        if str(row.get("loop_session_id", "")).strip() != session_id:
            continue
        if row.get("event_type") == "loop_session_start":
            start_event = row
        elif row.get("event_type") == "loop_session_end":
            end_event = row

    if start_event is None:
        print(f"Session id not found in loop session starts: {session_id}")
        return 1

    task_rows = [
        row
        for row in read_jsonl(METRICS_ROOT / "task_runs.jsonl")
        if str(row.get("loop_session_id", "")).strip() == session_id
    ]
    review_rows = [
        row
        for row in read_jsonl(METRICS_ROOT / "review_runs.jsonl")
        if str(row.get("loop_session_id", "")).strip() == session_id
    ]
    token_rows = load_token_rows(session_id, METRICS_ROOT / "token_ledger.csv")

    task_attempts = [
        row for row in task_rows if row.get("event_type") == "task_attempt"
    ]
    task_details = [row for row in task_rows if row.get("event_type") == "task_detail"]
    watchdog_events = [
        row for row in task_rows if row.get("event_type") == "loop_watchdog_warning"
    ]

    attempts_passed = sum(
        1 for row in task_attempts if str(row.get("result", "")) == "passed"
    )
    attempts_failed = sum(
        1 for row in task_attempts if str(row.get("result", "")) != "passed"
    )
    completed_count = sum(safe_int(row.get("completed_count")) for row in task_attempts)
    detail_passed = sum(
        1 for row in task_details if str(row.get("result", "")) == "passed"
    )
    detail_failed = sum(
        1 for row in task_details if str(row.get("result", "")) != "passed"
    )

    known_token_rows = [
        row for row in token_rows if (row.get("tokens_used") or "").strip().isdigit()
    ]
    token_sum = sum(int(row["tokens_used"]) for row in known_token_rows)

    review_pass = sum(
        1
        for row in review_rows
        if str(row.get("result", "")).lower() in {"pass", "passed"}
    )
    review_fail = sum(
        1
        for row in review_rows
        if str(row.get("result", "")).lower() in {"fail", "failed"}
    )

    done_count, open_count, total_count, next_task, next_phase = parse_backlog(
        TASKS_FILE
    )

    top_task_rows = sorted(
        task_details,
        key=lambda row: safe_int(row.get("duration_s")),
        reverse=True,
    )[:10]

    recent_attempt_rows = task_attempts[-10:]
    recent_review_rows = review_rows[-10:]

    summary_lines = [
        f"# Loop Session Report: `{session_id}`",
        "",
        f"- Generated UTC: {utc_now_iso()}",
        "",
        "## Session Summary",
        f"- Started: {start_event.get('started_at_utc', start_event.get('ts_utc', ''))}",
        (
            f"- Finished: {end_event.get('finished_at_utc', end_event.get('ts_utc', ''))}"
            if end_event
            else "- Finished: running or missing end event"
        ),
        f"- Stop reason: {(end_event or {}).get('stop_reason', 'unknown')}",
        f"- Final exit code: {(end_event or {}).get('final_exit_code', 'unknown')}",
        f"- Iterations attempted: {(end_event or {}).get('iterations_attempted', 'unknown')}",
        f"- Open tasks remaining at end: {(end_event or {}).get('open_tasks_remaining', 'unknown')}",
        "",
        "## Backlog Snapshot",
        f"- Completed: {done_count}/{total_count}",
        f"- Open: {open_count}",
        f"- Next task: {next_task}",
        f"- Next phase: {next_phase}",
        "",
        "## Task Metrics",
        f"- `task_attempt` rows: {len(task_attempts)} (passed={attempts_passed}, failed={attempts_failed})",
        f"- Completed tasks reported by attempts: {completed_count}",
        f"- `task_detail` rows: {len(task_details)} (passed={detail_passed}, failed={detail_failed})",
        f"- Watchdog warnings: {len(watchdog_events)}",
        "",
        "### Recent Task Attempts",
        md_table(
            [
                "ts_utc",
                "task_id",
                "phase",
                "result",
                "duration_s",
                "completed_count",
                "exit_code",
            ],
            [
                [
                    str(row.get("ts_utc", "")),
                    str(row.get("task_id", "")),
                    str(row.get("phase", "")),
                    str(row.get("result", "")),
                    str(row.get("duration_s", "")),
                    str(row.get("completed_count", "")),
                    str(row.get("exit_code", "")),
                ]
                for row in recent_attempt_rows
            ],
        ),
        "",
        "### Slowest Task Details",
        md_table(
            [
                "task_id",
                "result",
                "duration_s",
                "agent_time_s",
                "check_time_s",
                "failure_reason",
            ],
            [
                [
                    str(row.get("task_id", "")),
                    str(row.get("result", "")),
                    str(row.get("duration_s", "")),
                    str(row.get("agent_time_s", "")),
                    str(row.get("check_time_s", "")),
                    str(row.get("failure_reason", "")),
                ]
                for row in top_task_rows
            ],
        ),
        "",
        "## Review Metrics",
        f"- Review rows: {len(review_rows)} (pass={review_pass}, fail={review_fail})",
        "",
        "### Recent Review Checkpoints",
        md_table(
            [
                "ts_utc",
                "mode",
                "result",
                "duration_s",
                "focus_task",
                "focus_phase",
                "final_exit_code",
            ],
            [
                [
                    str(row.get("ts_utc", "")),
                    str(row.get("mode", "")),
                    str(row.get("result", "")),
                    str(row.get("duration_s", "")),
                    str(row.get("focus_task", row.get("task_id", ""))),
                    str(row.get("focus_phase", row.get("phase", ""))),
                    str(row.get("final_exit_code", row.get("exit_code", ""))),
                ]
                for row in recent_review_rows
            ],
        ),
        "",
        "## Token Ledger",
        f"- Rows for session: {len(token_rows)}",
        f"- Rows with numeric token snapshots: {len(known_token_rows)}",
        f"- Sum of numeric token snapshots: {token_sum}",
    ]

    output_path = (
        Path(args.output).expanduser()
        if args.output
        else DEFAULT_REPORT_DIR / f"loop-report-{session_id}.md"
    )
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text("\n".join(summary_lines) + "\n", encoding="utf-8")

    print(f"Wrote loop session report: {output_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
