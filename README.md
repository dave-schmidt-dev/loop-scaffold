# loop-scaffold

`loop-scaffold` is a public version of the `spec-loop-dev` skill: a spec-first project scaffold plus Ralph loop automation for task execution, review, and audit checkpoints.

The repo is designed for two related jobs:

1. Bootstrap a new project with `SPEC.md`, `tasks.md`, traceability tests, and a spec guard.
2. Install an operator-facing loop that works through `TASK-###` items with explicit review and audit gates.

## What You Get

- A reusable skill package layout (`SKILL.md`, `agents/`, `references/`, `assets/`, `scripts/`)
- `scripts/init_spec_scaffold.sh` to create baseline spec artifacts in a target project
- `scripts/install_loop.sh` to install Ralph loop runners and prompts into a target project
- Loop templates for implementor, reviewer, auditor, checklist, metrics, watchdog, and graceful-stop flows
- Reference docs for authoritative specs and task traceability patterns

## Repository Layout

```text
.
├── SKILL.md
├── agents/
├── assets/
│   ├── guard/
│   └── loop/
├── references/
├── scripts/
├── .github/workflows/
├── HISTORY.md
└── Makefile
```

## Prerequisites

- `bash`
- `python3` 3.10+
- `make`
- `rg` (ripgrep)
- At least one supported CLI agent available in your environment for full loop execution

The scaffold scripts themselves do not require API keys. Any live agent execution depends on whatever CLI tooling you choose to wire in.

## Safety Defaults

This public repo ships with conservative defaults:

- No unsafe CLI approval-bypass flags are enabled by default for Copilot or Cursor-style agents.
- Runtime model deny rules are opt-in through `COPILOT_FORBIDDEN_RUNTIME_MODELS`.
- GitHub issue creation from findings requires an explicit `owner/repo` via `--github-repo`.

If you want faster but less restrictive local behavior, set the corresponding environment variables in your own environment or wrapper scripts.

## Quick Start

Clone the repo and scaffold a target project:

```bash
git clone https://github.com/dave-schmidt-dev/loop-scaffold.git
cd loop-scaffold

mkdir -p /path/to/target-project
./scripts/init_spec_scaffold.sh /path/to/target-project my-project
./scripts/install_loop.sh /path/to/target-project
```

Then in the target project:

```bash
make check
```

## Using This As a Skill

If you want to use this repo as a Codex-style local skill, place or symlink the repo into your skills directory and keep the current structure intact so relative paths in `SKILL.md` continue to resolve.

## Validation

Run the repository checks before publishing changes:

```bash
make check
```

Current validation covers:

- Bash syntax for shipped shell entrypoints
- Python bytecode compilation for shipped Python utilities
- Presence checks for the required skill assets and templates

## Security and Privacy

- This repo should not contain API keys, auth tokens, personal email addresses, or machine-specific absolute paths.
- Generated loop state and telemetry are intended to stay local and are ignored by `.gitignore`.
- Review target projects separately before committing them; this repo only packages the scaffold and automation templates.

## Portfolio Notes

The repo is intended to be readable on its own. The public-facing pieces are:

- A concrete problem statement: spec drift and unstructured agent automation
- Shell and Python automation assets with validation
- CI that exercises the package before merge
- Change history in [`HISTORY.md`](./HISTORY.md)

## Roadmap

- Add example target-project output under `examples/`
- Add automated smoke tests that run the scaffold scripts inside a temporary directory
- Document agent-priority configuration in more detail
