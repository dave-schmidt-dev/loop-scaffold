#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "Usage: $0 <project-root> [project-name]"
  exit 1
fi

target_root="$1"
project_name="${2:-$(basename "$target_root")}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skill_root="$(cd "${script_dir}/.." && pwd)"
guard_template="${skill_root}/assets/guard/spec_guard.py"

if [[ ! -d "$target_root" ]]; then
  echo "Target project root does not exist: $target_root" >&2
  exit 1
fi

mkdir -p "${target_root}/scripts" "${target_root}/tests/spec" "${target_root}/.github/workflows"

write_if_missing() {
  local path="$1"
  local content="$2"
  if [[ -e "$path" ]]; then
    echo "Skip existing file: $path"
    return
  fi
  printf '%s\n' "$content" > "$path"
  echo "Created: $path"
}

write_if_missing "${target_root}/SPEC.md" "# SPEC: ${project_name}

## 1. Purpose
Describe the product purpose and MVP outcome.

## 2. MVP Goals
- Goal 1
- Goal 2

## 3. Functional Requirements

### REQ-001: Spec-task-test traceability
- Type: Quality
- Priority: P0
- Description: Requirements, tasks, and tests remain continuously aligned.
- Acceptance Criteria:
  - [ ] Every requirement maps to one or more tasks in tasks.md.
  - [ ] Every requirement has at least one test with covers: REQ-###.
  - [ ] make check fails on traceability drift.
"

write_if_missing "${target_root}/tasks.md" "# tasks.md

## Backlog

- [ ] TASK-001: Maintain traceability guardrails
  - spec: REQ-001
  - test: tests/spec/test_mvp_traceability.py::MvpTraceabilityTests.test_req_001_traceability
  - owner: unassigned
  - status: todo
"

write_if_missing "${target_root}/tests/spec/test_mvp_traceability.py" "import unittest


class MvpTraceabilityTests(unittest.TestCase):
    def test_req_001_traceability(self) -> None:
        # covers: REQ-001
        self.assertTrue(True)
"

write_if_missing "${target_root}/tests/__init__.py" ""
write_if_missing "${target_root}/tests/spec/__init__.py" ""

if [[ ! -f "${target_root}/scripts/spec_guard.py" ]]; then
  cp "$guard_template" "${target_root}/scripts/spec_guard.py"
  chmod +x "${target_root}/scripts/spec_guard.py"
  echo "Created: ${target_root}/scripts/spec_guard.py"
else
  echo "Skip existing file: ${target_root}/scripts/spec_guard.py"
fi

if [[ ! -f "${target_root}/Makefile" ]]; then
  cat > "${target_root}/Makefile" <<'EOF'
.PHONY: guard lint test check check-fast

guard:
	python3 scripts/spec_guard.py

lint:
	@echo "No linter configured yet; add project-specific lint commands here."

test:
	python3 -m unittest discover -s tests -p "test_*.py"

check: lint guard test

check-fast: check
EOF
  echo "Created: ${target_root}/Makefile"
else
  echo "Skip existing file: ${target_root}/Makefile"
fi

if [[ ! -f "${target_root}/.github/workflows/spec-quality.yml" ]]; then
  cat > "${target_root}/.github/workflows/spec-quality.yml" <<'EOF'
name: Spec Quality Gates

on:
  push:
    branches: ["**"]
  pull_request:

jobs:
  guard-and-test:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: "3.11"

      - name: Run checks
        run: make check
EOF
  echo "Created: ${target_root}/.github/workflows/spec-quality.yml"
else
  echo "Skip existing file: ${target_root}/.github/workflows/spec-quality.yml"
fi

echo ""
echo "Spec scaffold initialized for ${project_name}."
echo "Next:"
echo "1) Expand SPEC.md with product-specific REQ-### entries"
echo "2) Expand tasks.md with mapped TASK-### entries"
echo "3) Run: make check"
