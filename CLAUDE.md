# CLAUDE.md — Operating Protocol

> This file is the contract between you (Claude) and this project. It overrides any general defaults. Read it fully before any non-trivial action.

## 1. Project mission

Ship a production-grade B2B SaaS product incrementally without letting quality collapse. Every change must be safe to deploy, easy to review, and tied to a real user/business outcome.

## 2. Architecture guardrails

- **Modular by default.** Group code by feature (vertical slice), not by technical layer.
- **No god-modules.** A file > ~400 lines or a function > ~50 lines is a smell — split it.
- **Boundaries are explicit.** Cross-feature calls go through a stable public interface, not internals.
- **Pure core, thin edges.** Business logic is pure and testable; I/O sits at the edge.
- **One source of truth per concept.** No parallel implementations, no shadow models.
- **Migrations are forward-only and reviewed.** Never edit a shipped migration.
- **External API clients implement a Protocol.** Third-party API clients (`ExternalApiClient`, etc.) must be injectable via constructor so tests pass a stub without network I/O.

## 3. Coding standards

- Names describe intent, not type. `userById`, not `getUser`.
- Comments explain **why**, not **what**. Default to no comment.
- No dead code, no commented-out blocks, no `TODO` without a ticket or owner.
- Errors carry context; never swallow exceptions.
- Validate at the system boundary (HTTP, queue, CLI); trust internal types.
- No `any` / `Object` / `interface{}` escape hatches without a written reason.

## 4. Task execution protocol

For any non-trivial change, the slice runs through six stages. **Human approval gates are only at Stage 1 (brief) and Stage 2 (plan)** — the product and architecture decisions. Once the plan (Stage 2) is approved and merged, the agent drives **Stages 3–6A autonomously in a single consolidated PR** (tests → code → adversarial review → release Phase A) **without stopping for human review of intermediate stages**. The next human checkpoint is **release Phase A = GO** on that PR: the human verifies GO and merges. Stage 6B (post-deploy: staging sync + Phase B + prod deploy) follows the merge. Any account can perform any stage.

| Stage | Agent | Artifact | Base | Gate |
|---|---|---|---|---|
| 1 | `planner` | `docs/features/<slug>/brief.md` | `main` | 👤 **human approve → merge** |
| 2 | `architect` | `docs/features/<slug>/plan.md` | after stage 1 merge | 👤 **human approve → merge** |
| 3–5 | `tdd-engineer` → `implementer` → `reviewer` | failing tests + `test-matrix.md` · `src/` green · `review.md` | after stage 2 merge — **one PR** | ⚙️ autonomous |
| 6A | `release-engineer` | `release.md` §§1–9 (Phase A) | same PR | 👤 **human: GO → merge** |
| 6B | `release-engineer` | `release.md` §10 (Phase B) | after merge, on staging→prod | deploy |

**The consolidated 3–6A PR is the deliverable the human reviews** — not the intermediate stages. Before it is pushed for the human's GO check it must satisfy, autonomously:
- `scripts/quality-check.sh` green (format + lint + typecheck + all tests, incl. integration — see §12) and `SMOKE_MODE=ci` green.
- **Reviewer stage still runs** as an internal quality gate: a **fresh, independent** `reviewer` agent (never the context that wrote the impl) performs the adversarial pass (§10). If it raises blockers, `implementer` fixes them and the reviewer re-runs — **the agent resolves blockers itself; the human never sees intermediate blockers, only the final GO.** `review.md` is still written as the record, but it is **not** a human checkpoint.
- `release.md` §§1–9 filled with the Phase A verdict = GO.

The human's review is **not skipped** — it moves from six per-slice checkpoints to two decisions of substance (plan, then Phase A GO). The quality mechanism at Stages 3–5 is the automated/agent guardrails above (tests, quality-check, adversarial reviewer, `/review`), which replace — not remove — the former human rubber-stamp.

**Дисциплина вердикта (действует для любого GO — Phase A и Phase B).** Вердикт `GO` обязан
**поимённо перечислить каждый** обязательный пункт DoD (§7) и релиз-чеклиста (§11) с отметкой
✓/✗. Любой ✗ = **NO-GO** либо письменный waiver с обоснованием прямо в `release.md`. «Тихий GO»,
где непокрытый обязательный пункт (например, пропущенный релиз-тег) умалчивается, а не отмечается —
**невалиден**. Если пункт не перечислен, вердикт невалиден. Enforcement Phase B — §11.

**API contract capture** (обязательно перед stage 3, если фича использует новый endpoint внешнего API):
До написания тестов — выполнить один реальный запрос к API, сохранить сырой ответ в `docs/api-samples/<api>_<method>.json`. Этот файл становится единственным источником правды для фикстур. Тесты пишутся против зафиксированного контракта, а не предполагаемой формы ответа. Файл коммитится вместе с PR stage 3.

Trivial changes (typo, copy, single-line bug) may skip stages 1–3 but never skip the reviewer pass (Stage 5) — which, per above, runs autonomously as an internal gate.

See `docs/runbooks/PR-BASED-WORKFLOW.md` and `docs/runbooks/GIT-WORKFLOW-COMMANDS.md`.

**Follow-up lifecycle (техдолг не теряется между аккаунтами).** Источник правды —
**GitHub Issues** с меткой `followup` в репо `your-org/your-project`. Состояние
серверное и одинаковое для обоих аккаунтов, не привязано к ветке. Список открытых пунктов
вычисляется командой `scripts/followups.sh` (обёртка над `gh issue list`). Жизненный цикл:

- **Write** — любой агент, заметив постороннее, создаёт issue одной командой:
  ```
  gh issue create --label "followup,slice:<slug>[,route:<agent>]" \
    --title "FU-<slug>-<кратко>: описание" --body "контекст + предлагаемое действие"
  ```
  Не чинит сейчас. Метка `route:<agent>` необязательна, но помогает `planner`'у.
- **Adopt** — `planner` в начале каждого брифа гоняет `scripts/followups.sh [--slice <slug>]`,
  тащит релевантные issues в Scope или явно в Out of scope; ссылается на `#N` в тексте.
  Issue остаётся open до закрывающего PR.
- **Close** — PR, который чинит пункт, пишет `Closes #N` в теле. GitHub закрывает issue
  **автоматически при merge в main**. Ничего не редактировать вручную.
- **Verify** — `reviewer` (§10) проверяет `gh pr view <N> --json closingIssuesReferences`;
  `release-engineer` (§11) подтверждает `gh issue list --label followup --state open`.
  `GO` с незакрытыми, но решёнными пунктами недопустим.

Таксономия меток: `followup` (обязательна) · `slice:<slug>` (обязательна) · `route:<agent>` (опционально).
Детали и команды — `docs/runbooks/FOLLOWUPS.md`.

## 5. Vertical slice rule

Every feature ships **end-to-end**: data → service → API → UI (or CLI) → tests → docs. No half-built slices left on `main`. Prefer five thin slices over one thick one.

## 6. Testing rule

- **Test first** for behavior. Write a failing test that pins the contract before writing the implementation.
- **Test pyramid**: unit > integration > e2e. Don't replace a fast unit test with a slow e2e.
- **Real dependencies at boundaries.** Mock only what you don't own (third-party APIs, time, randomness).
- **Third-party API clients are always mocked in unit and integration tests.** Use fixture files from `docs/api-samples/` as response payloads. Tag any test that calls the real API with `@pytest.mark.live_api` — skipped by default, run only in CI when the token env var is set.
- **Fixture-first for new API methods.** Before writing tests — capture a real response into `docs/api-samples/`. Tests use only that payload; never invent the shape of an external response.
- **Determinism is mandatory.** A flaky test is a bug — quarantine or fix, never retry. Never add `sleep()` or retry loops in tests.
- Coverage is a *floor*, not a goal. Aim for meaningful assertions, not line counts.
- **Dual-mode smoke tests.** `smoke-check.sh` работает в трёх режимах через `SMOKE_MODE` env var:
  - `ci` (default): ephemeral stack в **изолированном** compose-проекте `acme-cismoke` — полный цикл boot postgres → migrate → seed → assert → `down -v`. Изоляция по трём осям (слайс `ci-smoke-isolation`, `deploy/docker-compose.ci.yml` + хелпер `ci_compose()` в `smoke-check.sh`): отдельный том `acme-cismoke_postgres_data`, private-сеть `cismoke_net` (вместо external `acme_net`), переопределённый `container_name` без host-порта. BI-инструмент/glitchtip/redis/etc. в CI **не поднимаются** (только postgres + one-shot `app` через `run --rm`).
  - `staging`: assertions-only против running stack — без boot, без down, без seed. Ассерты на `COUNT >= expected`, не `= expected`. Никогда не останавливает стек.
  - `prod`: только read-only health checks. Никаких мутаций, никакого seed.
- **`SMOKE_MODE=ci` изолирован от dev/staging и НЕ стирает пользовательские данные** — `down -v` удаляет только том CI-проекта `acme-cismoke`; dev/staging-стек (`acme-platform`, том `acme-platform_postgres_data`, external-сети `acme_net`/`acme-platform-shared`) и данные BI-инструмента физически вне границ проекта. Эмпирически подтверждено на живом staging-хосте (пример из практики — issue-трекер, номера тикетов опущены). **Эта изоляция — load-bearing инвариант защиты данных: любое изменение `smoke-check.sh` или `deploy/docker-compose.ci.yml` обязано её сохранять** (project name `-p acme-cismoke`, `networks: !override [cismoke_net]`, `down -v` строго CI-проекта). Слом изоляции возвращает риск затирания БД и BI-данных на dev/staging.
- **На живом dev/staging для верификации против running stack — `SMOKE_MODE=staging`** (`SMOKE_MODE=staging bash scripts/smoke-check.sh`): read-only, без мутаций, никогда не останавливает стек. Это дефолтный безопасный выбор; `SMOKE_MODE=ci` теперь тоже безопасен рядом с живым стеком (изоляция выше), но `staging` остаётся каноном для проверки самого running-стека. **Не вызывать деструктивных compose-команд (`down`, `down -v`, `up --force-recreate`, удаление томов) против dev-проекта `acme-platform`** — это и есть вектор потери данных. См. Сценарий F в `docs/runbooks/DEPLOY.md`.
- **`tests/smoke/` — домашний адрес smoke-тестов.** Используют `SMOKE_MODE` фикстуру из `tests/smoke/conftest.py` для переключения между CI/staging/prod. Один файл теста — три окружения без дублирования логики.

## 7. Definition of done

A change is done when **all** of these are true:

- [ ] Acceptance criteria documented and met.
- [ ] Tests added/updated and green locally (`scripts/quality-check.sh`).
- [ ] Smoke path passes (`scripts/smoke-check.sh`).
- [ ] No new lint/type errors.
- [ ] Migrations are reversible or have a documented forward-recovery plan.
- [ ] Observability (logs/metrics/traces) covers the new code path.
- [ ] `docs/reference/DATA-MODEL.md` updated if any of the following changed: API field mapping (`_RULES`, `_AMOUNT_CAMEL`, `map_row`), `metric_article` taxonomy, ETL counter-row logic, dataset SQL columns/formulas, or dashboard chart metrics.
- [ ] Reviewer signed off, blockers resolved.
- [ ] Release notes drafted (`release.md`).
- [ ] Manual acceptance checklist в `release.md` заполнен и пройден (§10 шаблона `docs/features/release.template.md`).

## 8. Migration & change management

- Schema changes ship in **two phases** (expand → migrate → contract) when they touch live tables.
- Backfills run as idempotent jobs; never inline in a request handler.
- Feature flags wrap any change that alters user-visible behavior.
- Removing a flag is a follow-up PR with its own DoD.

## 9. Security & secrets

- **No secrets in the repo.** Ever. Use the host's secret store / `.env` (gitignored).
- Treat all external input as hostile: validate, parameterize, encode on output.
- AuthN/AuthZ checks happen at the service boundary, not in the UI.
- PII access is logged. Cryptography uses vetted libraries, never roll your own.
- New dependencies require justification and a license/vuln check.

## 10. Review checklist (reviewer must enforce)

- Correctness vs. acceptance criteria.
- Tests cover the contract, not the implementation.
- No scope creep, no incidental refactors mixed in.
- No new abstraction without ≥3 concrete callers.
- Error paths handled; no swallowed exceptions.
- Security: input validation, authz, secret handling.
- Performance: obvious N+1, unbounded loops, missing indexes.
- Observability: structured logs at boundaries; metrics on new paths.
- Migrations: reversible or documented.
- Docs updated (PRD/API/runbook as applicable).
- `docs/reference/DATA-MODEL.md` updated if API mapping, metric taxonomy, ETL logic, or dashboard metrics changed (see §7 DoD).

## 11. Release checklist (release-engineer must enforce)

Stage 6 пересекает машинную границу: pre-deploy выполняется на dev-машине/CI
(MacBook), post-deploy — на staging VPS. Это **один** stage, **один** агент,
**один** артефакт (`release.md`), но с явной точкой передачи (HANDOFF). Агент
обязан остановиться после Phase A и НЕ объявлять релиз done, пока Phase B не
выполнена на VPS.

**Phase A — Pre-deploy (dev-машина / CI):**

- [ ] CI green on the merge commit.
- [ ] `scripts/quality-check.sh` green (format + lint + typecheck + unit tests).
- [ ] `SMOKE_MODE=ci bash scripts/smoke-check.sh` green на CI (ephemeral stack).
- [ ] `release.md` §§1–9 заполнены; env/secrets diff и migration/rollback plan описаны.
- [ ] Изменения (включая draft `release.md`) запушены в `main`.

→ **HANDOFF:** переключиться на staging VPS, выполнить Phase B. Возобновление —
по `release.md`: §§1–9 готовы, осталось §10.

**Phase B — Post-deploy (staging VPS).** Phase B имеет **два раздельных дельвербла** —
их нельзя схлопывать: пропуск (A) обязан быть виден в чеклисте и вердикте, даже если (B)
прошёл. GO требует **оба**.

**(A) Релиз-артефакт — трассируемость (тег + CHANGELOG + GitHub Release):**

- [ ] SemVer-тег `vX.Y.Z` создан **ДО деплоя** на release-authoring машине
      (`docs/runbooks/DEPLOY.md` → «Релизный процесс»): `git fetch origin --tags` →
      `git cliff --tag vX.Y.Z -o CHANGELOG.md` → commit CHANGELOG →
      `git tag -a vX.Y.Z` → `git push origin vX.Y.Z` → `gh release create vX.Y.Z`.
- [ ] Гейт AC-6 подтверждён: `git describe --tags --exact-match` на теговом коммите
      даёт точный `vX.Y.Z` — иначе деплой (Сценарий B) REFUSE, GO невозможен.
- [ ] CHANGELOG.md обновлён и запушен; GitHub Release опубликован.

**(B) Staging-деплой + приёмка:**

- [ ] `git pull origin main` на VPS; деплой инкремента по `docs/runbooks/DEPLOY.md` §B.
- [ ] `SMOKE_MODE=staging bash scripts/smoke-check.sh` green против running stack.
- [ ] Manual acceptance checklist (release.md §10) пройден вручную (включая GlitchTip UI).
- [ ] Env vars/secrets present in target env; diffs noted.
- [ ] Feature flags default state confirmed.
- [ ] Owner + on-call notified; release notes posted.

**Вердикт (дисциплина, §4):** GO обязан **явно перечислить каждый** обязательный пункт
(A) и (B) с отметкой ✓/✗. Любой ✗ = **NO-GO** либо письменный waiver с обоснованием
прямо в `release.md`. «Тихий GO» с умолчанием про непокрытый пункт (например, пропущенный
релиз-тег) недопустим — если пункт не перечислен, вердикт невалиден.

- [ ] GO/NO-GO вердикт проставлен в `release.md` с поимённым перечислением (A)+(B); финальный commit запушен.

## 12. When to use each subagent

| Need | Agent |
|---|---|
| Turn a vague product request into a scoped brief | `planner` |
| Decide data model / API / integration approach | `architect` |
| Pin behavior with failing tests before any code | `tdd-engineer` |
| Write the minimum code to satisfy plan + tests | `implementer` |
| Adversarial review of a diff before merge | `reviewer` |
| Verify release readiness (build, smoke, rollback) | `release-engineer` |

Do **not** ask one agent to do another's job. If you find yourself wanting to, stop and re-route.

**implementer** обязан перед открытием PR:
1. Запустить `TEST_DATABASE_URL=<local_postgres> scripts/quality-check.sh` — весь набор тестов, включая интеграционные. Скип тестов из-за отсутствия `TEST_DATABASE_URL` не считается "green".
2. Убедиться, что интеграционные тесты не скипаются молча — итоговая строка pytest должна содержать `passed`, а не только `skipped`.

Если локальный Postgres недоступен — зафиксировать это явно в PR-описании с причиной. Молчаливый skip = красный.

## 13. Never do this

- Never edit production code without a failing test (or a written waiver in the PR).
- Never modify tests to make them pass without re-validating the contract.
- Never merge with unresolved reviewer blockers.
- Never `--no-verify`, `--force-push` to `main`, or skip CI.
- Never assert merge/branch/PR state from local git refs without a fresh `git fetch origin` (or `gh`) — local `main` and remote-tracking refs go stale, especially in the two-account setup where the other account merges PRs.
- Never add a dependency you have not read the README of.
- Never introduce a new abstraction "for the future."
- Never ship a migration without a rollback story.
- Never log secrets, tokens, or PII in plaintext.
- Never delete files or branches you did not create without explicit instruction.
- Never claim "done" without running `scripts/quality-check.sh`.
- Never write a test that calls a real external API without `@pytest.mark.live_api`.
- Never use a third-party sandbox environment as a substitute for fixture-based mocking: sandbox rate limits are the same or lower than production, and data is randomly generated (unsuitable for domain logic).

## 14. Repo conventions

- **Feature folders.** `docs/features/<slug>/` holds brief / plan / test-matrix / review / release.
- **Templates.** `docs/product/*.template.md` and `docs/architecture/*.template.md` are the canonical starting points — copy, don't reinvent. `docs/features/release.template.md` — шаблон release.md для Stage 6; содержит обязательную §10.0 Release-артефакт (тег/CHANGELOG/Release — GO-блокер Phase B), обязательный §10 Manual acceptance checklist и HANDOFF-маркер между Phase A (pre-deploy, dev-машина/CI) и Phase B (post-deploy, staging VPS) — см. §11.
- **Scripts.** `scripts/quality-check.sh` is the single entry point for local checks. `scripts/smoke-check.sh` is the single entry point for end-to-end smoke. `scripts/followups.sh` lists open follow-ups from GitHub Issues (label `followup`) — see §4 Follow-up lifecycle and `docs/runbooks/FOLLOWUPS.md`.
- **Stack commands.** Where stack-specific commands are needed, they live in `scripts/*.sh` behind named functions — never inline in docs.
- **Data model reference.** `docs/reference/DATA-MODEL.md` is the living source of truth for the data layer: API field mapping, `metric_article` taxonomy, ETL counter-row logic, dataset SQL columns, and dashboard chart metrics. It **must** be updated in the same PR whenever any of these change — it is not optional documentation.
- **Documentation language.** All `docs/` artifacts (brief, plan, test-matrix, review, release, runbooks) are written in **Russian**. Code identifiers, file paths, CLI commands, Gherkin keywords, and technical terms (STT, TTS, WebSocket, PCM16, etc.) remain in English.

## 15. When in doubt

Stop and ask. A clarifying question is cheaper than an undo.

## 16. Role-agnostic workflow (two-account setup)

Two Claude Code Pro accounts (`acc1`, `acc2`) share one GitHub remote. Either account can perform **any** stage — no fixed role binding.

**Structure per feature slice:**
- One branch per slice: `feature/<slug>-stage1`, `feature/<slug>-stage2`, …
- Each stage = one PR → human approval → merge → next stage starts

**Session startup** (exact paths in `docs/runbooks/GIT-WORKFLOW-COMMANDS.md`):
```bash
# acc1
cd <path-to-acc1-repo>
export CLAUDE_CONFIG_DIR=~/.claude-acc1
claude

# acc2
cd <path-to-acc2-repo>
export CLAUDE_CONFIG_DIR=~/.claude-acc2
claude
```

**Parallel work:** While acc2 works on S1 stage 3, acc1 can start S2 stage 1. Slices that touch different `src/` paths are fully independent (e.g. S1 `src/data/` vs S3 `src/voice/`).

**Commit message format:** `[STAGE N/6] <verb>: <one-line description>`

Full commands → `docs/runbooks/GIT-WORKFLOW-COMMANDS.md`
Approval guide → `docs/runbooks/HUMAN-APPROVAL-GUIDE.md`

**Infrastructure ownership (single stack owner):**
- One account owns and starts the shared stack (postgres, BI tool, tracing/observability, etc.). The other account only connects to already-running containers via shared `container_name` values.
- The stack is defined in `deploy/docker-compose.yml` and identified by `name: acme-platform` (→ network `acme-platform_acme_net`, consistent from any repo clone).
- Infrastructure changes (`deploy/**`, `Dockerfile`, `scripts/*.sh`) go through a PR — never edited locally without committing. A local `M` on `deploy/docker-compose.yml` that diverges between accounts is a bug.
- Bootstrap a fresh network once: `docker network create acme_net` if it does not exist, then `docker compose up -d` from the owner account.
- All infra services (postgres, BI tool, tracing, redis) are managed together from `deploy/` by the owner — never start individual services from acc2.
- Never `docker restart <service>` to fix problems. The correct path: `docker compose up -d --build <service>` from `deploy/`. Restart preserves a broken worker state; recreation from compose does not.
- `container_name` is fixed in compose. Never run a container with a different name — it breaks DNS resolution for all services in the network.
- When migrating volumes after a project name change: `docker run --rm -v <old>:/src:ro -v <new>:/dst alpine sh -c "cp -a /src/. /dst/"`. Never delete the old volume until the new one is verified.

**Release authoring vs consume-only (release-traceability):**
- Релиз (SemVer-тег + GitHub Release + CHANGELOG через `git-cliff`) рождается **один раз**, на **release-authoring машине** — той, где есть write в GitHub И `git-cliff`. Это **dev/CI или staging-хост** (`staging.example.com`): на staging-хосте `gh` авторизован, `git-cliff` стоит готовым бинарём в `/usr/local/bin` (не в образе, не в `pyproject.toml`/`uv.lock`). Так Phase B делается одним заходом на staging.
- **Prod-хост — строго consume-only (инвариант):** только `git fetch --tags` → checkout тега → build. Prod **никогда** не создаёт теги/Releases; **git-cliff на prod не ставится** (реальный prod `app.example.com` — минимальная поверхность). Один тег в каталоге GitHub, окружения выбирают его независимо; `env` в `/version` (из `APP_ENV` хоста) отличает одну и ту же версию по среде. Детали и команды — `docs/runbooks/DEPLOY.md` → «Релизный процесс».

**BI dashboard versioning (code-as-config)** — пример: Apache Superset, паттерн применим к любому BI-инструменту с git-экспортируемыми дашбордами:
- `deploy/bi/assets/` is the single source of truth for all BI content (databases, datasets, charts, dashboards). It is committed to git — never configure dashboards only through the UI.
- UUIDs in YAML files are permanent identifiers. Never regenerate or change them — the BI tool uses UUID for upsert on import; changing a UUID creates a duplicate object.
- To update a dashboard: edit the YAML → `docker compose up --build -d bi` from `deploy/` (or run `import_assets.sh` without rebuild). `overwrite=true` is always set in both scripts.
- To capture UI changes back into code: run `export_assets.sh` → unzip → copy updated YAMLs into `assets/` → commit.
- `APP_DB_PASSWORD` env var must be set (taken from `POSTGRES_PASSWORD` in `.env`) — it is substituted into `databases/app.yaml` at import time. Never hardcode the password in YAML.
- `deploy/bi/backups/` is gitignored — backups are local only, not versioned.

## 17. Automated review with Claude

Every PR can be checked with the `/review` slash command (Claude Code skill) before human approval. This is distinct from the `reviewer` subagent (§12), which performs adversarial post-implementation review and writes `review.md`.

```bash
# inside Claude Code session on the repo
/review                  # list open PRs
/review <PR-number>      # review specific PR via gh pr diff
```

The skill reads the PR diff via `gh pr diff`, checks against `plan.md`, `test-matrix.md`, and CLAUDE.md criteria. It outputs either a list of blockers or "Approved for merge". Human reads the output and decides approve/reject. If rejected — add a GitHub PR comment; the account reworks and pushes to the same branch.
