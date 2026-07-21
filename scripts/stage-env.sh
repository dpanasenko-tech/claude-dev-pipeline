#!/usr/bin/env bash
# scripts/stage-env.sh — операционный CLI изолированного долгоживущего stage-окружения.
# Slice stage-env-multiplex (plan §2.3). Форма stage_compose() наследует ci_compose()
# из scripts/smoke-check.sh: project name задаётся ЯВНО (-p) как защита от затирания dev.
#
# Использование:
#   STAGE_ENV=stage bash scripts/stage-env.sh {up|down|destroy|config|selfcheck|ps|logs}
#
# STAGE_ENV выбирает файл переменных deploy/.env.<STAGE_ENV> (default: stage).
# Отсутствие файла -> hard-fail ДО любого docker-действия (Neg-3: нет тихого фолбэка на dev ../.env).
set -euo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd -- "$HERE/.." && pwd)"
cd "$ROOT"

BASE_COMPOSE="deploy/docker-compose.yml"
STAGE_OVERLAY="deploy/docker-compose.stage.yml"

STAGE_ENV="${STAGE_ENV:-stage}"
STAGE_ENV_PATH="deploy/.env.${STAGE_ENV}"

# --- Neg-3: env-файл обязателен ДО любого docker-действия (нет фолбэка на dev ../.env) ---
if [ ! -f "$STAGE_ENV_PATH" ]; then
  echo "✗ stage env file not found: $STAGE_ENV_PATH" >&2
  echo "  (нет тихого фолбэка на dev ../.env — создайте файл из deploy/.env.stage.example)" >&2
  exit 1
fi

# Источник интерполяции ${...} для compose + переменные для guard'ов ниже.
set -a
# shellcheck disable=SC1090
. "$STAGE_ENV_PATH"
set +a

: "${STAGE_PROJECT:?STAGE_PROJECT must be set in $STAGE_ENV_PATH}"

# --- Neg-1: overlay НИКОГДА не нацеливается на боевые проекты ---
case "$STAGE_PROJECT" in
  acme-platform | acme-platform-demo)
    echo "✗ refuse to target project '$STAGE_PROJECT' — stage overlay must never touch acme-platform/acme-platform-demo" >&2
    echo "  (инвариант защиты данных CLAUDE.md §6/§16)" >&2
    exit 1
    ;;
esac

# Ровно 5 сервисов stage. redis/glitchtip/caddy наследуются из base, но их
# НЕ поднимаем: `up` явно перечисляет этот список (иначе bare up стартанул бы singleton'ы).
STAGE_SERVICES=(postgres app telegram-bot mcp-server bi)

# Хелпер: project + base + stage-overlay + stage-env-файл. -p задаётся всегда явно.
stage_compose() {
  docker compose -p "$STAGE_PROJECT" --env-file "$STAGE_ENV_PATH" \
    -f "$BASE_COMPOSE" -f "$STAGE_OVERLAY" "$@"
}

# selfcheck — bash/python-ассерты изоляции из рендера `config` (без обращения к демону).
selfcheck() {
  local rendered
  local rendered
  rendered="$(stage_compose config --format json 2>/dev/null || true)"
  if [ -z "$rendered" ]; then
    echo "✗ selfcheck: 'docker compose config' produced no output (merge/interpolation error)" >&2
    exit 1
  fi
  # python3 -c (не `- <<'PY'`): при heredoc stdin занят текстом программы и json.load(sys.stdin)
  # получил бы пусто — stdin оставляем пайпу с рендером.
  printf '%s' "$rendered" | STAGE_PREFIX="$STAGE_PREFIX" python3 -c '
import json, os, sys

EXPECTED = {"postgres", "app", "telegram-bot", "mcp-server", "bi"}
SINGLETON = {"glitchtip", "caddy", "redis"}
prefix = os.environ["STAGE_PREFIX"]

doc = json.load(sys.stdin)
services = doc.get("services", {})
names = set(services)

# config рендерит ВСЕ 8 сервисов base+overlay; проверяем только 5 stage и что overlay
# не переопределил singleton (glitchtip/caddy/redis остаются base-сетевыми, не stage_net).
missing = EXPECTED - names
if missing:
    sys.exit(f"selfcheck: stage services missing from render: {sorted(missing)}")

for svc in EXPECTED:
    cfg = services[svc]
    nets = cfg.get("networks") or {}
    net_names = set(nets) if isinstance(nets, dict) else set(nets)
    if net_names != {"stage_net"}:
        sys.exit(f"selfcheck: {svc} networks={sorted(net_names)}, expected [stage_net] "
                 f"(external acme_net must be stripped by !override)")
    cn = cfg.get("container_name", "")
    if not cn.startswith(prefix):
        sys.exit(f"selfcheck: {svc} container_name {cn!r} not prefixed with {prefix!r}")

for sng in SINGLETON:
    cfg = services.get(sng)
    if cfg is None:
        continue
    nets = cfg.get("networks") or {}
    net_names = set(nets) if isinstance(nets, dict) else set(nets)
    if "stage_net" in net_names:
        sys.exit(f"selfcheck: singleton {sng} must NOT join stage_net (got {sorted(net_names)})")

print(f"✓ selfcheck: {len(EXPECTED)} stage services on stage_net only, prefixed; "
      f"singleton glitchtip/caddy/redis not on stage_net")
'
}

cmd="${1:-}"
[ "$#" -gt 0 ] && shift || true
case "$cmd" in
  up)
    # B3-guard: дорогой stage-BI-инструмент ОБЯЗАН быть предварительно ретегнут — иначе compose
    # тихо пересобрал бы его из контекста (пик RAM убил бы 8 GB коробку). Явный fail вместо тихой сборки.
    # (app/telegram-bot/mcp-server собираются штатно на первом up — дёшево, слои кэшированы из dev.)
    if ! docker image inspect "$STAGE_BI_IMAGE" >/dev/null 2>&1; then
      echo "✗ образ '$STAGE_BI_IMAGE' не найден — сначала ретег (STAGE-ENV.md §2):" >&2
      echo "    docker tag acme-platform-bi:latest $STAGE_BI_IMAGE" >&2
      echo "  (без ретега compose тихо пересобрал бы stage-BI — пик RAM)" >&2
      exit 1
    fi
    # Без аргументов поднимаются РОВНО 5 сервисов; с аргументами — только они (subset,
    # напр. `up postgres mcp-server bi` без `app`, чтобы cron_runner не ходил во внешний API).
    if [ "$#" -gt 0 ]; then
      stage_compose up -d "$@"
    else
      stage_compose up -d "${STAGE_SERVICES[@]}"
    fi
    ;;
  down)      stage_compose down "$@" ;;
  # Neg-2: `down -v` несуществующего проекта и так возвращает 0 (проверено) -> без `|| true`,
  # чтобы реальный сбой (напр. занятый том) не маскировался (S1/review, CLAUDE.md §3).
  destroy)   stage_compose down -v "$@" ;;
  config)    stage_compose config "$@" ;;
  exec)      stage_compose exec "$@" ;;
  ps)        stage_compose ps "$@" ;;
  logs)      stage_compose logs "$@" ;;
  selfcheck) selfcheck ;;
  *)
    echo "usage: STAGE_ENV=<name> bash scripts/stage-env.sh {up [svc...]|down|destroy|config|exec <svc> <cmd...>|selfcheck|ps|logs}" >&2
    exit 2
    ;;
esac
