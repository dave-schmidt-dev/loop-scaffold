# Spec Authoritative Checklist

Use this checklist when drafting or reviewing `SPEC.md`.

## Required Structure
1. Purpose and product summary.
2. MVP goals and out-of-scope boundaries.
3. End-to-end user flow.
4. Functional requirements (`REQ-###`).
5. Quality/process requirements.
6. Decision log (defaults locked for MVP).
7. Remaining non-blocking questions.

## Requirement Quality Rules
1. Each requirement has a clear description.
2. Each requirement has measurable acceptance criteria.
3. Criteria use concrete constraints (caps, formulas, statuses, thresholds).
4. Ambiguous language is removed (`fast`, `robust`, `high quality`) unless quantified.
5. Security and secret-handling behavior is explicit.
6. Testing requirements are explicit (unit/integration/e2e/regression).

## Implementation Authority Rules
1. Stack defaults are named (frameworks, runtime, database, migrations).
2. API contract conventions are named (versioning, error envelope, pagination).
3. Data contracts are explicit (required fields, optional fields, dedupe key).
4. Retry, timeout, and concurrency behavior are deterministic.
5. Release approval and change-control ownership are explicit.

## Traceability Rules
1. Every `REQ-###` must map to at least one task in `tasks.md`.
2. Every `REQ-###` must have at least one test file containing `covers: REQ-###`.
3. `make check` must fail when traceability is broken.
