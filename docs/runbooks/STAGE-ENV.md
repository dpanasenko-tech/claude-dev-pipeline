# Runbook — изолированное stage-окружение (stage-env-multiplex)

> **Назначение:** поднять/погасить дополнительное долгоживущее Docker-окружение на том же VPS,
> физически изолированное от боевого `acme-platform` и `acme-platform-demo`. Механизм — overlay
> `deploy/docker-compose.stage.yml` поверх неизменного `deploy/docker-compose.yml`, применяемый
> ТОЛЬКО через `scripts/stage-env.sh`. Ось B (рантайм/данные) параллельной разработки двумя
> аккаунтами (CLAUDE.md §16). Ось A (исходники) — `git worktree`, см. §«Связка с git worktree».

---

## 0. Инварианты изоляции (читать до первого запуска)

Слайс защищает единственный катастрофический сценарий — запись stage-app в боевую БД `acme-platform`.
Эти инварианты — load-bearing (CLAUDE.md §6/§16):

- **Overlay НИКОГДА не применяется к проекту `acme-platform`/`acme-platform-demo`.** `scripts/stage-env.sh` жёстко
  отвергает `STAGE_PROJECT=acme-platform|acme-platform-demo` (exit 1) до любого docker-действия.
- **`down -v` — строго своего `-p ${STAGE_PROJECT}`.** Никогда не запускать `down`/`down -v`/
  `up --force-recreate` против `acme-platform`. `destroy` удаляет ровно `${STAGE_PROJECT}_*` тома/сети;
  `acme-platform_postgres_data`, `acme-platform_bi_data`, external-сети `acme_net`/`acme-platform-shared` — вне границ.
- **stage-BI-инструмент никогда не запускать с `--build`.** Пересборка = пик RAM (убьёт 8 GB коробку) и
  откат запечённых ассетов `acme-platform-bi:latest`. Используется ретег существующего образа.
- **singleton-caddy НЕ подключать к `stage_net`** без переименования сервисов — иначе Compose
  добавит сервису `bi` alias в сети caddy и staging-домен утечёт на stage-BI
  (пример реального инцидента в практике — proxy подхватил alias чужого сервиса). Доступ к stage — только host-порт + SSH-туннель.
- **Нет тихого фолбэка на dev `../.env`.** Отсутствие `deploy/.env.<stage>` → hard-fail. stage-файл
  служит И источником интерполяции (`--env-file`), И service-level `env_file` внутри контейнеров.

---

## 1. Переменные окружения

Шаблон — `deploy/.env.stage.example` (коммитится, без секретов). Реальный `deploy/.env.stage`
gitignored (`.env.*`), заполняется вручную своими stage-значениями.

| Переменная | Назначение | Первый env |
|---|---|---|
| `STAGE_PROJECT` | project name (`-p`), namespace тома/сети; НИКОГДА не `acme-platform` | `acme-platform-stage` |
| `STAGE_PREFIX` | префикс `container_name` | `acme-platform-stage` |
| `STAGE_ENV_FILE` | service-level `env_file` (относительно `deploy/`) → `deploy/.env.stage` | `.env.stage` |
| `STAGE_PG_PORT` | host-порт postgres (`127.0.0.1:<port>:5432`) | `5436` |
| `STAGE_BI_PORT` | host-порт BI-инструмента (`…:8088`) | `8090` |
| `STAGE_MCP_PORT` | host-порт mcp-server (`…:8765`) | `8767` |
| `STAGE_BI_IMAGE` | тег ретегнутого образа | `acme-platform-bi:stage` |
| `POSTGRES_*`, `MCP_READONLY_DB_PASSWORD`, `BI_SECRET_KEY`, токены | СВОИ stage-секреты | — |

Порт-блоки (без коллизий): `acme-platform` = 5434/8088/8765/8000, `acme-platform-demo` = 5435/8089/8766,
`acme-platform-stage` = 5436/8090/8767. Резерв под второй env: 5437/8091/8768.

> **Разрешение «двух .env» (память проекта).** База интерполирует `${...}` из `--env-file` и
> грузит секреты через service-level `env_file`. Для stage ОБА пути ведут в один
> `deploy/.env.<stage>`: `stage_compose` подаёт `--env-file deploy/.env.<stage>`, а overlay
> переопределяет `env_file` на `${STAGE_ENV_FILE}` (относительно project-dir `deploy/` = тот же файл).
> Отклонение от plan §2.2 (там `../${STAGE_ENV_FILE}` → repo-root): выбран `deploy/`-относительный путь,
> чтобы интерполяция и service-level `env_file` указывали на ФИЗИЧЕСКИ ОДИН файл, а не два.

---

## 2. Подготовка (один раз)

```bash
# 1. Ретег образа BI-инструмента (без пересборки — переиспользует запечённые ассеты latest)
docker tag acme-platform-bi:latest acme-platform-bi:stage

# 2. Файл секретов stage
cp deploy/.env.stage.example deploy/.env.stage
# отредактировать deploy/.env.stage: свои POSTGRES_*, BI_SECRET_KEY, токены (stage-значения)
```

## 3. Pre-flight: проверка топологии до подъёма

```bash
# Рендер merged-config: убедиться, что 5 сервисов на stage_net, префиксные имена, порты STAGE_*
STAGE_ENV=stage bash scripts/stage-env.sh config | less

# Автоматические ассерты изоляции (сети/имена/состав) из рендера — без обращения к демону
STAGE_ENV=stage bash scripts/stage-env.sh selfcheck
```

## 4. Подъём / останов / уничтожение

```bash
STAGE_ENV=stage bash scripts/stage-env.sh up        # поднять РОВНО 5 сервисов (postgres app bot mcp bi)
STAGE_ENV=stage bash scripts/stage-env.sh ps        # состав; glitchtip/caddy/redis тут НЕ должно быть
STAGE_ENV=stage bash scripts/stage-env.sh logs -f bi
STAGE_ENV=stage bash scripts/stage-env.sh down      # остановить, тома целы
STAGE_ENV=stage bash scripts/stage-env.sh destroy   # down -v: удаляет ТОЛЬКО ${STAGE_PROJECT}_* тома (идемпотентно)
```

`up` явно перечисляет 5 сервисов — `redis`/glitchtip/`caddy` наследуются из base, но НЕ
поднимаются (singleton проекта `acme-platform`, план: гейт AC — второй параллельный env только под замер ресурсов).

## 5. Сквозной путь окружения

После `up` (миграции/seed/ассеты — как в основном стеке, но против stage-postgres):

```bash
# Миграции против stage-postgres (exec в уже поднятый контейнер app)
STAGE_ENV=stage bash scripts/stage-env.sh exec app alembic upgrade heads
# Seed: тот же скрипт, что в dev, но против stage-контейнера
STAGE_ENV=stage bash scripts/stage-env.sh exec -T postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f /seed/seed_phase_a.sql
# BI-ассеты: import_assets.sh внутри stage-BI-инструмента (host-порт STAGE_BI_PORT=8090)
STAGE_ENV=stage bash scripts/stage-env.sh exec bi bash -lc 'import_assets.sh'
```

## 6. Замер ресурсов (гейт второго окружения)

При живом `acme-platform` + поднятом stage под нагрузкой (миграции → seed → BI-импорт):

```bash
docker stats --no-stream
```

Суммарный RAM должен оставлять запас (нет OOM). Стартовые лимиты overlay (`mem_limit`/`cpus`):
bi 900M/1.0, postgres 400M/0.5, mcp 300M/0.5, app 300M/0.5, bot 200M/0.25 (Σ≈2.1G).
Замер документируется в `release.md` как гейт для решения о втором окружении.

## 7. Избежать обращений stage-app к внешнему API при разработке

stage-`app` под живым `cron_runner` по расписанию (`sync_cron_hour` и др.) ходит во внешний API.
**Флага «отключить cron» в коде нет** — `*_cron_hour` лишь переносят час, но не выключают job.
Две реальные меры:

1. **Свои/тестовые токены в `deploy/.env.stage`** (не совпадающие с prod) — чтобы не бить
   per-token квоты внешнего API (бан per-token). Единственная мера, если `app` нужен.
2. **Не поднимать сервис `app`** — `up` принимает список сервисов и поднимает РОВНО его:
   ```bash
   STAGE_ENV=stage bash scripts/stage-env.sh up postgres mcp-server bi
   ```
   Без аргументов поднимаются все 5; с аргументами — только перечисленные (cron-`app` не стартует).

## 8. Связка с git worktree (ось A + ось B)

```bash
# Ось A: отдельная рабочая директория под слайс (исходники не топчутся)
git worktree add ../acme-platform-stage feature/<slug>-stageN

# Ось B: из этой worktree поднять СВОЙ stage-env (свой deploy/.env.stage, свой STAGE_PROJECT)
cd ../acme-platform-stage
STAGE_ENV=stage bash scripts/stage-env.sh up
```

Каждая worktree держит собственный `deploy/.env.stage` (gitignored) → своё изолированное окружение.
См. также `docs/runbooks/GIT-WORKFLOW-COMMANDS.md` (раздел «stage-env»).

## 9. Rollback

| Что | Откат |
|---|---|
| overlay/скрипт/env-шаблон/runbook | `git revert` PR (новые файлы удаляются) |
| поднятое окружение | `stage-env.sh destroy` (`down -v` строго `${STAGE_PROJECT}`) |
| ретег `acme-platform-bi:stage` | `docker rmi acme-platform-bi:stage` (ассеты latest не тронуты) |
| база `docker-compose.yml` | не требуется — не менялась (overlay-only) |

Необратимых шагов (drop schema / delete prod data) нет. `down -v` необратим только для stage-данных —
stage эфемерен, пересоздаётся `up` + `alembic` + seed.
