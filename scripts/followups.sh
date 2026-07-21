#!/usr/bin/env bash
# Followup tracker (CLAUDE.md §4 — жизненный цикл follow-ups).
#
# Единый источник правды по техдолгу — GitHub Issues с меткой «followup».
# Два аккаунта (acc1/acc2) видят одно и то же серверное состояние.
# Закрытие: PR пишет «Closes #N» в теле → GitHub закрывает issue при merge в main.
#
# Usage:
#   scripts/followups.sh                         # открытые issues (по умолчанию)
#   scripts/followups.sh --all                   # открытые + закрытые
#   scripts/followups.sh --count                 # только число открытых
#   scripts/followups.sh --slice <slug>           # фильтр по слайсу
#
# Exit code всегда 0 — это отчёт, а не gate.
# Требует: gh CLI, авторизованный под вашей GitHub-организацией.

set -euo pipefail
IFS=$'\n\t'

if ! command -v gh &>/dev/null; then
  echo "Ошибка: gh CLI не установлен или не в PATH." >&2
  exit 1
fi

mode="open"
slice_filter=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --all)   mode="all"; shift ;;
    --count) mode="count"; shift ;;
    --slice) slice_filter="$2"; shift 2 ;;
    *) printf 'Неизвестный аргумент: %s (допустимо: --all | --count | --slice <slug>)\n' "$1" >&2; exit 2 ;;
  esac
done

# Строим аргументы gh issue list через массив
declare -a GH_ARGS
GH_ARGS=("-l" "followup" "--limit" "200")
[ -n "$slice_filter" ] && GH_ARGS+=("-l" "slice:${slice_filter}")
[ "$mode" = "all" ]    && GH_ARGS+=("--state" "all")

if [ "$mode" = "count" ]; then
  count=$(gh issue list "${GH_ARGS[@]}" --json number --jq 'length' 2>/dev/null) || {
    echo "Ошибка: gh issue list завершился с ошибкой. Проверьте авторизацию: gh auth status" >&2
    exit 1
  }
  echo "$count"
  exit 0
fi

issues_json=$(gh issue list "${GH_ARGS[@]}" --json number,title,labels,state 2>/dev/null) || {
  echo "Ошибка: gh issue list завершился с ошибкой. Проверьте авторизацию: gh auth status" >&2
  exit 1
}

total=$(GH_JSON="$issues_json" python3 -c "import os,json; print(len(json.loads(os.environ['GH_JSON'])))" 2>/dev/null || echo "?")

if [ "$total" = "0" ]; then
  echo "Нет follow-ups по заданным критериям."
  exit 0
fi

GH_JSON="$issues_json" python3 <<'PYEOF'
import os, json

data = json.loads(os.environ['GH_JSON'])

by_slice = {}

for item in data:
    slices = [l["name"] for l in item["labels"] if l["name"].startswith("slice:")]
    key = slices[0] if slices else "__none__"
    by_slice.setdefault(key, []).append(item)

for key in sorted(by_slice.keys()):
    items = by_slice[key]
    header = key.replace("slice:", "") if key != "__none__" else "(слайс не указан)"
    open_n = sum(1 for i in items if i["state"] == "OPEN")
    print(f"\n\033[1;34m▶ {header}\033[0m  (открыто: {open_n})")
    for i in sorted(items, key=lambda x: x["number"]):
        state_icon = "\033[32m✓\033[0m" if i["state"] == "CLOSED" else "○"
        routes = [l["name"].replace("route:", "") for l in i["labels"] if l["name"].startswith("route:")]
        route_str = f"  [{routes[0]}]" if routes else ""
        print(f"  {state_icon} #{i['number']:>4}  {i['title']}{route_str}")

open_total   = sum(1 for i in data if i["state"] == "OPEN")
closed_total = sum(1 for i in data if i["state"] == "CLOSED")
print(f"\n\033[1m— итого открыто: {open_total}; закрыто: {closed_total} —\033[0m")
PYEOF

exit 0
