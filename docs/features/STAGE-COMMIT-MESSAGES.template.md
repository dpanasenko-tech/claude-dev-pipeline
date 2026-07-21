# Stage Commit Messages Template

Format: `[STAGE N/6] <verb>: <one-line description>`

## Stage 1 — Brief (planner)
```
[STAGE 1/6] brief: <problem statement in one line>
```
Example: `[STAGE 1/6] brief: billing API data rail — fetch invoices and sync to DB`

## Stage 2 — Plan (architect)
```
[STAGE 2/6] plan: <key architecture decision in one line>
```
Example: `[STAGE 2/6] plan: polling adapter with idempotent upsert, no webhook`

## Stage 3 — Tests (tdd-engineer)
```
[STAGE 3/6] tests: failing tests for <AC reference>
```
Example: `[STAGE 3/6] tests: failing tests for invoice fetch AC-1..AC-4`

## Stage 4 — Implementation (implementer)
```
[STAGE 4/6] impl: <what was implemented, tests green>
```
Example: `[STAGE 4/6] impl: polling adapter, invoice upsert, all tests green`

## Stage 5 — Review (reviewer)
```
[STAGE 5/6] review: <findings summary or "no blockers">
```
Example: `[STAGE 5/6] review: 2 minor findings fixed, no blockers`

## Stage 6 — Release (release-engineer)
```
[STAGE 6/6] release: <GO or NO-GO + one-line rationale>
```
Example: `[STAGE 6/6] release: GO — CI green, rollback plan verified`
