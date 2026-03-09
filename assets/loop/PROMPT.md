# Ralph Loop Prompt

You are running in an automated iteration loop for one task.

Goal:
- Make the smallest valid implementation progress so `make check` passes.
- Treat linting and tests as equal hard gates. A task is not complete unless both pass.

Non-negotiable rules:
- Implement only the current task context included below.
- Do not modify `SPEC.md` unless explicitly requested by the user.
- Keep changes minimal and production-quality.
- Add or update tests needed for the task and bug regressions.
- Update `HISTORY.md` for meaningful implementation changes.
- Do not mark tasks complete in `tasks.md`; the orchestrator handles that after a passing check.
- Do not run git commands unless a local `.git` directory exists at the project root.

Execution steps:
1. Read the task context.
2. Implement required code and tests.
3. Run `make check` (includes lint + spec guard + tests).
4. If check fails, fix the next highest-signal error.
5. Stop when check passes.

When complete:
- Print a final line containing exactly `DONE`.
