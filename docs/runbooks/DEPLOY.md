# Руководство по деплою

Три окружения: **local** (ноутбук разработчика), **staging** (VPS), **production** (VPS).
Стек управляется через `deploy/docker-compose.yml` (проект `acme-platform`).

> **Помимо основного стека `acme-platform`** на том же VPS живут дополнительные изолированные
> compose-проекты поверх той же базы `docker-compose.yml` (overlay-only): `acme-platform-demo`
> (демо-срез) и `acme-platform-stage` (долгоживущее stage-окружение для параллельной разработки).
> Полный операционный runbook stage-механизма — **`docs/runbooks/STAGE-ENV.md`**; здесь, в
> Сценарии H, — только точка входа и карта портов. Все три проекта берут compose-файлы из
> ОДНОГО клона `~/projects/acme-platform-acc2/deploy/` (общий deploy-клон), различаясь
> только `-p <project>` и overlay-файлом.

> **Правило:** никогда не используй `docker restart <service>` для "починки". Только `docker compose up -d --build <service>` из `deploy/`.

---

## ⚠️ Правила безопасности для агентов на staging VPS

Эти правила предотвращают потерю данных. Агент ОБЯЗАН прочитать их перед любым действием на staging.

| Запрещено | Допустимо |
|---|---|
| `bash scripts/smoke-check.sh` (CI mode на staging) — defense-in-depth | `SMOKE_MODE=staging bash scripts/smoke-check.sh` |
| `docker compose down -v` | `docker compose down` (без -v) |
| `docker compose up -d --build` (пересобирает весь стек) | `docker compose up -d --build app mcp-server telegram-bot` (сервисы из `src/`) |
| `docker restart <service>` | `docker compose up -d --build <service>` |
| Редактировать `src/**`, `tests/**` на сервере | Читать логи, запускать `alembic upgrade head` |
| Запускать `scripts/quality-check.sh` на сервере | Запускать `SMOKE_MODE=staging bash scripts/smoke-check.sh` |
| Пересоздавать боевой `acme-platform` (`acme-platform-app-1`, `acme-platform-mcp-server-1`, `bi`) из dev-клона | Пересоздавать только контейнеры **своей** `acme-platform-stage*` (свой `STAGE_PREFIX`) |
| `git checkout <ветка>` в клоне, чей `../:/app` питает боевой стек | `git checkout` только в своём dev-клоне/worktree (см. Сценарий I) |

> **Про изоляцию CI-режима.** `SMOKE_MODE=ci` поднимает не общий стек `acme-platform`, а
> изолированный проект `acme-platform-cismoke` (`docker compose -p acme-platform-cismoke -f
> deploy/docker-compose.yml -f deploy/docker-compose.ci.yml`): отдельный том
> `acme-platform-cismoke_postgres_data` и CI-private сеть `acme-platform-cismoke_cismoke_net`. CI-`postgres`
> и CI-`app` работают **только** в `cismoke_net` и физически не достигают dev/staging-`postgres`
> (он в external-сети `acme_net`) — DNS-alias `postgres` внутри `cismoke_net` однозначен. Тем не
> менее запрет CI-режима на staging остаётся как **defense-in-depth**: CI-режим всё равно делает
> `down -v` своего проекта, и держать единственную команду smoke на staging в виде
> `SMOKE_MODE=staging ...` безопаснее, чем полагаться только на сетевую границу.

---

## Окружения

| Окружение | Хост | Ветка | Цель |
|---|---|---|---|
| local | localhost | любая | разработка и отладка |
| staging | `<staging-host>` — заполнить | `main` или feature-ветка | тестирование перед релизом |
| production | `<prod-host>` — заполнить | `main` (только tagged) | живые пользователи |

Для staging/prod все команды выполняются по SSH:
```bash
ssh <user>@<host>
cd /opt/acme-platform  # путь на сервере — уточнить
```

---

## Сценарий A — Первый деплой с нуля (bootstrap)

Выполняется один раз на новом хосте.

```bash
# 1. Клонировать репо
git clone https://github.com/your-org/your-project.git
cd acme-platform

# 2. Создать .env из примера и заполнить секреты
cp .env.example .env
# отредактировать .env — все значения обязательны, никаких дефолтов в prod

# 3. Создать Docker-сети (один раз на хосте)
docker network create acme_net 2>/dev/null || echo "сеть acme_net уже существует"
docker network create acme-platform-shared 2>/dev/null || echo "сеть acme-platform-shared уже существует"

# 4. Создать симлинк .env в deploy/ (обязательно — compose ищет .env в своей директории)
ln -sf ../.env deploy/.env

# 5. Собрать и поднять весь стек
cd deploy
docker compose up -d --build

# 6. Дождаться healthy
docker compose ps
# все сервисы должны быть healthy, не starting

# 7. Накатить миграции БД
docker compose exec app alembic upgrade head

# 8. Smoke-check (CI mode). Поднимает ИЗОЛИРОВАННЫЙ проект acme-platform-cismoke
#    (отдельный том acme-platform-cismoke_postgres_data + CI-private сеть cismoke_net),
#    не достигая dev/staging-postgres (см. safety-таблицу выше). Безопасен при
#    запущенном dev-стеке; на staging всё равно используй SMOKE_MODE=staging.
cd ..
SMOKE_MODE=ci bash scripts/smoke-check.sh

# 9. Инициализировать GlitchTip (admin user + org + project + API key)
bash deploy/glitchtip/init.sh
# → Creates admin, org 'acme-platform', project 'acme-platform', key из GLITCHTIP_KEY_UUID
# Idempotent: повторный запуск безопасен
```

После успешного bootstrap: `docker compose ps` показывает все сервисы в состоянии `healthy`.

---

## Сценарий B — Обновление app-кода (routine deploy)

Самый частый сценарий — вышел новый коммит в `main`.

> **Гейт до деплоя (мердж-топология).** `gh pr view … MERGED` НЕ означает «код на `main`»:
> цепочка PR с `base=предыдущая-ветка` при merge оседает в промежуточных ветках, а не в `main`.
> Перед деплоем убедиться, что нужный код реально на ветке деплоя:
> `git fetch origin && git grep '<маркер-фичи>' origin/main -- <путь>`. Ноль совпадений при
> «MERGED» PR = деплоить нечего; сначала свести код в `main` (3-way merge отдельным PR).

### Правило: нет деплоя без SemVer-тега (release-traceability #423, AC-6)

Каждый деплой собирает образ из **теговой** ревизии — версия трассируема через
`/version` и OCI-лейблы (`docker inspect`). `VERSION` для build-arg берётся **только**
из git-тега через `git describe --tags --exact-match` (единый источник, а не произвольная
строка). Untagged / грязное дерево / `latest` / `unknown` деплоить **запрещено** —
bash-гейт ниже отказывает (`exit 1`). Формат коммитов остаётся `[STAGE N/6] <verb>:`
(CLAUDE.md §16); changelog генерируется `git cliff` (см. «Релизный процесс» ниже).

```bash
cd acme-platform

# 1. Подтянуть изменения (+ теги: CLAUDE.md §13 — свежесть перед суждением о тегах)
git fetch origin --tags
git pull origin main

# 2. ГЕЙТ «нет деплоя без тега»: VERSION из git-тега, иначе REFUSE.
#    Деплой отказывается на пустом / latest / unknown / -dirty VERSION.
VERSION="$(git describe --tags --exact-match 2>/dev/null || true)"
case "$VERSION" in
  ""|latest|unknown|*-dirty)
    echo "REFUSE: деплой без валидного SemVer-тега (VERSION='$VERSION')"; exit 1;;
esac

# 3. Экспорт build-args трассируемости → пробрасываются в образ (Dockerfile ARG→ENV→LABEL).
export VERSION
export GIT_SHA="$(git rev-parse HEAD)"
export BUILD_TIME="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# 4. Пересобрать и перезапустить ВСЕ сервисы, собираемые из src/: app, mcp-server,
#    telegram-bot. Пересборка только app оставляет mcp-server (владелец публичного
#    /version за caddy) и telegram-bot на старой ревизии — bind-mount ../:/app не
#    спасает, процесс держит старый код в памяти (инцидент Phase B v0.3.0, #480).
#    postgres/bi/caddy НЕ трогаем.
cd deploy
docker compose up -d --build app mcp-server telegram-bot

# 5. Проверить что контейнеры поднялись
docker compose ps app mcp-server telegram-bot
# → должны быть healthy в течение ~30 сек

# 5b. Гейт приёмки: ПУБЛИЧНЫЙ /version (caddy → mcp-server:8765) отдаёт новый тег.
#     Проверка только OCI-лейблов acme-platform-app-1 недостаточна — она не ловит отставший
#     mcp-server (#480).
PUB_VERSION="$(curl -fsS https://staging.example.com/version | python3 -c 'import sys,json;print(json.load(sys.stdin)["version"])')"
[ "$PUB_VERSION" = "$VERSION" ] \
  || { echo "REFUSE: публичный /version='$PUB_VERSION' != тег '$VERSION' — mcp-server на старой ревизии"; exit 1; }

# 6. Накатить миграции, если они есть в этом релизе
docker compose exec app alembic upgrade head
# безопасно запускать всегда — если новых миграций нет, команда ничего не делает

# 7. Non-destructive health check против running stack
cd ..
SMOKE_MODE=staging bash scripts/smoke-check.sh
# ⚠️  НЕ запускать без SMOKE_MODE=staging — CI mode уничтожит данные

# 8. Проверить, что логи долетают до GlitchTip ПОСЛЕ накатки инкремента
docker compose -f deploy/docker-compose.yml exec -T app python -c "
import sentry_sdk, os
sentry_sdk.init(dsn=os.environ['GLITCHTIP_DSN'])
sentry_sdk.capture_message('deploy probe ' + os.popen('git rev-parse --short HEAD').read().strip())
sentry_sdk.flush(timeout=10)
print('sent')
"
# → открыть GlitchTip UI (Issues, проект acme-platform): событие 'deploy probe <SHA>'
#   должно появиться в течение ~1 мин.
#   Если события нет — observability сломана (дефект OBS-1, see followups.md),
#   деплой считается неуспешным до починки.
#
# Примечание: ручной sentry_sdk.init() в сниппете — временный обход OBS-1.
# После фикса OBS-1 проба упрощается до проверки Issues после прогона крона.
```

**Rollback при проблемах:**
```bash
git checkout <предыдущий-тег-или-коммит>
cd deploy && docker compose up -d --build app mcp-server telegram-bot
docker compose exec app alembic downgrade -1  # только если откат БД нужен
```

### Релизный процесс — тег + GitHub Release + CHANGELOG (release-traceability #423)

**Release-authoring машина.** Теги, GitHub Releases и CHANGELOG создаются **один раз**,
на выделенной release-authoring машине — той, где есть и write в GitHub, и `git-cliff`.
Это **dev/CI (MacBook) ИЛИ staging-VPS** (`acme-platform-deploy`, `staging.example.com`): на
staging-VPS `gh` авторизован и `git-cliff` установлен как готовый бинарь в `/usr/local/bin`
(не через cargo, не в образе, не в `pyproject.toml`/`uv.lock` — least surface на хосте).
Так Phase B (тег + деплой) выполняется одним заходом на staging-VPS.

**Prod-VPS — строго consume-only (инвариант, не нарушать):** только `git fetch --tags` →
checkout тегового коммита → build. Prod-VPS **никогда** не создаёт теги/Releases и **git-cliff
туда не ставится** — реальный prod (`app.example.com`, отдельная машина) остаётся с минимальной
поверхностью. Тег рождается на release-authoring машине, prod его лишь потребляет (тот же тег
через `git fetch --tags`). Свежесть тегов перед выбором номера обязательна (R3 — гонки тегов
между двумя аккаунтами).

```bash
# 1. Свежесть тегов перед выбором номера (CLAUDE.md §13).
git fetch origin --tags

# 2. Выбрать vX.Y.Z по SemVer относительно последнего тега.
git tag --sort=-v:refname | head -1   # → последний тег

# 3. Сгенерировать/обновить CHANGELOG.md из истории коммитов (git-cliff, cliff.toml).
#    git-cliff — dev/CI-инструмент (Rust-бинарь, brew install git-cliff), НЕ runtime-
#    зависимость приложения (в pyproject.toml/uv.lock не добавляется, в образ не попадает).
git cliff --tag vX.Y.Z -o CHANGELOG.md
#    инкрементально: git cliff --unreleased --prepend CHANGELOG.md
git add CHANGELOG.md && git commit -m "[STAGE 6/6] release-engineer: CHANGELOG vX.Y.Z"

# 4. Аннотированный тег + пуш.
git tag -a vX.Y.Z -m "release vX.Y.Z"
git push origin vX.Y.Z

# 5. GitHub Release с секцией changelog.
gh release create vX.Y.Z --notes-file <(git cliff --current)

# 6. VERSION для build-arg на деплое = git describe --tags --exact-match на теговом
#    коммите (AC-3: тег == OCI-label version == /version.version). См. гейт Сценария B.
```

**Формат коммитов** — `[STAGE N/6] <verb>: <описание>` (CLAUDE.md §16); `git cliff`
парсит его через `commit_parsers` в `cliff.toml` (verb → секция changelog), без перехода
на строгие `feat:`/`fix:`-префиксы.

---

## Сценарий C — Накат миграций БД

Миграции всегда идут через Alembic. Никогда не править схему вручную.

```bash
cd deploy

# Проверить текущее состояние
docker compose exec app alembic current
# → покажет revision и HEAD если всё актуально

# Накатить все новые миграции
docker compose exec app alembic upgrade head

# Проверить что дошли до HEAD
docker compose exec app alembic current
# → должно быть: <revision> (head)
```

**Rollback одной миграции:**
```bash
docker compose exec app alembic downgrade -1
```

**Правила безопасности миграций:**
- Миграция должна быть обратимой (иметь реализованный `downgrade`), иначе задокументирован forward-recovery план.
- Миграции с `ALTER TABLE` на живых таблицах выполняются по схеме expand → migrate → contract (два отдельных PR).
- Никогда не редактировать уже влитую миграцию.
- Никогда не вызывать `alembic upgrade` инлайн в request handler.

---

## Сценарий C2 — Создание read-only роли БД для MCP-сервера (i2-mcp-readonly)

На **свежем** кластере роль `acme_platform_readonly` создаётся автоматически при инициализации
postgres-контейнера (`deploy/postgres/init/03-readonly-role.sh` запускает
`scripts/db/readonly_role.sql`). На **существующем** кластере init-хук уже не сработает —
роль создаётся вручную один раз:

```bash
# На VPS, переменная MCP_READONLY_DB_PASSWORD должна быть в .env (тот же пароль, что в MCP_DATABASE_URL)
export MCP_READONLY_DB_PASSWORD="$(grep -E '^MCP_READONLY_DB_PASSWORD=' .env | cut -d= -f2-)"

# Прогнать скрипт против БД acme_platform под admin-DSN
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 \
  -v pwd="$MCP_READONLY_DB_PASSWORD" \
  -f scripts/db/readonly_role.sql

# Проверить, что роль создана и умеет логиниться
psql "$DATABASE_URL" -tA -c "SELECT rolname, rolcanlogin FROM pg_roles WHERE rolname='acme_platform_readonly'"
# → acme_platform_readonly|t
```

Скрипт **идемпотентен**: повторный прогон не падает и не пересоздаёт роль (top-level
`\gexec` выполняет `CREATE ROLE` только когда роли ещё нет; GRANT'ы переприменяются
безопасно).

**Ротация пароля.** Идемпотентный `CREATE ROLE` **не** обновляет пароль уже
существующей роли — повторный прогон скрипта оставит старый пароль. Чтобы сменить
пароль, выполните отдельный `ALTER ROLE` и синхронизируйте `MCP_DATABASE_URL`/
`MCP_READONLY_DB_PASSWORD` в `.env`:

```bash
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 \
  -c "ALTER ROLE acme_platform_readonly PASSWORD '$NEW_MCP_READONLY_DB_PASSWORD'"
```

---

## Сценарий D — Обновление инфра-образов

Когда изменился `Dockerfile` (bi, app) или версия базового образа в `docker-compose.yml`.

```bash
# 1. Изменение идёт через PR → merge в main
git pull origin main

cd deploy

# 2. Пересобрать конкретный сервис
docker compose up -d --build bi
# или: docker compose up -d --build app mcp-server telegram-bot  # сервисы из src/ — вместе (#480)
# или: docker compose up -d --build  # пересобрать всё

# 3. Дождаться healthy
docker compose ps bi
# entrypoint bi: db upgrade + init + create-admin выполняются автоматически

# 4. Для BI-инструмента — проверить подключение к БД
# http://localhost:8088 (или staging/prod URL)
# Settings → Database Connections → Test Connection → Success
```

**Volume при смене project name** (редкий случай):
```bash
# Скопировать данные из старого volume в новый
docker run --rm \
  -v <старый-volume>:/src:ro \
  -v <новый-volume>:/dst \
  alpine sh -c "cp -a /src/. /dst/"
# Проверить размеры совпадают, затем удалить старый
docker volume rm <старый-volume>
```

---

## Сценарий E — Обновление дашбордов BI-инструмента (пример: Apache Superset)

Конфигурация BI-инструмента хранится в `deploy/bi/assets/` и коммитится в git.
При каждом старте контейнера она импортируется автоматически через **CLI BI-инструмента** —
без HTTP-логина и без зависимости от пароля admin.

> **Архитектурная заметка.** Метаданные BI-инструмента (дашборды, датасеты, чарты) хранятся
> в SQLite: `/app/superset_home/superset.db` внутри контейнера. Файл находится в named
> volume `acme-platform_bi_data` и **переживает** пересборку образа — данные при
> `docker compose up --build bi` не теряются.

### Применить изменения YAML (с пересборкой образа)

Используется когда добавлены новые файлы в `assets/` или изменился `Dockerfile`:

```bash
cd deploy
docker compose up -d --build bi
```

Проверить результат:
```bash
docker compose logs --tail=30 bi | grep "\[import\]"
# Ожидаемый вывод: [import] OK: конфигурация дашбордов импортирована.
```

### Применить изменения YAML (без пересборки образа)

Если образ уже актуален, но нужно перезалить конфиг в работающий BI-инструмент:

```bash
cd deploy/bi
./import_assets.sh
# Пароль admin НЕ нужен — импорт идёт через CLI BI-инструмента напрямую в SQLite
```

### Сохранить изменения из UI обратно в git

После ручных правок дашборда через браузер:

```bash
cd deploy/bi
BI_URL=http://localhost:8088 \
BI_USER=admin \
BI_PASSWORD=<твой-пароль> \
./export_assets.sh
# ZIP сохранится в deploy/bi/backups/backup_YYYYMMDD_HHMMSS.zip
```

Затем распаковать, скопировать обновлённые YAML в `assets/`, закоммитить.

### Emergency: точечная правка через SQLite

> ⚠️ Только как крайняя мера. SQLite-правка обходит валидацию BI-инструмента,
> UUID-кэш и Flask app-context. После изменения **обязательно** пересобрать
> контейнер (`docker compose up -d --build bi`), иначе BI-инструмент будет
> работать с устаревшим кэшем.

```bash
# Посмотреть текущий json_metadata дашборда (slug=reporting)
docker compose exec -T bi \
  sqlite3 /app/superset_home/superset.db \
  "SELECT id, slug, json_metadata FROM dashboards WHERE slug='reporting';"

# Проверить целостность БД (всегда запускать после правки)
docker compose exec -T bi \
  sqlite3 /app/superset_home/superset.db "PRAGMA integrity_check;"
# → ok
```

Прямой `UPDATE` — последний резерв. Предпочтительный путь всегда —
`import_assets.sh` (CLI) или rebuild с `--build bi`.

---

## Сценарий G — Caddy на новом сервере (FirstVDS) + доступ к GlitchTip

Специфично для сервера, где `caddy` — часть самого стека `acme-platform` (не общий контейнер
чужого проекта, как раньше на Hetzner-стейдже). Два момента, которые легко забыть:

**Caddy должен видеть и `acme_net`, и `demo_net`.** `demo_net` — приватная сеть отдельного
compose-проекта `acme-platform-demo` (не `external`), поэтому подключить её сервису `caddy`
декларативно через `docker-compose.demo.yml` нельзя — он живёт в проекте `acme-platform`. Разовое
runtime-подключение после первого `up` обоих стеков:

```bash
docker network connect acme-platform-demo_demo_net acme-platform-caddy
```

Повторять после каждого пересоздания контейнера (`docker compose up -d --build caddy`) —
иначе `502` на demo-домене. Проверка: `docker exec acme-platform-caddy wget -qO- http://acme-platform-demo-bi:8088/health`.

**GlitchTip не проксируется наружу через Caddy.** Доступ только по SSH-туннелю:

```bash
ssh -L 8001:127.0.0.1:8000 root@203.0.113.10
```

Порт `8001` (не `8000`) — чтобы держать открытым одновременно с туннелем на старый
Hetzner-сервер (там GlitchTip тоже на `localhost:8000`), без конфликта портов на машине
разработчика.

---

## Сценарий H — Изолированные stage-окружения (stage-env-multiplex)

Дополнительное долгоживущее Docker-окружение на том же VPS, физически изолированное от
боевого `acme-platform` и от `acme-platform-demo`. Нужно, чтобы два аккаунта (acc1/acc2) вели параллельную
разработку без гонки версий за один стек. Механизм — overlay `deploy/docker-compose.stage.yml`
поверх **неизменной** базы `docker-compose.yml`, применяемый ТОЛЬКО через
`scripts/stage-env.sh`. Слайс `stage-env-multiplex` (PR #373).

> **Полный runbook — `docs/runbooks/STAGE-ENV.md`** (инварианты изоляции, переменные,
> сквозной путь миграций/seed, замер RAM, связка с `git worktree`, rollback). Ниже — только
> шпаргалка для деплоя.

**Карта портов (без коллизий между проектами):**

| Проект | postgres | bi | mcp-server | glitchtip | Overlay |
|---|---|---|---|---|---|
| `acme-platform` (боевой) | 5434 | 8088 | 8765 | 8000 | — (база) |
| `acme-platform-demo` | 5435 | 8089 | 8766 | — (singleton `acme-platform`) | `docker-compose.demo.yml` |
| `acme-platform-stage` | 5436 | 8090 | 8767 | — (singleton `acme-platform`) | `docker-compose.stage.yml` |
| резерв (2-й stage) | 5437 | 8091 | 8768 | — | `STAGE_ENV=stage2` |

Доступ к stage-BI/mcp — только `127.0.0.1:<port>` + SSH-туннель (caddy НЕ фронтит stage).

**Подготовка (один раз):**

```bash
cd ~/projects/acme-platform-acc2
docker tag acme-platform-bi:latest acme-platform-bi:stage   # ретег, НЕ пересборка (иначе пик RAM)
cp deploy/.env.stage.example deploy/.env.stage          # заполнить свои stage-секреты (gitignored)
```

**Деплой / операции (всегда через обёртку — она задаёт `-p acme-platform-stage` и hard-fail-guard'ы):**

```bash
STAGE_ENV=stage bash scripts/stage-env.sh selfcheck                 # ассерты изоляции до up (без демона)
STAGE_ENV=stage bash scripts/stage-env.sh up                        # поднять 5 сервисов (postgres app bot mcp bi)
STAGE_ENV=stage bash scripts/stage-env.sh up postgres mcp-server bi  # без app — cron не пойдёт во внешний API
STAGE_ENV=stage bash scripts/stage-env.sh exec app alembic upgrade heads    # миграции против stage-postgres
STAGE_ENV=stage bash scripts/stage-env.sh ps                        # состав (glitchtip/caddy/redis тут НЕТ)
STAGE_ENV=stage bash scripts/stage-env.sh logs -f bi
STAGE_ENV=stage bash scripts/stage-env.sh down                      # стоп, тома целы
STAGE_ENV=stage bash scripts/stage-env.sh destroy                   # down -v строго ${STAGE_PROJECT}_* (идемпотентно)
```

**Инварианты (load-bearing, не сломать):**

- `scripts/stage-env.sh` жёстко отвергает `STAGE_PROJECT=acme-platform|acme-platform-demo` (exit 1) до любого
  docker-действия — overlay НИКОГДА не целится в боевые проекты.
- stage-BI — **только ретег**, никогда `--build` (пересборка = пик RAM на 7.6 GiB коробке
  + откат запечённых ассетов `latest`). `up` делает hard-fail, если образа `:stage` нет.
- Отсутствие `deploy/.env.stage` → hard-fail (нет тихого фолбэка на dev `../.env`).
- База `deploy/docker-compose.yml` и `scripts/smoke-check.sh` — ноль-diff (overlay-only).
- **Гейт второго env:** перед `STAGE_ENV=stage2 … up` проверить `docker stats --no-stream` —
  available RAM после второго набора упадёт до ~1.8–2.0 GiB (см. `measurement.md` слайса).

---

## Сценарий I — Параллельная работа двух сессий на одном VPS без коллизий

Две сессии Claude (acc1/acc2) на этом VPS делят один Docker-демон и — что критично —
**бинд-маунт `../:/app`**: каждый `app`/`mcp-server` исполняет НЕ запечённый в образ код, а
**живое рабочее дерево того клона, из которого стек поднят**. Значит **ветка, на которую
переключён клон, молча определяет код, который отдадут ВСЕ стеки этого клона при следующем
`up`/recreate.**

> **Инцидент-первопричина (2026-07-16).** main-staging `acme-platform` (staging.example.com) и `acme-platform-stage`
> оба бинд-маунтили один клон `acme-platform-acc2`, переключённый на feature-ветку. Пересоздание
> main-staging MCP подхватило WIP. Два дефекта разом: (1) `acme-platform-stage` не мог тестировать версию,
> отличную от main-staging (один код на двоих); (2) любой recreate main-staging отгружал на
> `staging.example.com` недосмёрженный код (общий предпрод-стенд для обеих сессий).

**Проверить, какой клон питает стек (перед любым `checkout`/recreate):**
```bash
docker inspect <container> -f '{{range .Mounts}}{{if eq .Destination "/app"}}{{.Source}}{{end}}{{end}}'
# напр. acme-platform-mcp-server-1 (боевой), acme-platform-stage-mcp-server (stage A), acme-platform-stage2-app (stage B)
```

**Модель владения (target). Каждый стек ← ровно один клон; клон с feature-веткой НИКОГДА не
делит стек с общим main-staging `acme-platform`.** (Реальный prod — отдельная машина `app.example.com`,
на этом VPS его нет.)

| Клон / worktree | Ветка | Питает стек (pg/bi/mcp) | Владелец | Правило |
|---|---|---|---|---|
| `…/acme-platform-deploy` (выделенный) | `main` или RC | `acme-platform` — main-staging, `staging.example.com` (5434/8088/8765) | общий предпрод-стенд | ветку НЕ переключать в одиночку; recreate — по Сценарию B, по договорённости сессий |
| `…/acme-platform-acc2` | feature-ветка слайса A | `acme-platform-stage` (5436/8090/8767) | сессия A | только своя stage-env |
| `…/acme-platform-laneB` | feature-ветка слайса B | `acme-platform-stage2` (5437/8091/8768) | сессия B | только своя stage-env |

Каждая сессия делает **изолированную** приёмку на своей `acme-platform-stage*` (порт-туннель, свой
worktree, данные по Сценарию J). Общий `staging.example.com` (main-staging) — для согласованной
интеграционной приёмки RC перед промоушеном на реальный prod `app.example.com`.

**Карта «браузерный коннектор → стек» (claude.ai custom connector). КРИТИЧНО: `acme-prod-mcp`
— это ОТДЕЛЬНЫЙ prod-сервер, НЕ этот VPS.**

| Коннектор | URL / доступ | Хост / стек | Данные |
|---|---|---|---|
| `acme-prod-mcp` | `https://app.example.com/mcp` | **реальный prod `203.0.113.10` (отдельная машина)** | ВСЕ тенанты, включая **Tenant D** |
| staging-коннектор | `https://staging.example.com/mcp` (caddy → `mcp-server:8765`) | **этот VPS**, стек `acme-platform` = main-staging | Tenant A, Tenant B, Tenant C (**без Tenant D**) |
| (изолир. dev A/B) | `127.0.0.1:8767` / `:8768` + SSH-туннель | `acme-platform-stage` / `acme-platform-stage2` | seed из staging (Сценарий J) |

> **Этот VPS — staging.** Стек `acme-platform` здесь — это main-staging за `staging.example.com`, а не
> боевой prod. Реальный prod (`app.example.com`, `203.0.113.10`) — другая машина; деплой туда
> по тому же Сценарию B, но по SSH на тот хост, и **отсюда недоступен**. Пре-прод-приёмка
> инкремента идёт на `staging.example.com`, затем промоушен на `app.example.com`.
>
> После деплоя нового контракта тула claude.ai держит **старую схему в кэше** — коннектор надо
> переподключить (Settings → Connectors → off/on), иначе новые параметры в браузере не появятся.

**Жёсткие правила для агента — что МОЁ, что НЕТ:**

- ✅ Трогаю **только свой** клон + **свою** stage-env (`STAGE_ENV=stage` для A, `stage2` для B).
  Пересобираю/пересоздаю только контейнеры с моим `STAGE_PREFIX`.
- ⛔ **Не пересоздаю общий main-staging `acme-platform`** (`acme-platform-app-1`, `acme-platform-mcp-server-1`, `bi`,
  `caddy`) из своего dev-клона — это общий предпрод-стенд `staging.example.com` для обеих сессий.
  Только из `…-deploy` клона, по Сценарию B, по договорённости. **Реальный prod `app.example.com`
  отсюда не трогается вообще** (другая машина, деплой по SSH на тот хост).
- ⛔ **Не переключаю ветку** в клоне, чей `../:/app` питает `acme-platform` (проверка выше). Если
  `/app` контейнера `acme-platform-*` = мой клон — стоп, сначала ремедиация ниже.
- ⛔ Не запускаю `stage-env.sh` с чужим `STAGE_ENV`; не `down`/`destroy`/`--force-recreate`
  чужого проекта.
- ⛔ **Инвариант данных staging-VPS: все тенанты `is_active=false`** во всех БД этого VPS
  (`acme-platform`, `acme-platform-stage*`). Активный тенант + реальный токен = cron бьёт внешний API → бан per-token.
  После любого импорта данных — деактивировать (Сценарий J, шаг 2).
- ℹ️ **«Оно завелось?» — судить только по пересозданному контейнеру.** Бинд-маунт → `/app` всегда
  свежий, но живой PID1 держит модули с момента старта. Отдаёт новый код только после
  `docker compose … up -d --build --force-recreate <svc>` (НЕ `restart`). `docker exec <c> python -c …`
  порождает НОВЫЙ интерпретатор и всегда видит новый `/app` — по нему НЕЛЬЗЯ судить о живом сервере.

**Разовая ремедиация — вывести main-staging `acme-platform` с dev-клона на выделенный клон:**
```bash
# 1. Выделенный деплой-клон (БД в томе acme-platform_postgres_data — вне клона, не мигрирует)
git clone <repo> ~/projects/acme-platform-deploy
cd ~/projects/acme-platform-deploy && git checkout main && ln -sf ../.env deploy/.env
# 2. Пересоздать main-staging app+mcp ИЗ deploy-клона — bind-mount /app переедет на него
cd deploy && docker compose up -d --force-recreate --no-deps app mcp-server
# 3. Проверить, что /app контейнеров acme-platform-* теперь = deploy-клон
docker inspect acme-platform-mcp-server-1 -f '{{range .Mounts}}{{if eq .Destination "/app"}}{{.Source}}{{end}}{{end}}'
# → ~/projects/acme-platform-deploy
```
После этого `acme-platform-acc2` свободен как dev-клон сессии A (питает только `acme-platform-stage`).

---

## Сценарий J — Наполнение stage-БД данными тенантов из prod (read-only)

Смысл stage — прогнать инкремент против **реальных данных тенантов ДО прод-деплоя**. Но
stage-postgres после `up`+`alembic` пуст. Наполняем его снимком доменных таблиц из боевого
`acme-platform-postgres`. **На стороне prod — только чтение (`pg_dump` не мутирует и не лочит.)**

```bash
# 0. На stage: схема + read-only роль уже накатаны (Сценарии C/C2 против stage-postgres)
STAGE_ENV=stage bash scripts/stage-env.sh exec app alembic upgrade heads

# 1. Data-only дамп доменных таблиц из БОЕВОГО postgres → в stage-postgres.
#    Список = то, что читает VIEW reporting_source + MCP-тулы. Отредактировать под свой инкремент.
docker exec acme-platform-postgres pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
    --data-only --no-owner --disable-triggers \
    -t tenant_profiles -t tenant_accounts -t skus -t product_costs \
    -t audit_lines -t tenant_tax_params -t tenant_daily_stats \
  | docker exec -i acme-platform-stage-postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"

# 2. ⚠️ ОБЯЗАТЕЛЬНО сразу после заливки — ДЕАКТИВИРОВАТЬ все тенанты.
#    Инвариант этого VPS: все тенанты is_active=false → app/cron НЕ дёргают внешний API.
#    Иначе staging-cron бьёт реальным токеном по per-token квоте маркетплейса (бан per-token).
docker exec acme-platform-stage-postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
  -c "UPDATE tenant_accounts SET is_active=false WHERE is_active=true;"

# 3. Проверка: тенанты залиты И все inactive; есть unmatched-строки для теста note
docker exec acme-platform-stage-postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -tAF'|' -c "
  SELECT (SELECT COUNT(*) FROM tenant_accounts)                          AS cabinets,
         (SELECT COUNT(*) FROM tenant_accounts WHERE is_active)          AS active_MUST_BE_0,
         (SELECT COUNT(*) FROM audit_lines WHERE product_id IS NOT NULL)  AS fal,
         (SELECT COUNT(*) FROM reporting_source)                                 AS reporting;"
```

Замечания:
- **Инвариант staging-VPS: все тенанты `is_active=false`.** Дамп из prod приносит `is_active=true`
  → шаг 2 обязателен после КАЖДОЙ заливки/рефреша. `active_MUST_BE_0` в проверке = 0. Реактивация
  тенанта — только осознанно и только с dummy-токеном.
- Данные = снимок; для чистого рефреша — `TRUNCATE <таблицы> CASCADE` на **stage** перед повторной
  заливкой (НИКОГДА не на prod), затем снова шаг 2.
- Реальные данные тенантов на stage → токены/секреты внешнего маркетплейса в `deploy/.env.stage` обязаны быть
  **dummy** (Сценарий H / STAGE-ENV.md §7), host-порты — только `127.0.0.1` + SSH-туннель.
- Для второго env — то же, но `acme-platform-stage2-postgres` и `STAGE_ENV=stage2`.
- То же и для main-staging `acme-platform` (staging.example.com): после любого импорта данных —
  деактивировать тенанты (`acme-platform-postgres`, тот же UPDATE).

---

## Проверка здоровья стека

```bash
cd deploy

# Статус всех контейнеров
docker compose ps

# Логи конкретного сервиса (последние 50 строк)
docker compose logs --tail=50 bi
docker compose logs --tail=50 app

# Проверить что сеть включает все нужные контейнеры
docker network inspect acme_net --format '{{range .Containers}}{{.Name}} {{end}}'
# → должны быть: acme-platform-postgres bi app (и glitchtip, redis, acme-platform-caddy)

# Smoke-check
cd ..
bash scripts/smoke-check.sh
```

---

## Секреты и конфигурация

- `.env` — единственный источник секретов. Никогда не коммитить в репо.
- На каждом окружении свой `.env` с уникальными значениями (разные пароли для staging и prod).
- Список обязательных переменных: см. `.env.example`.
- Новая переменная в коде → обязательно добавить в `.env.example` с описанием (без значения).

---

## Типичные ошибки и их решение

| Симптом | Причина | Решение |
|---|---|---|
| `No module named 'psycopg2'` в BI-инструменте | Старый worker с битым состоянием | `docker compose up -d --build bi` |
| BI-инструмент не видит БД после рестарта | `docker restart` вместо compose | `docker compose up -d bi` |
| `alembic.util.exc.CommandError: Can't locate revision` | Ветки миграций не смержены | `alembic merge heads -m "merge"` → новый PR |
| Контейнер не резолвит `acme-platform-postgres` | Сервис не в сети `acme_net` | `docker network connect acme_net <container>` — временно; потом фиксировать в compose через PR |
| Volume пуст после `compose up` | Сменился project name | Миграция volume по Сценарию D |

---

## Сценарий F — Проверка здоровья staging (non-destructive)

Запускается после деплоя инкремента или при диагностике. Не трогает данные.

```bash
# Non-destructive smoke против running stack
SMOKE_MODE=staging bash scripts/smoke-check.sh

# Или вручную:
cd ~/projects/acme-platform-acc2/deploy
docker compose ps
docker compose exec -T postgres \
  psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
  -c "SELECT COUNT(*) FROM tenant_profiles; SELECT COUNT(*) FROM tenant_accounts;"
docker compose logs --tail=20 app | grep -E "Scheduler|error|CRITICAL"
```
