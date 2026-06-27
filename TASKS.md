# Tasks

> Live queue for **current, pending, and future** work — never history. Completed work belongs in `HISTORY.md`. See `~/.agent/AGENTS.md` → Required Documents.

Status key: `pending | in progress | done | blocked`

## Rules

- Never trample another session's in-flight or pending work.
- Update status as work progresses.
- Only mark `done` after verification (tests pass, behavior confirmed).
- `done` is **transient**: after verification, port the row's substance into `HISTORY.md` and delete the row from `TASKS.md` in the same change.
- If a completed task is worth remembering, that's a `HISTORY.md` entry — not a `TASKS.md` preservation.
- Smell test: if `done` rows outnumber open rows, the file has drifted into a log. Clean it up.
- Keep tasks small and actionable — one unit of work each.

## Open

> Source: the "Roadmap" section of `README.md`. No `TODO`/`FIXME`/`XXX` markers exist in tracked source. This repo is a scaffold/template (a public packaging of the `spec-loop-dev` skill); last commit 2026-03-09.

### Task 1: Add example target-project output under `examples/`
- **Status:** pending
- **Description:** Create an `examples/` directory showing the artifacts produced when `scripts/init_spec_scaffold.sh` and `scripts/install_loop.sh` run against a fresh target project, so readers can see the scaffold output without running it.
- **Blocked by:** none
- **Tests:** manual verification (compare committed example output against a fresh scaffold run)
- **Done when:**
  - `examples/` exists with representative scaffolded output
  - `README.md` Roadmap item is updated to reflect completion

### Task 2: Add automated smoke tests that run the scaffold scripts in a temp directory
- **Status:** pending
- **Description:** Add a test that runs `scripts/init_spec_scaffold.sh` and `scripts/install_loop.sh` against a throwaway temporary directory and asserts the expected files are created, then wire it into `make check` / the CI workflow (`.github/workflows/ci.yml`).
- **Blocked by:** none
- **Tests:** new smoke test invoked via `make check` and CI
- **Done when:**
  - A smoke test exercises both scaffold scripts in a temp dir and asserts expected artifacts
  - The test runs in `make check` and in CI
  - `README.md` Roadmap item is updated to reflect completion

### Task 3: Document agent-priority configuration in more detail
- **Status:** pending
- **Description:** Expand the docs to explain how agent priority/selection is configured for loop execution (e.g. `agents/openai.yaml`, the safety-default environment variables, and dispatcher behavior in `assets/loop/scripts/agent_dispatcher.sh`).
- **Blocked by:** none
- **Tests:** manual verification (docs reviewed for accuracy against the referenced config/scripts)
- **Done when:**
  - Agent-priority configuration is documented (README or a `references/` doc)
  - `README.md` Roadmap item is updated to reflect completion
