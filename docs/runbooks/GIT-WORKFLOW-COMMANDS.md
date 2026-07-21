# Git Workflow Commands

Copy-paste команды для каждого аккаунта при работе над стадией слайса.

## Pre-work checklist (обязательно перед созданием любой ветки)

```bash
git fetch origin                  # синхронизировать remote-состояние
git status                        # убедиться: нет uncommitted изменений
git log --oneline origin/main -3  # убедиться: main актуален
```

Только после этих трёх команд — создавать ветку.

## Начало новой стадии

```bash
# Stage 1 базируется на main:
git checkout -b feature/<slug>-stage1 origin/main

#    Stage N (N > 1) базируется на main ПОСЛЕ мержа предыдущей стадии:
git checkout -b feature/<slug>-stage2 origin/main
# (предыдущая стадия уже влита в main через squash merge)
```

**Запрещено:** `git checkout -b feature/... main` (локальный main может быть устаревшим).
Всегда использовать `origin/main` явно.

## Работа внутри стадии

```bash
# Коммитить по мере работы
git add <files>
git commit -m "[STAGE N/6] <verb>: <description>"

# Пуш в remote
git push origin feature/<slug>-stageN
```

## Создание PR

```bash
# PR с base=main (стадия N мержится в main после approval)
gh pr create \
  --base main \
  --head feature/<slug>-stageN \
  --title "[S<X>] Stage N/6: <Stage Name> — <slug>" \
  --body "$(cat <<'EOF'
## What
<одно предложение что сделано>

## Artifact
- docs/features/<slug>/brief.md   # stage 1
- docs/features/<slug>/plan.md    # stage 2
- docs/features/<slug>/test-matrix.md + tests/  # stage 3
- src/ (tests green)              # stage 4
- docs/features/<slug>/review.md  # stage 5
- docs/features/<slug>/release.md # stage 6

## Checklist
- [ ] CI green
- [ ] /review passed (or human review)
- [ ] No unresolved comments
EOF
)"
```

## Запросить Claude review

```bash
# Внутри Claude Code сессии (в директории репо):
/review <PR-number>
```

Claude прочтёт diff и артефакты стадии, выдаст список проблем или "Approved".

## После approval: merge (делает человек)

```bash
# Squash merge — одна стадия = один коммит в main
gh pr merge <PR-number> --squash --delete-branch
```

## Следующий аккаунт подхватывает работу

```bash
# В директории acc2 (или acc1 — не важно):
git fetch origin
git checkout -b feature/<slug>-stage<N+1> origin/main
# main уже содержит результат стадии N
```

## Параллельная работа на другом слайсе

```bash
# Пока acc2 на S1 stage 3 — acc1 начинает S3 stage 1:
git checkout -b feature/s3-stage1 origin/main
# S1 и S3 трогают разные папки (src/data/ vs src/voice/) — конфликтов нет
```

## Инициализация acc2 (один раз)

```bash
# Клонировать репо в директорию acc2:
git clone https://github.com/your-org/your-project.git \
  "~/projects/acme-platform-acc2"

# Запускать acc2 всегда так:
cd "~/projects/acme-platform-acc2"
export CLAUDE_CONFIG_DIR=~/.claude-acc2
claude
```

## Правила инфраструктуры (два аккаунта)

### Владелец стека

Один аккаунт (обычно acc1) **поднимает** общий стек (postgres, BI-инструмент, tracing).
Второй аккаунт только **подключается** к уже запущенным контейнерам.

```bash
# Владелец: поднять стек (один раз при старте работы)
cd "~/projects/acme-platform/deploy"
docker compose up -d postgres bi

# Проверить что сеть и контейнеры работают:
docker network inspect acme_net --format '{{range .Containers}}{{.Name}} {{end}}'
# → должны быть: acme-platform-postgres bi
```

### Запрет локальных правок инфра-файлов

Любое изменение `deploy/**`, `docker-compose.yml`, `Dockerfile`, `scripts/*.sh`
**идёт через PR** — как обычный код. Локальные изменения без коммита запрещены.

```bash
# Проверить: нет ли незакоммиченных правок инфры
git status deploy/ scripts/
# Должно быть пусто (или только gitignored .env)
```

### Сеть Docker

Сеть называется `acme_net` (external, создаётся один раз):
```bash
docker network create acme_net 2>/dev/null || echo "network acme_net already exists"
```

Все сервисы в `deploy/docker-compose.yml` используют эту сеть. Docker DNS резолвит
`acme-platform-postgres`, `bi` и т.д. по `container_name` из любого сервиса в сети.

### После sync с main (pull)

Если основная ветка обновила инфра-файлы, обязательно:
```bash
git pull origin main
# пересобрать и поднять сервис, если изменился его Dockerfile:
cd deploy && docker compose up -d --build bi
```

### BI-инструмент: дашборды как код

Конфигурация BI-инструмента (пример: Apache Superset) хранится в `deploy/bi/assets/` и коммитится в git.
UUID в YAML-файлах постоянны — их нельзя менять.

```bash
# Применить изменения YAML в работающий BI-инструмент (без пересборки образа)
cd deploy/bi
BI_URL=http://localhost:8088 BI_USER=admin BI_PASSWORD=admin \
  ./import_assets.sh

# Сохранить UI-изменения дашборда в резервную копию
cd deploy/bi
BI_URL=http://localhost:8088 BI_USER=admin BI_PASSWORD=admin \
  ./export_assets.sh
# ZIP → deploy/bi/backups/backup_YYYYMMDD_HHMMSS.zip (gitignored)
# Распаковать, обновить YAML в assets/, закоммитить

# Проверить лог автоимпорта после docker compose up
docker compose logs --tail=30 bi | grep "\[import\]"
```

## stage-env: изолированный рантайм на общий VPS (ось B)

Ось A (исходники) — `git worktree`. Ось B (рантайм/данные) — изолированный compose-проект через
`scripts/stage-env.sh`. Связка: одна worktree ↔ один stage-env со своим `deploy/.env.stage`.

```bash
# 1. Ось A: рабочая директория под слайс
git worktree add ../acme-platform-stage feature/<slug>-stageN
cd ../acme-platform-stage

# 2. Ось B: свой изолированный stage-env (свой STAGE_PROJECT/порты/секреты)
docker tag acme-platform-bi:latest acme-platform-bi:stage   # один раз
cp deploy/.env.stage.example deploy/.env.stage          # заполнить свои stage-секреты
STAGE_ENV=stage bash scripts/stage-env.sh selfcheck     # проверить изоляцию до up
STAGE_ENV=stage bash scripts/stage-env.sh up            # поднять 5 сервисов
# ... работа ...
STAGE_ENV=stage bash scripts/stage-env.sh destroy       # down -v строго своего проекта
```

Инварианты изоляции и полный runbook — `docs/runbooks/STAGE-ENV.md`. Никогда не применять overlay
к `acme-platform`; `down -v` строго своего `-p`; stage-BI без `--build`; caddy вне `stage_net`.
