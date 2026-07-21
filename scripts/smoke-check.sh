#!/usr/bin/env bash
# Single entry point for end-to-end smoke checks (CLAUDE.md §11).
# Boots the Docker stack, verifies Postgres + migrations, runs the critical path.
# Fails fast. Returns non-zero if any step fails.

set -euo pipefail
IFS=$'\n\t'

# SMOKE_MODE: ci (default) | staging | prod
# ci      — ephemeral stack: boot → seed → assert → down. Используется в CI.
# staging — assertions-only против running stack: без boot, без down, без seed.
# prod    — только read-only health checks, без мутаций.
SMOKE_MODE="${SMOKE_MODE:-ci}"

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

COMPOSE_FILE="deploy/docker-compose.yml"
CI_OVERRIDE_FILE="deploy/docker-compose.ci.yml"
CI_PROJECT="acme-cismoke"

# Хелпер: docker compose для CI-изолированного проекта (project + base + ci-override).
# Используется ТОЛЬКО в ci-ветке (boot/cleanup/health/critical_path). Изолирует CI
# от dev-стека по volume (acme-cismoke_postgres_data), network (cismoke_net) и
# container_name — см. deploy/docker-compose.ci.yml.
ci_compose() {
  docker compose -p "$CI_PROJECT" -f "$COMPOSE_FILE" -f "$CI_OVERRIDE_FILE" "$@"
}

if [ ! -f .env ]; then
  echo "✗ .env not found at repo root — copy .env.example and fill in values."
  exit 1
fi

# Export POSTGRES_USER / POSTGRES_DB for the psql calls below.
set -a
# shellcheck disable=SC1091
. ./.env
set +a

step() {
  local name="$1"; shift
  printf '\n\033[1;34m▶ %s\033[0m\n' "$name"
  "$@"
}

cleanup() {
  # staging/prod: never tear down a running stack
  [[ "$SMOKE_MODE" != "ci" ]] && return
  # Полный teardown CI-проекта: контейнеры + том acme-cismoke_postgres_data +
  # CI-private сеть acme-cismoke_cismoke_net. dev-том acme-platform_postgres_data и
  # external-сети (acme_net/acme-platform-shared) вне границ проекта -> не затрагиваются.
  ci_compose down -v >/dev/null 2>&1 || true
}
trap cleanup EXIT

# ---------- staging / prod assertions-only mode ----------
critical_path_staging() {
  # DB healthcheck (verifies alembic_version table exists) — adapt the module
  # path below to your app's own healthcheck function.
  docker compose -f "$COMPOSE_FILE" exec -T app \
    python -c "from src.persistence.db import healthcheck; raise SystemExit(0 if healthcheck() else 1)"

  # Data presence check (>= 0: real staging may have more rows than seed).
  # Replace tenant_profiles/domain_records with your own core domain tables.
  docker compose -f "$COMPOSE_FILE" exec -T postgres \
    psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t -c \
    "SELECT (SELECT COUNT(*) FROM tenant_profiles) >= 0
        AND (SELECT COUNT(*) FROM domain_records) >= 0" \
    | grep -q ' t$'

  # ---- add ONE non-destructive exercise of your most important business
  # logic here (a read-only tool call, a report generator, etc.), following
  # the same "run in the app container, assert on stdout" pattern. ----

  # GlitchTip ingest probe: проверяет, что DSN настроен и события принимаются.
  # init вызывается явно здесь, т.к. приложение может не инициализировать его
  # само при определённых конфигурациях — держите это как отдельный smoke-гейт.
  docker compose -f "$COMPOSE_FILE" exec -T app \
    python -c "
import sentry_sdk, os
dsn = os.environ.get('GLITCHTIP_DSN')
assert dsn, 'GLITCHTIP_DSN not set — observability not configured'
sentry_sdk.init(dsn=dsn)
event_id = sentry_sdk.capture_message('smoke ingest probe')
sentry_sdk.flush(timeout=10)
assert event_id, 'GlitchTip did not accept event'
print('GlitchTip ingest OK, event_id=' + str(event_id))
"
}

# /version read-only assert (release-traceability, CLAUDE.md §11): публичный роут
# отдаёт 200 + ровно 4 поля {version,git_sha,built_at,env}, env == текущее окружение,
# без секретов. Только staging/prod (в CI mcp-server не поднят). URL берётся из .env
# (STAGING_URL/PROD_URL) + путь /version — тот же публичный эндпоинт, что и в браузере.
version_endpoint_check() {
  local base expected
  if [[ "$SMOKE_MODE" == "staging" ]]; then
    base="${STAGING_URL:-}"; expected="staging"
  else
    base="${PROD_URL:-}"; expected="prod"
  fi
  if [[ -z "$base" ]]; then
    echo "SKIP: base URL для ${SMOKE_MODE} не задан (STAGING_URL/PROD_URL) — /version не проверяется"
    return 0
  fi
  local url="${base%/}/version" body
  body="$(curl -fsS "$url")" || { echo "FAIL: GET $url недоступен/не-2xx (404 = эндпоинт не задеплоен)"; return 1; }
  for key in version git_sha built_at env; do
    echo "$body" | grep -q "\"$key\"" || { echo "FAIL: $url — нет поля '$key'"; return 1; }
  done
  echo "$body" | grep -q "\"env\"[[:space:]]*:[[:space:]]*\"$expected\"" \
    || { echo "FAIL: $url — env != '$expected': $body"; return 1; }
  for needle in DATABASE_URL MCP_ password 'postgresql://' 'postgres://'; do
    echo "$body" | grep -q "$needle" && { echo "FAIL: $url — тело содержит секрет '$needle'"; return 1; }
  done
  echo "/version OK (${url}), env=${expected}"
}

if [[ "$SMOKE_MODE" == "staging" || "$SMOKE_MODE" == "prod" ]]; then
  step "Critical path (${SMOKE_MODE} assertions)" critical_path_staging
  step "Version endpoint (${SMOKE_MODE})" version_endpoint_check
  printf '\n\033[1;32m✓ smoke-check (%s) passed\033[0m\n' "$SMOKE_MODE"
  exit 0
fi

# ---------- 1. boot ----------
boot_app() {
  # Только postgres (в cismoke_net). app — one-shot run --rm в critical_path ->
  # нет контейнера app под restart-политикой на пустой БД -> нет restart-loop.
  ci_compose up -d --build postgres
}

# ---------- 2. health ----------
health_check() {
  local tries=30
  until [ "$(ci_compose ps postgres --format '{{.Health}}')" = "healthy" ]; do
    tries=$((tries - 1))
    [ "$tries" -gt 0 ] || { echo "postgres did not become healthy"; exit 1; }
    sleep 2
  done
  echo "postgres healthy"
}

# ---------- 3. critical path E2E ----------
critical_path() {
  ci_compose run --rm --no-deps app alembic upgrade head

  ci_compose run --rm --no-deps app \
    python -c "from src.persistence.db import healthcheck; raise SystemExit(0 if healthcheck() else 1)"

  ci_compose exec -T postgres \
    psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f /seed/seed_phase_a.sql

  # Строгий глобальный инвариант сида: БД изолирована (volume + network) и пуста
  # до seed -> COUNT(*) = expected корректен. Замените имена таблиц и ожидаемые
  # количества на контракт вашего собственного seed_phase_a.sql.
  ci_compose exec -T postgres \
    psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t -c \
    "SELECT (SELECT COUNT(*) FROM tenant_profiles)::int = 1
        AND (SELECT COUNT(*) FROM domain_records)::int > 0" \
    | grep -q ' t$'

  # ---- add ONE non-destructive exercise of your most important business
  # logic here, run against the freshly-seeded CI database. Assert on a
  # concrete, deterministic outcome — this is your strongest regression net. ----
}

# bi/glitchtip в CI не поднимаются -> экспорты host-портов не нужны.
# CI-private cismoke_net создаёт сам docker compose при up; dev-сети
# (acme_net/acme-platform-shared) CI-app не использует -> отдельный ensure_network
# не требуется.

step "Boot"           boot_app
step "Health"        health_check
step "Critical path" critical_path

printf '\n\033[1;32m✓ smoke-check passed\033[0m\n'
