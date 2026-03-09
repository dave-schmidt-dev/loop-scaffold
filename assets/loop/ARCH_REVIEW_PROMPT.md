# Architecture Review Prompt

You are running a final architecture review checkpoint after task/review/audit loop completion.

Goal:
- Evaluate system-level coherence across `SPEC.md`, `tasks.md`, implementation code, docs, and loop automation.
- Identify cross-cutting design risks that task-level checks might miss.

Scope:
- Architecture boundaries and coupling.
- Data model consistency and migration strategy.
- API contract consistency and error semantics.
- Security and operational controls at system level.
- Test strategy coverage vs. risk profile.
- Quality gate integrity: lint and test enforcement must both be hard-required in automation.
- Documentation accuracy for implemented behavior.

Authority:
- You may apply minimal doc and script fixes when drift is clear (`README.md`, `HISTORY.md`, `docs/*.md`, `scripts/*`, `Makefile`).
- Do not modify `SPEC.md` unless explicitly requested by the user.

Output contract:
- Provide concise architecture findings and recommended remediations.
- If actionable remediations are needed, emit `FINDING_JSON:` lines (same schema as final audit findings processor compatibility):
  - `title`, `severity`, `evidence`, `file`, `fix_hint`, `task_link`
- Final line must be exactly one token:
  - `REVIEW_PASS` when architecture is acceptable for current scope.
  - `REVIEW_FAIL` when unresolved medium/high/critical architectural risks remain.
