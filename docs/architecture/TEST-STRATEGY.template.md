# Test Strategy

> Stack-agnostic defaults. Replace placeholders once stack is chosen.

## Pyramid (default targets)
- **Unit** — pure functions, no I/O. Target: most of the suite. Runtime budget: full unit suite < 30s.
- **Integration** — real DB, real HTTP server in-process, mocked third parties. Target: every API endpoint + critical service path.
- **End-to-end** — boot the app, hit the public surface, real DB. Target: the critical-path smoke flow only.
- **Contract** — for each external API consumed or exposed.

## What to mock
- **Never mock what you own** (your DB, your services). Use real instances in integration tests.
- **Always mock what you don't own**: third-party APIs, time (`clock`), randomness, network calls in unit tests.

## Fixtures & data
- Factory functions per entity. No shared mutable fixtures across tests.
- Each test creates its own data and tears it down (transaction rollback or scoped DB).
- No production data, no PII in fixtures.

## Environment

### Local
```bash
# Unit tests (no DB):
uv run pytest -q tests/unit/

# Integration (требует PostgreSQL):
DATABASE_URL=postgresql+psycopg://user:pass@localhost:5434/dbname \
  uv run pytest -q tests/integration/

# Quality check (format + lint + typecheck + unit):
bash scripts/quality-check.sh

# Smoke CI (ephemeral stack — только локально, не на staging):
SMOKE_MODE=ci bash scripts/smoke-check.sh
```

### CI (ephemeral)
```bash
# Unit + integration (без DB для unit):
uv run pytest -q tests/unit/

# Integration (требует PostgreSQL, запускается в CI docker-service):
DATABASE_URL=postgresql+psycopg://... uv run pytest -q tests/integration/

# Smoke (ephemeral stack — boot → seed → assert → down):
SMOKE_MODE=ci bash scripts/smoke-check.sh
```

### CD — Staging
```bash
# Non-destructive assertions против running stack:
SMOKE_MODE=staging bash scripts/smoke-check.sh

# Или через pytest напрямую (когда появятся pytest-smoke тесты):
SMOKE_MODE=staging uv run pytest -q tests/smoke/
```

### CD — Production (когда появится)
```bash
# Только read-only smoke:
SMOKE_MODE=prod uv run pytest -q tests/smoke/ -m "readonly"
```

## Smoke test matrix

| Тест | CI (ephemeral) | Staging | Prod |
|---|---|---|---|
| DB connectivity | ✓ | ✓ | ✓ |
| alembic at head | ✓ | ✓ | ✓ |
| Seed data present | seeded (= 1) | native (>= 0) | native (>= 0) |
| AbcSnapshotTool | ✓ | ✓ if data | — |
| GlitchTip ingest probe | ✓ | ✓ | — (read-only) |
| Mutable operations | ✓ | — | — |
| Stack boot/teardown | ✓ | — | — |

## SMOKE_MODE pattern

```python
# tests/smoke/conftest.py (создаётся когда появятся первые pytest smoke тесты)
import os, pytest

SMOKE_MODE = os.environ.get("SMOKE_MODE", "ci")

@pytest.fixture(scope="session")
def smoke_db_url():
    match SMOKE_MODE:
        case "ci":      return os.environ["DATABASE_URL"]
        case "staging": return os.environ["STAGING_DB_URL"]
        case _:         pytest.skip("SMOKE_MODE not configured for this target")

@pytest.fixture(scope="session")
def is_mutable():
    return SMOKE_MODE == "ci"
```

- DB: ephemeral per-run (Dockerized or transactional rollback).

## Determinism
- Seed all randomness.
- Freeze time at known instants.
- No `sleep`-based waits — use deterministic synchronization (events, conditions).
- No external network calls in unit/integration tiers.

## Flake policy
- A flaky test is a bug. Quarantine within 24h, fix within 1 week, or delete.
- No retry-until-green in CI for application tests.

## Coverage
- Coverage is a *floor*, not a goal. Suggested floors:
  - Unit: 80% line / 70% branch on changed files.
  - Integration: every endpoint exercised at least once.
- Reviewer rejects coverage-padding tests (assert on internals, no behavior).

## Performance & load tests
- Out of the default suite. Run on a schedule against staging.
- Define SLOs in `docs/architecture/SLO.md` (TODO if added).

## Security tests
- AuthN/AuthZ matrix per endpoint (allowed roles vs denied roles).
- Input fuzzing on every public boundary.
- Dependency scan in CI (TODO: wire in chosen tool).
