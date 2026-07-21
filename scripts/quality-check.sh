#!/usr/bin/env bash
# Single entry point for local quality gates (CLAUDE.md §7 Definition of Done).
# Stack: Python 3.12 + uv. Step order: format -> lint -> typecheck -> test.
# Fails fast on the first failing step. Returns non-zero so CI/hooks can rely on it.

set -euo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

have() { command -v "$1" >/dev/null 2>&1; }

step() {
  local name="$1"; shift
  printf '\n\033[1;34m▶ %s\033[0m\n' "$name"
  "$@"
}

require() {
  local tool="$1"
  if ! have "$tool"; then
    printf '\033[31m✗ %s not found.\033[0m Install uv: https://docs.astral.sh/uv/\n' "$tool"
    exit 1
  fi
}

require uv

# ---------- 1. format ----------
fmt() {
  uv run ruff format --check .
}

# ---------- 2. lint ----------
lint() {
  uv run ruff check .
}

# ---------- 3. typecheck ----------
typecheck() {
  uv run mypy src
}

# ---------- 4. project-specific consistency guards (optional) ----------
# Add your own invariant checks here (e.g. a DB view whose SQL must stay in
# sync with a checked-in YAML/schema file). Keep each guard as its own script
# under scripts/db/ or similar, called from a dedicated step like this one.
# extra_guard() {
#   bash scripts/db/check_some_invariant.sh
# }

# ---------- 5. test ----------
test_suite() {
  uv run pytest -q
}

step "Format"        fmt
step "Lint"          lint
step "Typecheck"     typecheck
step "Tests"         test_suite

printf '\n\033[1;32m✓ quality-check passed\033[0m\n'
