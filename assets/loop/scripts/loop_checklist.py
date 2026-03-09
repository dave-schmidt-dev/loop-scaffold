#!/usr/bin/env python3
"""Automated loop reliability checklist validation."""

from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path


@dataclass
class CheckResult:
    name: str
    ok: bool
    detail: str


def run_cmd(cmd: list[str], cwd: Path) -> tuple[int, str]:
    proc = subprocess.run(cmd, cwd=cwd, text=True, capture_output=True)
    out = (proc.stdout or "") + (proc.stderr or "")
    return proc.returncode, out.strip()


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


def disk_usage_bytes(path: Path) -> int:
    total = 0
    if not path.exists():
        return total
    for root, _, files in os.walk(path):
        root_path = Path(root)
        for name in files:
            file_path = root_path / name
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
    path = Path(candidate)
    if not path.is_absolute():
        path = repo_root / path
    return path.resolve()


def check_tasks_format(tasks_file: Path) -> CheckResult:
    if not tasks_file.is_file():
        return CheckResult("tasks.md well-formed", False, f"missing: {tasks_file}")
    text = tasks_file.read_text(encoding="utf-8", errors="replace")
    open_task_lines = re.findall(r"^- \[ \] TASK-\d+:", text, flags=re.MULTILINE)
    all_task_lines = re.findall(r"^- \[[ xX]\] TASK-\d+:", text, flags=re.MULTILINE)
    if not all_task_lines:
        return CheckResult("tasks.md well-formed", False, "no TASK-### entries")

    bad = []
    lines = text.splitlines()
    for i, line in enumerate(lines):
        if not re.match(r"^- \[[ xX]\] TASK-\d+:", line):
            continue
        has_spec = False
        has_test = False
        for j in range(i + 1, len(lines)):
            nxt = lines[j]
            if re.match(r"^- \[[ xX]\] TASK-\d+:", nxt):
                break
            if nxt.startswith("  - spec:"):
                has_spec = True
            if nxt.startswith("  - test:"):
                has_test = True
        if not (has_spec and has_test):
            bad.append(line)
    if bad:
        return CheckResult(
            "tasks.md well-formed",
            False,
            f"missing spec/test fields in {len(bad)} task(s)",
        )
    detail = (
        f"{len(open_task_lines)} open task(s)"
        if open_task_lines
        else "backlog complete (0 open tasks)"
    )
    return CheckResult("tasks.md well-formed", True, detail)


def check_lock_pid_health(state_root: Path) -> list[CheckResult]:
    lock_dir = state_root / "run_all_tasks.lock"
    pid_file = state_root / "run_all_tasks.pid"
    stop_file = state_root / "stop-after-current-task"

    results: list[CheckResult] = []
    if lock_dir.exists():
        pid = ""
        pid_path = lock_dir / "pid"
        if pid_path.is_file():
            pid = pid_path.read_text(encoding="utf-8", errors="replace").strip()
        if pid.isdigit() and pid_is_alive(int(pid)):
            results.append(
                CheckResult("No stale lock", False, f"active lock pid={pid}")
            )
        else:
            results.append(
                CheckResult("No stale lock", False, f"lock exists: {lock_dir}")
            )
    else:
        results.append(CheckResult("No stale lock", True, "none"))

    if pid_file.is_file():
        pid = pid_file.read_text(encoding="utf-8", errors="replace").strip()
        if pid.isdigit() and pid_is_alive(int(pid)):
            results.append(CheckResult("No stale PID file", False, f"pid alive={pid}"))
        else:
            results.append(
                CheckResult("No stale PID file", False, f"pid file exists: {pid_file}")
            )
    else:
        results.append(CheckResult("No stale PID file", True, "none"))

    if stop_file.exists():
        results.append(CheckResult("No stale stop file", False, f"exists: {stop_file}"))
    else:
        results.append(CheckResult("No stale stop file", True, "none"))

    return results


def run_preflight(
    repo_root: Path, state_root: Path, strict_quality: bool
) -> list[CheckResult]:
    checks: list[CheckResult] = []

    git_ec, git_out = run_cmd(["git", "status", "--porcelain"], repo_root)
    if git_ec != 0:
        checks.append(CheckResult("Repo clean", False, "git status failed"))
    else:
        checks.append(
            CheckResult(
                "Repo clean",
                git_out == "",
                "clean" if git_out == "" else "working tree has changes",
            )
        )

    venv_python = repo_root / ".venv" / "bin" / "python"
    checks.append(CheckResult("Venv active", venv_python.exists(), str(venv_python)))

    if strict_quality:
        ec, out = run_cmd(["make", "check"], repo_root)
        checks.append(
            CheckResult(
                "Quality gate green",
                ec == 0,
                (
                    "make check passed"
                    if ec == 0
                    else (out.splitlines()[-1] if out else "make check failed")
                ),
            )
        )
    else:
        checks.append(
            CheckResult("Quality gate green", True, "skipped (use --strict-quality)")
        )

    checks.append(check_tasks_format(repo_root / "tasks.md"))

    spec_file = repo_root / "SPEC.md"
    checks.append(CheckResult("SPEC.md present", spec_file.is_file(), str(spec_file)))

    prompt_files = [
        "PROMPT.md",
        "REVIEW_PROMPT.md",
        "AUDIT_PROMPT.md",
        "ARCH_REVIEW_PROMPT.md",
    ]
    missing_prompts = [p for p in prompt_files if not (repo_root / p).is_file()]
    checks.append(
        CheckResult(
            "Prompt files present",
            len(missing_prompts) == 0,
            "ok" if not missing_prompts else f"missing: {', '.join(missing_prompts)}",
        )
    )

    bins = ["codex", "gemini", "copilot", "agent", "vibe"]
    found = [b for b in bins if shutil.which(b)]
    checks.append(
        CheckResult(
            "Agent binaries reachable",
            len(found) >= 2,
            f"found: {', '.join(found) if found else 'none'}",
        )
    )

    checks.extend(check_lock_pid_health(state_root))

    ralph_size = disk_usage_bytes(repo_root / ".ralph")
    ralph_limit = 1024 * 1024 * 1024
    checks.append(
        CheckResult(
            "Disk space (.ralph < 1GiB)",
            ralph_size < ralph_limit,
            f"{ralph_size / (1024 * 1024):.1f} MiB",
        )
    )

    log_prune = os.environ.get("LOG_PRUNE_ENABLED", "1").strip().lower()
    checks.append(
        CheckResult(
            "Log pruning configured",
            log_prune in {"1", "true", "yes", "on"},
            f"LOG_PRUNE_ENABLED={log_prune}",
        )
    )

    return checks


def run_postrun(
    repo_root: Path, state_root: Path, strict_quality: bool
) -> list[CheckResult]:
    checks: list[CheckResult] = []

    stop_reason = state_root / "last_stop_reason"
    checks.append(
        CheckResult("Stop reason visible", stop_reason.is_file(), str(stop_reason))
    )

    lock_dir = state_root / "run_all_tasks.lock"
    checks.append(
        CheckResult(
            "Lock released", not lock_dir.exists(), f"exists={lock_dir.exists()}"
        )
    )

    pid_file = state_root / "run_all_tasks.pid"
    checks.append(
        CheckResult(
            "PID file cleaned", not pid_file.exists(), f"exists={pid_file.exists()}"
        )
    )

    if strict_quality:
        ec, out = run_cmd(["make", "check"], repo_root)
        checks.append(
            CheckResult(
                "Post-run quality gate",
                ec == 0,
                (
                    "make check passed"
                    if ec == 0
                    else (out.splitlines()[-1] if out else "make check failed")
                ),
            )
        )
    else:
        checks.append(
            CheckResult("Post-run quality gate", True, "skipped (use --strict-quality)")
        )

    history = repo_root / "HISTORY.md"
    checks.append(CheckResult("HISTORY.md updated", history.is_file(), str(history)))

    return checks


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Run loop reliability checklist checks."
    )
    parser.add_argument(
        "--phase", choices=["preflight", "postrun"], default="preflight"
    )
    parser.add_argument(
        "--strict-quality",
        action="store_true",
        help="Run make check as part of checklist",
    )
    parser.add_argument("--repo-root", default=str(Path(__file__).resolve().parents[1]))
    parser.add_argument("--state-root")
    args = parser.parse_args()

    repo_root = Path(args.repo_root).resolve()
    state_root = resolve_path(
        args.state_root,
        "STATE_ROOT",
        repo_root / ".ralph" / "state",
        repo_root,
    )
    checks = (
        run_preflight(repo_root, state_root, args.strict_quality)
        if args.phase == "preflight"
        else run_postrun(repo_root, state_root, args.strict_quality)
    )

    failed = [c for c in checks if not c.ok]

    print(f"Loop checklist ({args.phase})")
    for check in checks:
        icon = "PASS" if check.ok else "FAIL"
        print(f"- [{icon}] {check.name}: {check.detail}")

    if failed:
        print(f"\nChecklist failed: {len(failed)} item(s) failed.", file=sys.stderr)
        return 1

    print("\nChecklist passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
