---
name: spec-loop-dev
description: Build and operate a spec-driven development workflow with strict traceability and autonomous task-loop execution. Use when a user wants to start a project from scratch with authoritative `SPEC.md` + `tasks.md` + test coverage mapping, or when they want to automate `TASK-###` implementation cycles with Ralph-loop quality gates.
---

# Spec Loop Dev

## Workflow

### Step 1: Confirm Scope
Confirm whether the user wants one or both:
1. Spec framework generation (`SPEC.md`, `tasks.md`, coverage guardrails).
2. Autonomous task-loop setup (Ralph loop scripts and orchestrator).

If unclear, default to both.

### Step 2: Gather Minimum Product Context
Collect concise answers needed to generate an authoritative spec:
1. Product name and one-sentence product summary.
2. MVP audience and outcome.
3. In-scope and out-of-scope boundaries.
4. Must-have features.
5. Non-functional constraints (local/cloud, security, testing, release control).

Then use [references/spec-authoritative-checklist.md](references/spec-authoritative-checklist.md).

### Step 3: Generate Authoritative Spec
Create or update `SPEC.md` with:
1. Requirement IDs (`REQ-###`) and acceptance criteria.
2. Explicit defaults for architecture, data, retries/timeouts, and testing.
3. Decision log and remaining non-blocking questions.

Rules:
1. Every requirement must be testable.
2. Avoid vague statements (replace with thresholds, formulas, caps).
3. Put approval-gated decisions in a dedicated release/process requirement.

### Step 4: Generate Traceable Task Backlog
Create or update `tasks.md` so every task has:
1. `TASK-###` ID.
2. `spec:` with one or more `REQ-###`.
3. `test:` with at least one concrete selector.
4. `status:` and `owner:`.

Use [references/tasks-traceability-pattern.md](references/tasks-traceability-pattern.md).

### Step 5: Install Guardrails
Use scripts in this skill:
1. `scripts/init_spec_scaffold.sh <project-root>` to add baseline spec files and guard script if missing.
2. `scripts/install_loop.sh <project-root>` to install Ralph loop automation scripts.
3. Ensure operator loop entrypoints default to colorized terminal/debug output for readability.
4. Ensure install includes reviewer checkpoints, auditor checkpoints, graceful-stop helpers, append-only telemetry helpers, and structured result handoff files.
5. Ensure install includes the shared loop helpers required by current loop runners: `checkpoint_exec_lib.sh`, `loop_state.sh`, `loop_process_scan.sh`, `exit_codes.sh`, and `loop_checklist.py`.
6. Ensure install includes status/report/prune helpers (`loop_status.py`, `loop_report.py`, `prune_loop_logs.sh`) plus watchdog/log-retention defaults.
7. Ensure codex wrappers default to `--skip-git-repo-check` and only run git actions when a local `.git` exists in project root.

Installed files are sourced from this skill's `assets/` templates.

### Step 6: Validate
Run validation and refuse to declare done unless checks pass:
1. `bash -n agent.sh reviewer.sh auditor.sh ralph.sh scripts/agent_dispatcher.sh scripts/exit_codes.sh scripts/checkpoint_exec_lib.sh scripts/loop_state.sh scripts/loop_process_scan.sh scripts/run_next_task.sh scripts/run_all_tasks.sh scripts/run_review_exec.sh scripts/run_audit_exec.sh scripts/stop_loop_gracefully.sh scripts/prune_loop_logs.sh`
2. `make lint`
3. `make check`
4. `python3 -m unittest discover -s tests -p "test_*.py"`
5. Confirm every `REQ-###` has both task mapping and `covers:` tags.

## Resource Usage

### scripts/
1. `scripts/init_spec_scaffold.sh`: install baseline `SPEC.md`, `tasks.md`, trace tests, and `scripts/spec_guard.py`.
2. `scripts/install_loop.sh`: install `ralph.sh`, `agent.sh`, `reviewer.sh`, `auditor.sh`, prompt files, loop runners, graceful-stop helpers, shared loop-state/process-scan/checkpoint helpers, checklist/status/report/prune utilities, and colorized loop wrappers.

### references/
1. `references/spec-authoritative-checklist.md`: required sections and decision quality checklist.
2. `references/tasks-traceability-pattern.md`: task formatting and mapping rules.

### assets/
1. `assets/guard/spec_guard.py`: reusable traceability validator.
2. `assets/loop/*`: reusable Ralph-loop automation templates, including reviewer/auditor checkpoints, graceful stop controls, append-only telemetry logging, shared checkpoint/state/process-scan helpers, watchdog/log-retention controls, checklist/status/report helpers, and default colorized output wrappers.
