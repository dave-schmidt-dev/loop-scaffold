#!/usr/bin/env python3
"""Enforce traceability between SPEC requirements, tasks, and tests."""

from __future__ import annotations

import argparse
import re
import sys
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path

REQ_HEADING_RE = re.compile(r"^###\s+(REQ-\d+):")
TASK_LINE_RE = re.compile(r"^- \[[ xX]\]\s+(TASK-\d+):\s+(.+)$")
FIELD_LINE_RE = re.compile(r"^  - ([a-z_]+):\s+(.+)$")
COVERS_RE = re.compile(r"covers:\s*(REQ-\d+)", re.IGNORECASE)


@dataclass
class ParsedTask:
    task_id: str
    line_number: int
    fields: dict[str, str]


@dataclass
class GuardResult:
    requirements: set[str]
    tasks: list[ParsedTask]
    covered_requirements: set[str]
    errors: list[str]


def parse_requirements(spec_path: Path) -> set[str]:
    """Extract requirement IDs from the spec heading format."""
    requirements: set[str] = set()
    for line in spec_path.read_text(encoding="utf-8").splitlines():
        match = REQ_HEADING_RE.match(line)
        if match:
            requirements.add(match.group(1).upper())
    return requirements


def parse_tasks(tasks_path: Path) -> list[ParsedTask]:
    """Parse standardized task entries from tasks.md."""
    tasks: list[ParsedTask] = []
    current: ParsedTask | None = None

    for line_number, line in enumerate(tasks_path.read_text(encoding="utf-8").splitlines(), start=1):
        task_match = TASK_LINE_RE.match(line)
        if task_match:
            if current is not None:
                tasks.append(current)
            current = ParsedTask(
                task_id=task_match.group(1).upper(),
                line_number=line_number,
                fields={},
            )
            continue

        field_match = FIELD_LINE_RE.match(line)
        if field_match and current is not None:
            key = field_match.group(1).strip().lower()
            value = field_match.group(2).strip()
            current.fields[key] = value

    if current is not None:
        tasks.append(current)

    return tasks


def split_csv(value: str) -> list[str]:
    """Split comma-separated values and trim whitespace."""
    return [item.strip() for item in value.split(",") if item.strip()]


def normalize_test_path(root: Path, selector: str) -> Path:
    """Resolve a test selector path to a real filesystem path."""
    selector_path = selector.split("::", 1)[0]
    path = Path(selector_path)
    if path.is_absolute():
        return path
    return (root / path).resolve()


def scan_test_coverage(root: Path, tests_dir: Path) -> tuple[dict[str, set[str]], dict[str, set[str]]]:
    """Scan tests for `covers: REQ-###` tags."""
    requirement_to_files: dict[str, set[str]] = defaultdict(set)
    file_to_requirements: dict[str, set[str]] = defaultdict(set)

    if not tests_dir.exists():
        return requirement_to_files, file_to_requirements

    root_resolved = root.resolve()

    for test_file in tests_dir.rglob("test_*.py"):
        test_file_resolved = test_file.resolve()
        try:
            relative = str(test_file_resolved.relative_to(root_resolved))
        except ValueError:
            relative = str(test_file_resolved)
        content = test_file_resolved.read_text(encoding="utf-8")
        for match in COVERS_RE.finditer(content):
            req_id = match.group(1).upper()
            requirement_to_files[req_id].add(relative)
            file_to_requirements[relative].add(req_id)

    return requirement_to_files, file_to_requirements


def analyze_project(
    root: Path,
    spec_file: str = "SPEC.md",
    tasks_file: str = "tasks.md",
    tests_dir: str = "tests",
) -> GuardResult:
    """Validate the project against traceability rules."""
    root = root.resolve()
    errors: list[str] = []
    spec_path = root / spec_file
    tasks_path = root / tasks_file
    tests_path = root / tests_dir

    if not spec_path.exists():
        errors.append(f"Missing spec file: {spec_path}")
        return GuardResult(set(), [], set(), errors)

    if not tasks_path.exists():
        errors.append(f"Missing task file: {tasks_path}")
        return GuardResult(set(), [], set(), errors)

    requirements = parse_requirements(spec_path)
    tasks = parse_tasks(tasks_path)

    if not requirements:
        errors.append("No requirement headings found. Add lines like: ### REQ-001: ...")

    if not tasks:
        errors.append("No tasks found. Add task entries to tasks.md.")

    req_to_tasks: dict[str, set[str]] = defaultdict(set)
    req_to_coverage, test_file_to_reqs = scan_test_coverage(root, tests_path)

    for req_id in req_to_coverage:
        if req_id not in requirements:
            files = ", ".join(sorted(req_to_coverage[req_id]))
            errors.append(f"Coverage tag references unknown requirement {req_id} in {files}.")

    for task in tasks:
        spec_field = task.fields.get("spec", "")
        test_field = task.fields.get("test", "")
        status_field = task.fields.get("status", "")

        if not spec_field:
            errors.append(f"{task.task_id} (line {task.line_number}) missing 'spec' field.")
            continue

        if not test_field:
            errors.append(f"{task.task_id} (line {task.line_number}) missing 'test' field.")

        if not status_field:
            errors.append(f"{task.task_id} (line {task.line_number}) missing 'status' field.")

        spec_refs = [item.upper() for item in split_csv(spec_field)]
        if not spec_refs:
            errors.append(f"{task.task_id} (line {task.line_number}) has empty 'spec' field.")
            continue

        test_selectors = split_csv(test_field) if test_field else []
        test_rel_paths: set[str] = set()

        for selector in test_selectors:
            test_path = normalize_test_path(root, selector)
            if not test_path.exists():
                errors.append(f"{task.task_id} references missing test path: {selector}")
                continue
            try:
                rel_path = str(test_path.relative_to(root))
            except ValueError:
                rel_path = str(test_path)
            test_rel_paths.add(rel_path)

        for req_id in spec_refs:
            if not re.fullmatch(r"REQ-\d+", req_id):
                errors.append(f"{task.task_id} has invalid requirement format '{req_id}'. Use REQ-###.")
                continue

            if req_id not in requirements:
                errors.append(f"{task.task_id} references unknown requirement {req_id}.")
                continue

            req_to_tasks[req_id].add(task.task_id)

            if test_rel_paths:
                covers_req = any(req_id in test_file_to_reqs.get(path, set()) for path in test_rel_paths)
                if not covers_req:
                    errors.append(
                        f"{task.task_id} maps to {req_id} but its tests do not declare 'covers: {req_id}'."
                    )

    for req_id in sorted(requirements):
        if not req_to_tasks.get(req_id):
            errors.append(f"{req_id} has no mapped task in tasks.md.")
        if not req_to_coverage.get(req_id):
            errors.append(f"{req_id} has no test coverage tag. Add 'covers: {req_id}' in a test file.")

    return GuardResult(
        requirements=requirements,
        tasks=tasks,
        covered_requirements=set(req_to_coverage.keys()),
        errors=errors,
    )


def main() -> int:
    """CLI entrypoint."""
    parser = argparse.ArgumentParser(description="Validate SPEC/tasks/tests traceability.")
    parser.add_argument("--root", default=".", help="Project root directory.")
    parser.add_argument("--spec", default="SPEC.md", help="Path to spec file relative to root.")
    parser.add_argument("--tasks", default="tasks.md", help="Path to tasks file relative to root.")
    parser.add_argument("--tests", default="tests", help="Path to tests directory relative to root.")
    args = parser.parse_args()

    root = Path(args.root).resolve()
    result = analyze_project(root=root, spec_file=args.spec, tasks_file=args.tasks, tests_dir=args.tests)

    if result.errors:
        print("Spec guard failed:")
        for error in result.errors:
            print(f"- {error}")
        return 1

    print(
        "Spec guard passed: "
        f"{len(result.requirements)} requirement(s), "
        f"{len(result.tasks)} task(s), "
        f"{len(result.covered_requirements)} covered requirement(s)."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
