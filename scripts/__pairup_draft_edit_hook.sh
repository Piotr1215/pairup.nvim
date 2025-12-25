#!/usr/bin/env bash
set -eo pipefail

# PreToolUse hook for Edit - captures edits as drafts instead of applying
# Exit codes: 0=allow, 2=block
# Only blocks for the specific pairup session (via PAIRUP_SESSION_ID env var)

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // ""')

# Only intercept Edit tool
[[ "$TOOL" != "Edit" ]] && exit 0

# Check if this is a pairup session with draft mode enabled
[[ -z "$PAIRUP_SESSION_ID" ]] && exit 0
[[ ! -f "/tmp/pairup-draft-mode-$PAIRUP_SESSION_ID" ]] && exit 0

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""')
OLD_STRING=$(echo "$INPUT" | jq -r '.tool_input.old_string // ""')
NEW_STRING=$(echo "$INPUT" | jq -r '.tool_input.new_string // ""')

# Skip if missing required fields
[[ -z "$FILE_PATH" || -z "$NEW_STRING" ]] && exit 0

DRAFTS_FILE="/tmp/pairup-drafts.json"
LOCK_FILE="/tmp/pairup-drafts.lock"

# File locking to prevent race conditions
exec 200>"$LOCK_FILE"
flock -x 200

# Load existing drafts or start fresh
if [[ -f "$DRAFTS_FILE" ]]; then
  DRAFTS=$(cat "$DRAFTS_FILE")
else
  DRAFTS="[]"
fi

# Create new draft entry with jq (handles escaping safely)
DRAFT=$(jq -n \
  --arg id "$(date +%s%N)" \
  --arg file "$FILE_PATH" \
  --arg old "$OLD_STRING" \
  --arg new "$NEW_STRING" \
  --arg ts "$(date -Iseconds)" \
  '{id:$id, file:$file, old_string:$old, new_string:$new, created_at:$ts}')

# Atomic write: temp file + rename
TEMP_FILE=$(mktemp)
echo "$DRAFTS" | jq --argjson draft "$DRAFT" '. + [$draft]' > "$TEMP_FILE"
mv "$TEMP_FILE" "$DRAFTS_FILE"

flock -u 200

# Block the edit (exit 2) and provide feedback
echo '{"decision":"block","reason":"Edit captured as draft. Use :Pairup drafts apply when ready."}'
exit 2
