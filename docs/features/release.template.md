# Release — <slug> (Stage 6)

> Шаблон для `release.md`. Скопировать в `docs/features/<slug>/release.md`,
> заполнить все секции. Пустые строки в §10 — блокер GO.

## Вердикт: GO / NO-GO

<!-- GO / NO-GO + краткое обоснование -->

---

## 1. Артефакт

| Поле | Значение |
|---|---|
| SHA | `<git rev-parse --short HEAD>` |
| Ветка | `feature/<slug>-stage4` → `main` |
| PR | #<номер> |
| Модули / файлы | `src/<...>` |
| Миграция | да / нет — `<revision>` |

---

## 2. Build & test evidence

```bash
bash scripts/quality-check.sh
# → Вставить вывод (последние строки)
```

Все проверки зелёные: да / нет.

---

## 3. Smoke evidence (CI ephemeral)

```bash
SMOKE_MODE=ci bash scripts/smoke-check.sh
# → Вставить вывод
```

---

## 4. Env & secrets diff

Новые переменные в `.env.example` (не заданные в `.env` текущего окружения):

```
<VAR>=<example_value>   # что означает
```

Нет новых переменных: да / нет.

---

## 5. Migration plan

- Revision: `<id>`
- Тип: DDL / DML / смешанная
- Reversible: да / нет — `alembic downgrade <prev_rev>`
- Downtime estimate: ~0 / ~N сек (блокировка таблицы `<table>`)
- Backfill: нет / да — idempotent job `<name>`

---

## 6. Feature flag state

Флаг: нет / `<FLAG_NAME>` (default: off → включить на staging, потом prod).

---

## 7. Rollback plan

```bash
# 1. Откатить миграцию
docker compose -f deploy/docker-compose.yml exec app \
  alembic downgrade <prev_rev>

# 2. Откатить образ
git revert <SHA> && git push origin main
docker compose -f deploy/docker-compose.yml up -d --build app
```

---

## 8. Post-deploy actions

> Каноническая процедура деплоя инкремента: `docs/runbooks/DEPLOY.md` §B.

```bash
# На staging VPS:
cd ~/projects/acme-platform-acc2/deploy
git pull origin main
docker compose up -d --build app
docker compose exec app alembic upgrade head
cd ..
SMOKE_MODE=staging bash scripts/smoke-check.sh
```

Проверить GlitchTip (см. §10 ниже).

---

## 9. Observability hooks

- Логи: stdlib JSON → `docker compose logs app`
- Метрики APScheduler: `logs app | grep -E "sync_scheduled|spp_collection_scheduled"`
- GlitchTip: события от `cron_runner`, `spp_collector`, `alert_worker`, `scraper_runner`
- Новые пути, добавленные этой фичей: `<путь>` — логирует `<событие>`

---

## ⛳ HANDOFF: dev-машина → staging VPS

> **§§1–9 = Phase A** (dev-машина / CI). Заполнены и запушены в `main`.
> **§10.0 + §10–12 = Phase B** (staging VPS). Выполняются ПОСЛЕ деплоя на VPS.
>
> Релиз **НЕ** считается done после §§1–9. Это машинная граница, не конец работы.
> Переключиться на staging VPS (новая Claude Code сессия), сделать `git pull`,
> **сначала нарезать релиз (§10.0 — тег ДО деплоя)**, накатить инкремент по
> `docs/runbooks/DEPLOY.md` §B, затем заполнить §10 ниже.
> Возобновление тривиально: §§1–9 уже в `release.md` — осталось §10.0 + §10 + вердикт.

---

## 10.0 Релиз-артефакт — тег + CHANGELOG + Release (Phase B, дельвербл A — GO-блокер)

> Трассируемость (тег/CHANGELOG/Release) — **отдельный** дельвербл от деплоя (CLAUDE.md §11).
> Выполняется **ДО** деплоя на release-authoring машине. Пустые чекбоксы — блокер GO.
> Каноническая процедура и обоснование машин — `docs/runbooks/DEPLOY.md` → «Релизный процесс».

```bash
# На release-authoring машине (dev/CI ИЛИ staging-VPS — где есть gh + git-cliff):
git fetch origin --tags
git tag --sort=-v:refname | head -1                 # последний тег → выбрать vX.Y.Z по SemVer
git cliff --tag vX.Y.Z -o CHANGELOG.md              # или: git cliff --unreleased --prepend CHANGELOG.md
git add CHANGELOG.md && git commit -m "[STAGE 6/6] release-engineer: CHANGELOG vX.Y.Z"
git tag -a vX.Y.Z -m "release vX.Y.Z" && git push origin vX.Y.Z
gh release create vX.Y.Z --notes-file <(git cliff --current)
git describe --tags --exact-match                   # → vX.Y.Z (иначе Сценарий B REFUSE)
```

- [ ] SemVer-тег `vX.Y.Z` выбран по SemVer (`git fetch origin --tags` перед выбором — гонки тегов) и создан **ДО деплоя** (AC-5)
- [ ] `CHANGELOG.md` сгенерирован git-cliff, закоммичен и запушен (AC-4)
- [ ] GitHub Release `vX.Y.Z` опубликован с секцией changelog (AC-5)
- [ ] Гейт AC-6 подтверждён: `git describe --tags --exact-match` даёт точный `vX.Y.Z` (AC-3) — без него деплой REFUSE

> Если этот слайс уезжает в **общий** тег (несколько слайсов в одном релизе) — указать
> здесь номер общего тега и явно отметить, что отдельный тег не нарезается. Не оставлять
> секцию пустой при «GO»: пропуск релиз-шага должен быть виден, а не подразумеваться.

---

## 10. Manual acceptance checklist (Phase B — выполнить на staging VPS после деплоя)

> Заполнить release-engineer-ом. Пустые строки — блокер GO.

### CLI (если фича добавляет/меняет CLI)

```bash
# <команда> → <ожидаемый вывод>
```

### UI / Superset (если фича затрагивает дашборды или визуальный вывод)

- [ ] `<страница>` открывается без ошибок
- [ ] `<конкретный элемент>` отображает `<ожидаемое значение>`

### Логирование в GlitchTip (ОБЯЗАТЕЛЬНО для каждого релиза)

> Цель: убедиться, что после накатки инкремента ошибки реально долетают до UI.
> На текущем коде (до фикса OBS-1) шаг требует ручного `sentry_sdk.init()` в сниппете.

```bash
# Отправить тестовое событие из того же контейнера, что пишет логи в проде:
docker compose -f deploy/docker-compose.yml exec -T app python -c "
import sentry_sdk, os
sentry_sdk.init(dsn=os.environ['GLITCHTIP_DSN'])
sentry_sdk.capture_message('release smoke: <slug> $(git rev-parse --short HEAD)')
sentry_sdk.flush(timeout=10)
print('sent')
"
```

- [ ] Событие `release smoke: <slug> <SHA>` появилось в GlitchTip UI
      (Issues → проект `your-project`) в течение ~1 мин
- [ ] После деплоя нет новых **неожиданных** ошибок в Issues
- [ ] (если применимо) приложение само инициализирует sentry_sdk —
      событие долетает **без** ручного `sentry_sdk.init()` в сниппете

### DB (после `alembic upgrade head`)

```sql
-- <query> → <ожидаемый результат>
```

### Интеграция (если фича затрагивает внешние API)

- [ ] `<действие оператора>` → `<ожидаемый результат>`

### Smoke (non-destructive, против running stack)

```bash
SMOKE_MODE=staging bash scripts/smoke-check.sh
# → ✓ smoke-check (staging) passed  (включая GlitchTip ingest probe)
```

- [ ] Smoke зелёный

---

## 11. Owner & on-call

- Owner: @<handle>
- On-call: @<handle>
- Уведомлены: да / нет

---

## 12. Release notes

<!-- Одна строка для CHANGELOG или GitHub Release -->

**<slug>:** <краткое описание для пользователя/оператора>.

---

## DoD checklist (CLAUDE.md §11)

**Phase A — Pre-deploy (dev-машина / CI):**

- [ ] CI green на merge commit
- [ ] `scripts/quality-check.sh` green
- [ ] `SMOKE_MODE=ci bash scripts/smoke-check.sh` green на CI
- [ ] §§1–9 заполнены; migration/rollback plan описаны
- [ ] Изменения (включая draft `release.md`) запушены в `main`

→ HANDOFF → staging VPS

**Phase B — Post-deploy (staging VPS). Два дельвербла — GO требует оба:**

_(A) Релиз-артефакт (трассируемость):_
- [ ] SemVer-тег `vX.Y.Z` создан ДО деплоя + CHANGELOG + GitHub Release (§10.0)
- [ ] Гейт AC-6: `git describe --tags --exact-match` даёт точный тег

_(B) Деплой + приёмка:_
- [ ] `git pull` + деплой по `docs/runbooks/DEPLOY.md` §B
- [ ] `SMOKE_MODE=staging bash scripts/smoke-check.sh` green против running stack
- [ ] Manual acceptance checklist (§10) пройден вручную (включая GlitchTip UI)
- [ ] Env vars/secrets присутствуют в целевом окружении
- [ ] Feature flags: состояние по умолчанию подтверждено
- [ ] Owner + on-call уведомлены

_Вердикт:_
- [ ] GO/NO-GO с поимённым перечислением (A)+(B) ✓/✗ (любой ✗ = NO-GO или письменный waiver); финальный commit запушен
