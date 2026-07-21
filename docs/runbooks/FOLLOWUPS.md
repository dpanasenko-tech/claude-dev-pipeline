# Follow-up lifecycle — runbook

Источник правды по техдолгу пайплайна — **GitHub Issues** с меткой `followup` в репо
`your-org/your-project`. Состояние серверное и одинаковое для обоих аккаунтов (acc1/acc2),
не привязано к ветке. Файлы `docs/features/*/followups.md` — только исторический архив.

## Таксономия меток

| Метка | Назначение | Обязательна? |
|---|---|---|
| `followup` | маркер пайплайна | да |
| `slice:<slug>` | к какому слайсу относится | да |
| `route:<agent>` | кому чинить (`tdd-engineer`, `implementer`, `architect`, `reviewer`, `release-engineer`) | нет |

## Жизненный цикл

### Write — любой агент заметил постороннее

```bash
gh issue create \
  --label "followup,slice:<slug>" \
  --label "route:<agent>" \          # опционально
  --title "FU-<slug>-<кратко>: однострочное описание" \
  --body "$(cat <<'EOF'
**Слайс:** <slug>
**Обнаружено:** <агент, stage N, дата>

<Контекст: что именно, где, симптом>

**Действие:** <что нужно сделать; если требует цикла — planner → architect → …>

**Источник:** <файл:строка или PR #N>
EOF
)"
```

Не чинить сейчас — только зафиксировать.

### Adopt — planner в начале каждого брифа

```bash
# Все открытые follow-ups:
bash scripts/followups.sh

# По конкретному слайсу:
bash scripts/followups.sh --slice <slug>

# Только count для CI-проверки:
bash scripts/followups.sh --count
```

Релевантные issues → в **Scope (this slice)** или **Out of scope (future slices)** в брифе,
со ссылкой `#N`. Issue остаётся `open` до закрывающего PR.

### Close — PR, который чинит пункт

В теле PR (не в заголовке):
```
Closes #N
```

GitHub закрывает issue **автоматически при merge в main**. Ничего не редактировать вручную.

### Verify — reviewer / release-engineer

```bash
# Проверить, что PR закрывает нужные issues:
gh pr view <PR-number> --json closingIssuesReferences

# Проверить оставшиеся открытые issues слайса:
bash scripts/followups.sh --slice <slug>
```

`GO` с незакрытыми, но решёнными пунктами недопустим.

## GitHub Projects board (опционально)

Для визуального обзора поверх Issues:

```bash
# Требует scope project — выполнить один раз:
gh auth refresh -s project,read:project

# Создать доску:
gh project create --owner your-org --title "Tech debt / follow-ups"
```

Настройки доски в UI:
1. Поле **Status** (single-select): `Backlog` / `Adopted` / `Done`
2. Auto-workflow: «Auto-add to project» по метке `followup`
3. Auto-workflow: «Item closed → Done»

## Полезные команды

```bash
# Все открытые follow-ups (сгруппированы по слайсам):
bash scripts/followups.sh

# Только по слайсу:
bash scripts/followups.sh --slice <slug>

# Открытые + закрытые:
bash scripts/followups.sh --all

# Открытые + закрытые по слайсу:
bash scripts/followups.sh --all --slice <slug>

# Только число (для скриптов):
bash scripts/followups.sh --count

# Посмотреть issue в браузере:
gh issue view <N> --web

# Посмотреть все issues с меткой followup в браузере:
gh issue list -l followup --web
```
