# Проверка версии развёрнутого сервиса (release-traceability)

Как узнать, **какой именно код** сейчас запущен в окружении (prod / staging / dev),
и дойти от версии до списка вошедших изменений. Слой трассируемости — два независимых
источника, оба baked в образ на сборке:

- **`GET /version`** — рантайм-ответ `mcp-server` (что реально исполняется);
- **OCI-лейблы образа** (`docker inspect`) — метаданные без запуска, доступны для всех
  трёх сервисов (`app` / `telegram-bot` / `mcp-server`), собранных из одного `deploy/Dockerfile`.

## Поля ответа `/version`

```json
{ "version": "v1.4.0", "git_sha": "3f2a9c8e…", "built_at": "2026-07-17T09:41:12Z", "env": "prod" }
```

| Поле | Значение | Источник |
|---|---|---|
| `version` | SemVer-тег образа (`vX.Y.Z`); `unknown` — образ собран без тега | build-arg `VERSION` → `APP_VERSION` |
| `git_sha` | Полный git SHA сборки (40 hex); суффикс `-dirty` — грязное дерево; `unknown` — без build-arg | build-arg `GIT_SHA` → `APP_GIT_SHA` |
| `built_at` | ISO-8601 UTC время сборки образа | build-arg `BUILD_TIME` → `APP_BUILD_TIME` |
| `env` | Самоидентификация окружения `{local,dev,staging,prod}` | per-host `APP_ENV` (`get_settings().app_env`) |

`env` — единственное per-host поле (из `.env` хоста), остальные три baked в образ.
Тело содержит **ровно** эти четыре поля — секретов (DSN/токены/пароли) в нём нет by design.

## Процедуры по каналам

Хосты: prod `https://app.example.com`, staging `https://staging.example.com`,
dev — локально `http://127.0.0.1:8765` (порт mcp-server).

### Канал 1 — браузер / curl (рантайм)

```bash
curl -fsS https://app.example.com/version | jq .     # prod
curl -fsS https://staging.example.com/version | jq .  # staging
curl -fsS http://127.0.0.1:8765/version | jq .       # dev (внутри стека)
```

Через браузер — просто открыть `<host>/version`. Публичный роут, без авторизации.

### Канал 2 — docker inspect (OCI-лейблы образа, без запуска)

На хосте с доступом к Docker-демону (по SSH для VPS):

```bash
docker inspect --format \
  '{{index .Config.Labels "org.opencontainers.image.version"}} | {{index .Config.Labels "org.opencontainers.image.revision"}} | {{index .Config.Labels "org.opencontainers.image.created"}}' \
  acme-platform-mcp-server-1
# → v1.4.0 | 3f2a9c8e… | 2026-07-17T09:41:12Z
```

Работает и для `app` / `telegram-bot` (те же лейблы, один Dockerfile) — так проверяется
версия сервисов без HTTP-эндпоинта.

### Канал 3 — обёртка `scripts/prod-version.sh` (оба канала разом)

Запускается **с dev-машины** (есть SSH к прод-VPS + GitHub read):

```bash
bash scripts/prod-version.sh
# env-переопределения: PROD_URL / PROD_HOST / SSH_USER / MCP_CONTAINER
```

Печатает HTTP-`/version` + `docker inspect` OCI-лейблов. Graceful degradation: если один
канал недоступен (нет SSH / нет `jq` / 404) — печатает доступное; падает только когда
недоступны оба.

## От версии к списку изменений (git_sha → коммит → CHANGELOG)

1. `git_sha` → коммит на GitHub:
   `https://github.com/your-org/your-project/commit/<git_sha>`
   или локально `git show <git_sha>`.
2. `version` (`vX.Y.Z`) → секция в `CHANGELOG.md` (генерируется `git cliff`, см.
   `docs/runbooks/DEPLOY.md` → Сценарий B → «Релизный процесс») и GitHub Release
   `https://github.com/your-org/your-project/releases/tag/vX.Y.Z`.
3. Диапазон между двумя развёрнутыми версиями:
   `git log <старый_sha>..<новый_sha> --oneline`.

## Операционный канон (least privilege)

- Version-check и **создание тегов/Releases** — только с **dev/CI** (есть SSH к проду
  и GitHub write). Прод-VPS теги/релизы **не** создаёт: только `git pull` /
  `git fetch --tags` (read) и отдаёт `/version`.
- Свежесть тегов перед любым суждением: `git fetch origin --tags` (CLAUDE.md §13).

## Требуемые доступы

- SSH к прод-VPS `203.0.113.10` (пользователь по умолчанию `root`) — для `docker inspect`.
- Read-доступ к репозиторию `your-org/your-project` на dev-хосте.
- Сетевой доступ к `<host>/version` (публичный, без токена).

## Установка `APP_ENV` на каждом хосте

`env` в `/version` корректен, только если в `.env` хоста выставлено правильное значение:

- dev-машина → `APP_ENV=local` (или `dev`);
- staging-VPS → `APP_ENV=staging`;
- prod-VPS → `APP_ENV=prod`.

`mcp-server` получает `.env` через `env_file: ../.env` (docker-compose) — отдельная
правка environment-секции не нужна.

## Troubleshooting

| Симптом | Причина | Действие |
|---|---|---|
| `env` не соответствует окружению | `APP_ENV` не выставлен / выставлен неверно в `.env` хоста | Исправить `APP_ENV`, пересоздать контейнер: `docker compose up -d --build mcp-server` |
| `git_sha` / `version` == `unknown` | Образ собран без build-args (dev-сборка / забыт экспорт) | Пересобрать с гейтом Сценария B (`git describe --tags` → `VERSION`, `GIT_SHA`, `BUILD_TIME`) |
| `built_at` == `unknown` | Не передан build-arg `BUILD_TIME` | То же — экспортировать `BUILD_TIME` перед `docker compose build` |
| `/version` → 404 | Caddy-роут `/version` не синхронизирован на VPS / старый образ без роута | Применить `handle /version` в живом Caddyfile VPS (`deploy/caddy/README.md`), пересобрать mcp-server |
| `-dirty` в `git_sha` | Образ собран из некоммиченного дерева | Не деплоить: гейт «нет деплоя без тега» это отбраковывает (`docs/runbooks/DEPLOY.md`) |
