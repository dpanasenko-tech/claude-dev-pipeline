# Claude Workflow — Onboarding

> 5-minute read. Print and pin if useful.

## The pipeline

```
planner -> architect -> tdd-engineer -> implementer -> reviewer -> release-engineer
   ^           ^             ^               ^              ^              ^
   |           |             |               |              |              |
human-approve  human-approve human-approve  human-approve   verdict       verdict
```

Each `->` is a **human approval gate**. Agents do not auto-advance.

## How to invoke
- Type `@planner ...` (or `@architect`, etc.) in a Claude Code session, OR
- Ask Claude: "use the **planner** subagent to draft a brief for <feature>."
- For trivial changes (typo, copy), skip 1–3 but never skip the reviewer.

## Per-feature paper trail
Everything lives in `docs/features/<slug>/`. See `docs/features/README.md`.

## What the user (you) does
- Approve or reject each artifact in turn. Be specific in rejections.
- Pick the slug. Keep it stable.
- Run `scripts/quality-check.sh` locally if Claude doesn't.
- Final call on `GO/NO-GO` rests with you, regardless of agent verdicts.

## When something feels wrong
- Stop the pipeline. Send the artifact back to the originating agent with the specific issue.
- Do **not** patch the next stage to compensate.

## Common anti-patterns to refuse
- "Let me just implement it real quick" — no plan, no tests → reject.
- "I noticed and fixed an unrelated issue" → revert, move to `followups.md`.
- "Tests were failing so I updated them" → halt, route to tdd-engineer.
- "Looks good to me" with no findings from reviewer → demand the mandatory passes.
- "Release is small, skipping smoke" → no.

## Cheat sheet — which agent for what

| Situation | Agent |
|---|---|
| Vague feature request from stakeholder | `planner` |
| Brief approved, need API/data design | `architect` |
| Plan approved, ready to pin behavior | `tdd-engineer` |
| Failing tests in place, ready to build | `implementer` |
| Tests green, need an adversarial second pair of eyes | `reviewer` |
| Reviewer approved, need to ship safely | `release-engineer` |

## Stack setup (TODO once chosen)
- Fill in `scripts/quality-check.sh` with real format/lint/typecheck/test commands.
- Fill in `scripts/smoke-check.sh` with real boot + health-check + critical-path command.
- Update `docs/architecture/TEST-STRATEGY.template.md` local/CI commands.
- Add CI config (`.github/workflows/` or equivalent) that runs `scripts/quality-check.sh`.
- Add a `.env.example` and gitignore the real `.env`.

## Emergency
- Hotfix flow: `planner` (1 paragraph brief is fine) → `tdd-engineer` (regression test) → `implementer` → `reviewer` (full pass, no shortcuts) → `release-engineer`. Speed comes from small scope, not skipped stages.
