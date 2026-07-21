#!/usr/bin/env bash
# Показать build-метаданные запущенного прод-mcp-server двумя каналами
# (release-traceability, см. docs/runbooks/VERSION-CHECK.md):
#   (a) HTTP GET /version  — рантайм-ответ приложения (version/git_sha/built_at/env);
#   (b) docker inspect      — OCI-лейблы образа (revision/version/created) по SSH.
#
# Точка запуска — dev-машина: у неё есть SSH к прод-VPS (→ docker inspect) и GitHub read.
# Скрипт read-only, прод НЕ мутирует. Graceful degradation (R6): отсутствие jq/ssh/curl
# не роняет весь запуск — печатается доступное; ненулевой код только при полной
# недоступности (оба канала недоступны).
#
# Параметры через env:
#   PROD_URL  — базовый URL (default https://app.example.com)
#   PROD_HOST — хост VPS для SSH (default 203.0.113.10)
#   SSH_USER  — пользователь SSH (default root)

set -euo pipefail
IFS=$'\n\t'

PROD_URL="${PROD_URL:-https://app.example.com}"
PROD_HOST="${PROD_HOST:-203.0.113.10}"
SSH_USER="${SSH_USER:-root}"
# mcp-server без явного container_name → compose именует его <project>-mcp-server-1.
# Переопределяется через MCP_CONTAINER, если проект/имя иные.
MCP_CONTAINER="${MCP_CONTAINER:-acme-platform-mcp-server-1}"

have() { command -v "$1" >/dev/null 2>&1; }

section() {
  printf '\n\033[1;34m▶ %s\033[0m\n' "$1"
}

# (a) HTTP-канал: GET /version. Возвращает 0 при 200, 1 иначе.
http_channel() {
  section "HTTP  GET ${PROD_URL}/version"
  if ! have curl; then
    echo "WARN: curl не найден — пропускаю HTTP-канал"
    return 1
  fi
  local body
  if ! body="$(curl -fsS "${PROD_URL}/version" 2>/dev/null)"; then
    echo "WARN: ${PROD_URL}/version недоступен или вернул не-2xx"
    echo "      (404 = эндпоинт не задеплоен / старый образ / Caddy-роут не синхронизирован на VPS)"
    return 1
  fi
  if have jq; then
    echo "$body" | jq .
  else
    echo "$body"
    echo "(jq не установлен — сырой JSON; brew install jq для форматирования)"
  fi
}

# (b) SSH-канал: docker inspect OCI-лейблов образа mcp-server. Возвращает 0 при успехе.
inspect_channel() {
  section "SSH  docker inspect ${MCP_CONTAINER}@${PROD_HOST} (OCI labels)"
  if ! have ssh; then
    echo "WARN: ssh не найден — пропускаю inspect-канал"
    return 1
  fi
  local fmt='{{index .Config.Labels "org.opencontainers.image.version"}} | '
  fmt+='{{index .Config.Labels "org.opencontainers.image.revision"}} | '
  fmt+='{{index .Config.Labels "org.opencontainers.image.created"}}'
  local out
  if ! out="$(ssh -o ConnectTimeout=10 "${SSH_USER}@${PROD_HOST}" \
      "docker inspect --format '${fmt}' ${MCP_CONTAINER}" 2>/dev/null)"; then
    echo "WARN: SSH/docker inspect недоступен (нет доступа к ${PROD_HOST} или контейнера ${MCP_CONTAINER})"
    return 1
  fi
  echo "version | revision | created"
  echo "$out"
}

main() {
  local http_ok=0 inspect_ok=0
  http_channel && http_ok=1 || true
  inspect_channel && inspect_ok=1 || true

  if [[ "$http_ok" -eq 0 && "$inspect_ok" -eq 0 ]]; then
    printf '\n\033[31m✗ оба канала недоступны — версию установить не удалось\033[0m\n'
    exit 1
  fi
  printf '\n\033[1;32m✓ prod-version: получено по %s из 2 каналов\033[0m\n' "$((http_ok + inspect_ok))"
}

main "$@"
