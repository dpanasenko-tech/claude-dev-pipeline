# Features

Every non-trivial change lives in its own folder under `docs/features/<slug>/`. The folder is the paper trail for the change — planner through release-engineer all write here.

## Slug convention
- `kebab-case`, short, stable. Example: `billing-portal-mvp`, `oauth-google-signin`.
- Once chosen, the slug does not change. If scope diverges, create a new slug and link.

## Folder contents
```
docs/features/<slug>/
  brief.md          # planner output
  plan.md           # architect output
  test-matrix.md    # tdd-engineer output
  review.md         # reviewer output
  release.md        # release-engineer output
  followups.md      # optional — out-of-scope items noticed during work
```

## Lifecycle
1. **planner** writes `brief.md`. **Human approves.**
2. **architect** writes `plan.md`. **Human approves.**
3. **tdd-engineer** writes failing tests + `test-matrix.md`. **Human approves.**
4. **implementer** turns tests green. **Human approves.**
5. **reviewer** writes `review.md`. **Reviewer must say `APPROVE` to advance.**
6. **release-engineer** writes `release.md`. **Verdict: GO or NO-GO.**

Skipping a stage requires a written waiver in that stage's file (e.g., "`plan.md` skipped — single-line copy fix"). Stages 5 and 6 are never skipped.

## Naming follow-ups
- Out-of-scope discoveries during implementation go to `followups.md`. They do **not** get fixed in the current slice. They become candidate slugs for future briefs.
