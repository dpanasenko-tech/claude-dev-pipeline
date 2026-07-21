<div align="right">

[GitHub @dpanasenko-tech](https://github.com/dpanasenko-tech) · Telegram [@pde87](https://t.me/pde87)

</div>

# Claude Code Dev Pipeline

Шестистадийный agent-pipeline для разработки в [Claude Code](https://claude.com/claude-code):
`planner → architect → tdd-engineer → implementer → reviewer → release-engineer`.
Вынесено (и обезличено) из продакшн B2B SaaS проекта, где по этому процессу прошли
десятки фич end-to-end — от продуктового брифа до GO/NO-GO на проде.

Схема пайплайна и топологии окружений: **[открыть как страницу](https://dpanasenko-tech.github.io/claude-dev-pipeline/pipeline-topology.html)**
(или исходник — [docs/pipeline-topology.html](docs/pipeline-topology.html)).

## Если вы — предприниматель или селлер без навыков программирования

Пайплайн создан не только для разработчиков. Он даёт нетехническому человеку контроль над
качеством того, что делает ИИ, не требуя уметь читать код:

- **Не нужно уметь программировать, чтобы управлять процессом.** Вы одобряете всего два документа
  на человеческом языке — бриф («что делаем») и финальный вердикт GO («можно выкатывать») — всё
  остальное (код, тесты, архитектура) ИИ ведёт сам, но строго по вашим правилам.
- **ИИ не может «сдать» сырой код.** Каждая фича обязана пройти тесты, независимую адверсариальную
  проверку и чек-лист готовности к релизу до того, как попадёт к вам на подтверждение — типичные
  для соло-разработки на ИИ полуфабрикаты и забытые edge-кейсы отсекаются автоматически.
- **Всегда понятно, что происходит и почему.** Каждый шаг оставляет документ (бриф/план/ревью/релиз)
  на понятном языке — можно вернуться через месяц и разобраться, что и зачем было сделано, не читая код.
- **Безопасные точки отката по умолчанию.** Миграции с планом отката, релизы с git-тегами, обязательный
  staging перед продом — типичные способы «уронить всё в проде» закрыты процессом, а не вашей бдительностью.
- **Растёт вместе с продуктом.** Начинаете с одного скрипта-автоматизации — доходите до полноценного
  сервиса с несколькими фичами и релизами в месяц, не меняя подход и инструменты.

**Что можно качественно сделать по этому пайплайну:** Telegram-бот для приёма заказов/записи клиентов
с оплатой и напоминаниями · личный дашборд аналитики продаж (маркетплейс, соцсети, реклама) с
автообновлением данных · внутренняя CRM/учёт заказов и остатков для магазина или мастерской ·
автоматизация отчётности (выгрузка из внешних сервисов → сверка → ежедневная сводка) · MVP
SaaS-продукта, который не стыдно показать первым платящим клиентам.

## Что это

- **`.claude/agents/*.md`** — шесть субагентов, каждый — одна стадия. Строгий скелет:
  Inputs → Output → Operating rules → Forbidden → Definition of done → Handoff message format.
- **`.claude/settings.json`** — permissions (read-only allowlist + deny на деструктивные git/rm)
  и hooks (SessionStart-напоминание о процессе, PostToolUse-чеклист, Stop-чеклист).
- **`CLAUDE.md`** — контракт-регламент: гейты человека (только брифы и Phase A = GO), Definition
  of Done, testing rules, migration policy, follow-up lifecycle через GitHub Issues, release checklist.
- **`docs/product/*.template.md`, `docs/architecture/*.template.md`** — шаблоны продуктовых/архитектурных
  артефактов (acceptance criteria, domain model, user flows, API spec, test strategy).
- **`docs/features/*.template.md`, `docs/features/README.md`** — шаблон `release.md` (с обязательным
  Phase A/Phase B и manual acceptance checklist), конвенция commit-сообщений по стадиям, конвенция
  директории `docs/features/<slug>/`.
- **`docs/runbooks/`** — как физически выполнять процесс: git-команды по стадиям, чек-лист human-approve,
  follow-up lifecycle, деплой в три окружения (dev/staging/prod), параллельная работа нескольких
  сессий Claude Code над разными слайсами, изолированные stage-окружения, трассируемость версий.
- **`scripts/*.sh`** — рабочая референсная реализация: `quality-check.sh` (единая точка входа
  format+lint+typecheck+test), `smoke-check.sh` (dual/triple-mode: ci/staging/prod), `followups.sh`
  (обёртка над `gh issue list`), `stage-env.sh` (изолированные docker-compose stage-окружения),
  `prod-version.sh` (трассируемость версии по двум каналам).

Домены/IP/названия организации везде заменены на плейсхолдеры (`example.com`, `your-org`,
`acme-platform`) — методология и структура команд сохранены дословно.

## Совместимость

**Интерфейсы Claude Code (нативная поддержка):** CLI, [VS Code-расширение](https://docs.claude.com/en/docs/claude-code/vs-code),
JetBrains-плагин, веб (claude.ai/code) — `.claude/agents/*.md` (subagents), hooks и `permissions`
в `.claude/settings.json` работают одинаково в любом из этих интерфейсов, потому что все они
читают один и тот же `.claude/`.

**Другие агентские IDE** (Antigravity, Cursor, Windsurf и подобные) — если они поддерживают
project-level инструкции и кастомных агентов: `CLAUDE.md` и все `docs/*.template.md`/`docs/runbooks/*.md` —
обычный markdown, переносится без изменений как system prompt / project rules. `.claude/agents/*.md`
и `.claude/settings.json` — формат, специфичный для Claude Code; в другой IDE их нужно переложить в
её собственный механизм кастомных агентов/hooks (если он есть) — сама методология (гейты, DoD,
шесть стадий) от конкретного инструмента не зависит.

**Прочее:**
- `gh` CLI, авторизованный в вашей GitHub-организации — нужен для follow-up lifecycle (§4 в
  CLAUDE.md) и релизного процесса (тег → CHANGELOG → GitHub Release).
- `git-cliff` — генерация `CHANGELOG.md` из git-тегов на release-authoring машине (dev/CI или staging).
- Bash + Docker Compose — для `scripts/*.sh` в исходном виде. Сам процесс (agents/CLAUDE.md/шаблоны)
  от стека не зависит; скрипты — иллюстративная реализация, адаптируйте под свой CI/деплой.
- Стек в примерах (Postgres, docker-compose, BI-инструмент вроде Superset, error-tracker вроде
  GlitchTip) — иллюстративный. Ни сам пайплайн, ни его гейты не завязаны на конкретные технологии.

## Быстрый старт

1. Скопируйте в свой репозиторий: `.claude/agents/`, `.claude/settings.json`, `CLAUDE.md`,
   `docs/product/*.template.md`, `docs/architecture/*.template.md`, `docs/features/*.template.md`,
   `docs/features/README.md`, `scripts/*.sh` (адаптировав под свой стек).
2. Замените плейсхолдеры под свой проект:

   | Плейсхолдер | На что заменить |
   |---|---|
   | `acme-platform` | имя вашего проекта/docker-compose-стека |
   | `your-org/your-project` | ваш GitHub org/repo |
   | `app.example.com`, `staging.example.com` | ваши реальные домены prod/staging |
   | `ExternalApiClient` | конкретные клиенты внешних API вашего продукта |
   | «BI-инструмент» | ваш BI (Superset, Metabase, …) или удалите раздел, если не нужен |

3. Заведите `docs/features/` по конвенции из `docs/features/README.md`.
4. Откройте Claude Code в репозитории и опишите первую фичу — сработает `planner` (см.
   `docs/runbooks/CLAUDE-WORKFLOW.md` для полного онбординга по стадиям).
5. Дальше по цепочке: одобрили brief → `architect` пишет plan → одобрили plan → агент
   автономно проводит tdd-engineer → implementer → reviewer → release-engineer Phase A
   в одном PR → ваш GO на Phase A → merge → Phase B на деплое (`docs/runbooks/DEPLOY.md`).

## Адаптация под свой проект

- **Масштаб стадий.** Для тривиальных правок (тайпо, однострочный фикс) можно пропускать
  стадии 1–3, но не ревьюера (Stage 5) — см. CLAUDE.md §4. Для очень маленьких проектов
  вы вправе слить planner+architect в одну стадию — сама методология (test-first,
  вертикальные слайсы, DoD) важнее числа формальных стадий.
- **Доменная терминология.** В CLAUDE.md/агентах намеренно оставлены generic-примеры
  (`ExternalApiClient`, «BI-инструмент») — впишите вместо них реальные интеграции своего продукта.
- **Скрипты.** `quality-check.sh`/`smoke-check.sh` — рабочий скелет (single entry point,
  fail-fast, три режима smoke: `ci`/`staging`/`prod` с разной семантикой мутаций). Замените
  вызовы `ruff`/`mypy`/`pytest` на инструменты своего стека, но сохраните: один скрипт — одна
  точка входа, `SMOKE_MODE=ci` — эфемерный изолированный стек с собственным `docker compose
  -p` project name (никогда не делите volume/network с dev-стеком).
- **`.claude/settings.json`.** `permissions.allow` — стартовый allowlist read-only команд
  (`git status/diff/log`, `find`, `grep`) плюс ваши `quality-check.sh`/`smoke-check.sh`.
  `permissions.deny` — расширяйте под свои деструктивные операции.
- **`CLAUDE.md`.** Разделы про инфраструктуру (§9 security, §11 release checklist, §14 repo
  conventions, §16 two-account workflow) — замените на свою реальную инфраструктуру: домены,
  hosting, BI-инструмент, число параллельных Claude Code аккаунтов/сессий.

## Лицензия

См. [LICENSE](LICENSE).
