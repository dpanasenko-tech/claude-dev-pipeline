# Dual Claude Account Setup

Изоляция двух аккаунтов Claude Code Pro на одном Mac — CLI и VS Code.

## Проблема

По умолчанию Claude Code CLI хранит токен в `~/.claude/`, а VS Code хранит состояние плагинов в одном `user-data-dir`. При работе двух окон оба аккаунта читают одно и то же место → после перезапуска один перетирает другой.

## Решение

Два набора изолированных конфигов + алиасы в терминале:

| Алиас | Claude config | VS Code profile |
|---|---|---|
| `claude1` / `vscode1` | `~/.claude-acc1/` | `~/.vscode-profile-acc1/` |
| `claude2` / `vscode2` | `~/.claude-acc2/` | `~/.vscode-profile-acc2/` |

Оригинальные `claude` и `code .` работают как раньше — ничего не сломано.

---

## Первоначальная настройка (один раз)

### 1. Запустить setup-скрипт

```bash
bash scripts/setup-dual-claude.sh
source ~/.zshrc
```

Скрипт:
- Создаёт бэкап `~/.zshrc.bak.<timestamp>`
- Создаёт директории `~/.claude-acc1` и `~/.claude-acc2`
- Добавляет 4 алиаса в `~/.zshrc` (идемпотентно — повторный запуск безопасен)

### 2. Залогиниться в Claude CLI (по одному разу)

```bash
claude1
# внутри Claude: /login → войти под аккаунтом #1
# выйти: /exit

claude2
# внутри Claude: /login → войти под аккаунтом #2
# выйти: /exit
```

### 3. Настроить VS Code профили (по одному разу)

```bash
# Открыть VS Code с профилем аккаунта #1:
vscode1 "~/projects/acme-platform"

# В этом окне:
# 1. Extensions → найти "Claude Code" → Install
# 2. Claude Code sidebar → Sign in → войти под аккаунтом #1
```

```bash
# Открыть VS Code с профилем аккаунта #2:
vscode2 "~/projects/acme-platform-acc2"

# В этом окне:
# 1. Extensions → найти "Claude Code" → Install
# 2. Claude Code sidebar → Sign in → войти под аккаунтом #2
```

После этого каждый следующий запуск `vscode1` / `vscode2` сразу подхватывает нужный аккаунт без повторного логина.

---

## Ежедневное использование

```bash
# Терминал — acc1:
claude1

# Терминал — acc2:
claude2

# VS Code — acc1 (открыть проект):
vscode1 "~/projects/acme-platform"

# VS Code — acc2 (открыть проект):
vscode2 "~/projects/acme-platform-acc2"
```

Перезагрузка Mac не сбрасывает изоляцию — алиасы и профили постоянны.

---

## Откат

```bash
# 1. Найти бэкап:
ls -lt ~/.zshrc.bak.* | head -3

# 2. Восстановить .zshrc:
cp ~/.zshrc.bak.<timestamp> ~/.zshrc
source ~/.zshrc

# 3. Удалить профили (опционально):
rm -rf ~/.claude-acc1 ~/.claude-acc2
rm -rf ~/.vscode-profile-acc1 ~/.vscode-profile-acc2
```

Оригинальный `~/.claude/` не изменялся — `claude` продолжает работать как прежде.

---

## Проверка после установки

```bash
# Алиасы определены:
type claude1 && type claude2 && type vscode1 && type vscode2

# Оригинальный claude не сломан:
claude --version

# Скрипт идемпотентен:
bash scripts/setup-dual-claude.sh
grep -c "claude1" ~/.zshrc   # → 1 (не дублируется)
```
