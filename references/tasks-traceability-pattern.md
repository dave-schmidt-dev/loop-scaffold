# Tasks Traceability Pattern

Use this exact task block format:

```md
- [ ] TASK-001: Short actionable task title
  - spec: REQ-001
  - test: tests/spec/test_mvp_traceability.py::MvpTraceabilityTests.test_req_001_traceability
  - owner: unassigned
  - status: todo
```

## Rules
1. Keep tasks small enough to complete in one implementation cycle.
2. Use one primary requirement per task when possible.
3. If a task spans requirements, list comma-separated IDs in `spec:`.
4. `test:` must reference concrete selectors, not placeholders.
5. Status transitions: `todo` -> `in_progress` -> `done`.
6. Only mark done after `make check` passes.

## Recommended Backlog Shape
1. Foundation/setup.
2. Core functional features.
3. Validation and execution semantics.
4. UI/reporting.
5. Persistence/export/security.
6. Testing/docs/release gates.
