# PR-Based Workflow

Каждая стадия разработки = один GitHub PR. Стадии выполняются последовательно,
любой аккаунт может делать любую стадию.

## Жизненный цикл одной стадии

```
acc выполняет работу
    → git push feature/<slug>-stageN
    → gh pr create (base: main)
    → /review <PR> (опционально, Claude reviewer)
    → human читает review → approve или request changes
    → gh pr merge --squash
    → следующая стадия начинается от обновлённого main
```

## PR naming

```
Title:  [S<X>] Stage N/6: <Stage Name> — <slug>
Branch: feature/<slug>-stageN

Примеры:
  [S1] Stage 1/6: Brief — billing-export
  [S1] Stage 4/6: Implementation — billing-export
  [S3] Stage 2/6: Plan — notifications-rail
```

## PR body template

```markdown
## What
<одно предложение что сделано>

## Artifact
- `docs/features/<slug>/brief.md`

## Checklist
- [ ] CI green
- [ ] /review passed or human reviewed
- [ ] No unresolved comments
```

## Стадии и их артефакты

| Stage | Артефакт в PR | Кто создаёт |
|---|---|---|
| 1 Brief | `docs/features/<slug>/brief.md` | planner |
| 2 Plan | `docs/features/<slug>/plan.md` | architect |
| 3 Tests | `tests/<slug>/`, `docs/features/<slug>/test-matrix.md` | tdd-engineer |
| 4 Impl | `src/`, тесты зелёные | implementer |
| 5 Review | `docs/features/<slug>/review.md` | reviewer |
| 6 Release | `docs/features/<slug>/release.md` | release-engineer |

## Когда merge в main

**После каждой стадии** — squash merge. Следующая стадия начинается от актуального `main`.
Никогда не мержить стадию N, если стадия N-1 не смержена.

## Если нужны правки после review

```bash
# acc правит файлы в той же ветке и пушит:
git add <files>
git commit -m "[STAGE N/6] fix: <что исправлено>"
git push origin feature/<slug>-stageN   # обычный push, PR обновится автоматически
```

> Force-push (`--force-with-lease`) допустим только на feature-ветках этой стадии —
> никогда на `main`. См. CLAUDE.md §13.

## Запустить Claude review

```bash
# В Claude Code сессии (внутри директории репо):
/review <PR-number>

# Claude прочтёт:
# - diff PR (Files changed)
# - docs/features/<slug>/plan.md
# - docs/features/<slug>/test-matrix.md (stage 3+)
# - CLAUDE.md критерии

# Claude выдаст:
# - список проблем/блокеров (если есть)
# - "Approved for merge" (если всё ОК)
```

## Merge стратегия

Всегда **squash merge** — одна стадия = один коммит в main с чистым сообщением.
После merge ветка `feature/<slug>-stageN` **обязательно удаляется** — флаг `--delete-branch` обязателен.

```bash
gh pr merge <PR-number> --squash --delete-branch
```

Merge без `--delete-branch` — ошибка процесса.
