# Contributing

## Workflow

1. Create a branch for the change.
2. Keep edits focused and documented.
3. Update `HISTORY.md` when behavior changes.
4. Run `make check` before opening a pull request.

## Standards

- Keep shell scripts portable and readable.
- Use comments to explain non-obvious behavior, especially around loop control and safety gates.
- Avoid introducing machine-specific paths or personal account assumptions.

## Pull Requests

- Describe the user-facing change.
- Call out any changes to safety defaults or agent execution behavior.
- Include validation results from `make check`.
