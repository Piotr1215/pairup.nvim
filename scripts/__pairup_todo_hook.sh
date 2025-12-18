#!/usr/bin/env bash
set -eo pipefail

INPUT=$(cat)
SESSION=$(echo "$INPUT" | jq -r '.session_id // ""')
[ -z "$SESSION" ] && exit 0

TODOS=$(echo "$INPUT" | jq -c '.tool_input.todos // []')
TOTAL=$(echo "$TODOS" | jq 'length')
COMPLETED=$(echo "$TODOS" | jq '[.[] | select(.status == "completed")] | length')
CURRENT=$(echo "$TODOS" | jq -r '[.[] | select(.status == "in_progress")][0].content // ""')

jq -n \
  --arg s "$SESSION" \
  --argjson t "$TOTAL" \
  --argjson c "$COMPLETED" \
  --arg cur "$CURRENT" \
  '{session:$s,total:$t,completed:$c,current:$cur}' \
  > "/tmp/pairup-todo-${SESSION}.json"
