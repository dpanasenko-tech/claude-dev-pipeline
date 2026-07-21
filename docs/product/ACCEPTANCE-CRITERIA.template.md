# Acceptance Criteria — <feature>

> Gherkin-style. Each AC has a stable ID. Each AC maps to ≥1 test.

## Conventions
- ID format: `AC-<slug>-<n>` (e.g., `AC-billing-portal-3`).
- Each AC: one behavior, one Then.
- Map to tests in `docs/features/<slug>/test-matrix.md`.

## Acceptance criteria

### AC-<slug>-1 — <short title>
- **Given** <precondition>
- **When** <action>
- **Then** <observable outcome>
- **Test**: `<test file>::<test name>`

### AC-<slug>-2 — <short title>
- **Given** ...
- **When** ...
- **Then** ...
- **Test**: ...

## Negative / edge criteria
- Same format. Examples:
  - Unauthorized actor → 403.
  - Duplicate submission → idempotent.
  - Input over limit → 422 with field error.

## Out of scope (will not be tested in this slice)
- <list>
