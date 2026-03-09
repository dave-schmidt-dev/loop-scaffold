#!/usr/bin/env python3
"""Process extracted findings and append remediation tasks."""

from __future__ import annotations

import argparse
import fcntl
import hashlib
import json
import re
import subprocess
import sys
import time
from contextlib import contextmanager
from pathlib import Path

SEVERITY_ORDER = {"low": 1, "medium": 2, "high": 3, "critical": 4}
TASK_LINE_RE = re.compile(r"^- \[[ xX]\] TASK-(\d+):")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Process findings and create remediation tasks."
    )
    parser.add_argument("--findings-file", required=True)
    parser.add_argument("--tasks-file", required=True)
    parser.add_argument("--summary-file", required=True)
    parser.add_argument("--source", required=True)
    parser.add_argument("--mode", required=True)
    parser.add_argument("--loop-session-id", default="")
    parser.add_argument("--default-spec", default="REQ-001")
    parser.add_argument(
        "--default-test",
        default="tests/spec/test_req_coverage.py::ReqCoverageTests.test_req_001",
    )
    parser.add_argument("--blocker-severity", default="medium")
    parser.add_argument("--create-low-issues", action="store_true")
    parser.add_argument("--create-accepted-risk-issues", action="store_true")
    parser.add_argument(
        "--github-repo",
        default="",
        help="Explicit owner/repo for gh issue creation. Required when creating issues.",
    )
    parser.add_argument("--dry-run", action="store_true")
    return parser.parse_args()


def normalize_severity(value: str | None) -> str:
    if not value:
        return "medium"
    normalized = str(value).strip().lower()
    return normalized if normalized in SEVERITY_ORDER else "medium"


def load_findings(path: Path) -> tuple[list[dict[str, object]], int]:
    findings: list[dict[str, object]] = []
    malformed = 0
    if not path.is_file():
        return findings, malformed

    for index, line in enumerate(
        path.read_text(encoding="utf-8", errors="ignore").splitlines(), start=1
    ):
        line = line.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
        except json.JSONDecodeError as exc:
            malformed += 1
            print(
                f"[process_findings] WARNING: malformed JSONL line {index} in {path}: {exc}",
                file=sys.stderr,
            )
            continue
        if isinstance(obj, dict):
            findings.append(obj)
    return findings, malformed


def next_task_id(tasks_text: str) -> int:
    max_id = 0
    for line in tasks_text.splitlines():
        match = TASK_LINE_RE.match(line)
        if match:
            max_id = max(max_id, int(match.group(1)))
    return max_id + 1


def pick_spec(task_link: str, default_spec: str) -> str:
    req_match = re.search(r"REQ-\d+", task_link or "", re.IGNORECASE)
    if req_match:
        return req_match.group(0).upper()
    return default_spec


def short_title(value: str, limit: int = 110) -> str:
    one_line = re.sub(r"\s+", " ", (value or "")).strip()
    if not one_line:
        one_line = "Address audit finding"
    return (
        one_line if len(one_line) <= limit else one_line[: limit - 3].rstrip() + "..."
    )


def finding_fingerprint(finding: dict[str, object]) -> str:
    raw = "|".join(
        [
            str(finding.get("title", "")),
            str(finding.get("file", "")),
            str(finding.get("severity", "")),
            str(finding.get("evidence", ""))[:200],
        ]
    )
    return hashlib.sha1(raw.encode("utf-8", errors="ignore")).hexdigest()[:8]


def maybe_create_github_issue(title: str, body: str, repo: str) -> bool:
    if not shutil_which("gh"):
        return False
    if not repo.strip():
        return False
    cmd = ["gh", "issue", "create", "--repo", repo, "--title", title, "--body", body]
    try:
        subprocess.run(
            cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )
    except Exception:
        return False
    return True


def shutil_which(binary: str) -> str | None:
    from shutil import which

    return which(binary)


def render_task_block(
    task_id: int,
    title: str,
    spec: str,
    test_selector: str,
    marker: str,
) -> str:
    return (
        f"\n- [ ] TASK-{task_id:03d}: {title} [{marker}]\n"
        f"  - spec: {spec}\n"
        f"  - test: {test_selector}\n"
        f"  - owner: unassigned\n"
        f"  - status: todo\n"
    )


def ensure_findings_backlog_header(tasks_text: str) -> str:
    if "## Findings Backlog" in tasks_text:
        return tasks_text
    return tasks_text.rstrip() + "\n\n## Findings Backlog\n"


def append_task_block(
    tasks_file: Path,
    task_id: int,
    title: str,
    spec: str,
    test_selector: str,
    marker: str,
) -> str:
    tasks_text = tasks_file.read_text(encoding="utf-8")
    tasks_text = ensure_findings_backlog_header(tasks_text)
    tasks_text += render_task_block(task_id, title, spec, test_selector, marker)
    tasks_file.write_text(tasks_text, encoding="utf-8")
    return tasks_text


@contextmanager
def tasks_file_lock(lock_path: Path, timeout_seconds: float = 10.0):
    lock_path.parent.mkdir(parents=True, exist_ok=True)
    with lock_path.open("a+", encoding="utf-8") as lock_handle:
        deadline = time.time() + max(0.1, timeout_seconds)
        while True:
            try:
                fcntl.flock(lock_handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if time.time() >= deadline:
                    raise TimeoutError(f"Timed out waiting for tasks lock: {lock_path}")
                time.sleep(0.1)
        try:
            yield
        finally:
            fcntl.flock(lock_handle.fileno(), fcntl.LOCK_UN)


@contextmanager
def no_op_lock():
    yield


def synthesize_malformed_finding(
    count: int, source: str, mode: str
) -> dict[str, object]:
    return {
        "title": f"Malformed findings payload(s) detected for {source}/{mode}",
        "severity": "medium",
        "evidence": (
            f"process_findings.py skipped {count} malformed JSONL line(s). "
            "Inspect the findings generator output and fix serialization."
        ),
        "file": "scripts/process_findings.py",
        "fix_hint": "Ensure reviewer/auditor emits valid FINDING_JSON lines (one JSON object per line).",
        "task_link": "REQ-013",
    }


def main() -> int:
    args = parse_args()
    findings_file = Path(args.findings_file)
    tasks_file = Path(args.tasks_file)
    summary_file = Path(args.summary_file)
    lock_file = Path(".ralph/state/tasks_md.lock")

    findings, malformed_findings = load_findings(findings_file)
    if malformed_findings > 0:
        findings.append(
            synthesize_malformed_finding(malformed_findings, args.source, args.mode)
        )

    blocker_threshold = normalize_severity(args.blocker_severity)
    threshold_value = SEVERITY_ORDER[blocker_threshold]

    if tasks_file.is_file():
        tasks_text = tasks_file.read_text(encoding="utf-8")
    else:
        tasks_text = "# Task Backlog\n"
        if not args.dry_run:
            tasks_file.write_text(tasks_text, encoding="utf-8")

    blocking_findings = 0
    accepted_risk_findings = 0
    new_tasks = 0
    created_issue_count = 0

    try:
        lock_cm = tasks_file_lock(lock_file) if not args.dry_run else no_op_lock()
        with lock_cm:
            if not args.dry_run and tasks_file.is_file():
                tasks_text = tasks_file.read_text(encoding="utf-8")

            for finding in findings:
                severity = normalize_severity(str(finding.get("severity", "medium")))
                accepted_risk = bool(finding.get("accepted_risk", False))
                if accepted_risk:
                    accepted_risk_findings += 1
                if not accepted_risk and SEVERITY_ORDER[severity] >= threshold_value:
                    blocking_findings += 1

                marker = f"finding:{finding_fingerprint(finding)}"
                if marker in tasks_text:
                    continue

                title = short_title(str(finding.get("title", "Address finding")))
                spec_ref = pick_spec(
                    str(finding.get("task_link", "")), args.default_spec
                )
                task_id = next_task_id(tasks_text)

                if args.dry_run:
                    tasks_text = ensure_findings_backlog_header(tasks_text)
                    tasks_text += render_task_block(
                        task_id,
                        f"Resolve finding from {args.source}/{args.mode}: {title}",
                        spec_ref,
                        args.default_test,
                        marker,
                    )
                else:
                    tasks_text = append_task_block(
                        tasks_file,
                        task_id,
                        f"Resolve finding from {args.source}/{args.mode}: {title}",
                        spec_ref,
                        args.default_test,
                        marker,
                    )
                new_tasks += 1

                if not args.dry_run and args.create_low_issues and severity == "low":
                    issue_title = f"[{args.source}/{args.mode}] {title}"
                    issue_body = f"Severity: {severity}\n\nEvidence:\n{finding.get('evidence', '')}\n"
                    if maybe_create_github_issue(
                        issue_title, issue_body, args.github_repo
                    ):
                        created_issue_count += 1
                if (
                    not args.dry_run
                    and args.create_accepted_risk_issues
                    and accepted_risk
                ):
                    issue_title = f"[accepted-risk] {title}"
                    issue_body = (
                        f"Source: {args.source}/{args.mode}\n"
                        f"Severity: {severity}\n"
                        f"Reason: {finding.get('accepted_risk_reason', '')}\n"
                        f"Until: {finding.get('accepted_risk_until', '')}\n"
                    )
                    if maybe_create_github_issue(
                        issue_title, issue_body, args.github_repo
                    ):
                        created_issue_count += 1
    except TimeoutError as exc:
        print(f"[process_findings] ERROR: {exc}", file=sys.stderr)
        return 1

    summary = {
        "source": args.source,
        "mode": args.mode,
        "findings_total": len(findings),
        "blocking_findings": blocking_findings,
        "accepted_risk_findings": accepted_risk_findings,
        "new_tasks": new_tasks,
        "created_issues": created_issue_count,
        "blocker_severity": blocker_threshold,
        "malformed_findings": malformed_findings,
        "dry_run": bool(args.dry_run),
    }

    summary_file.parent.mkdir(parents=True, exist_ok=True)
    summary_file.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
