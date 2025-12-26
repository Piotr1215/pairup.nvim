# Draft Mode Validation Guide

## Prerequisites

1. Hook script installed:
   ```bash
   ls -la ~/.claude/scripts/__pairup_draft_edit_hook.sh
   # Should show: rwxrwxr-x (executable)
   ```

2. Hook configured in `~/.claude/settings.json`:
   ```bash
   jq '.hooks.PreToolUse[] | select(.matcher == "Edit")' ~/.claude/settings.json
   # Should show the draft edit hook
   ```

## Step-by-Step Validation

### 1. Start Pairup from Neovim

```vim
:Pairup start
```

This launches Claude Code with `PAIRUP_SESSION_ID` set. **Only this Claude session will capture drafts.**

### 2. Enable Draft Mode

```vim
:Pairup drafts enable
```

Creates flag file: `/tmp/pairup-draft-mode-<session_id>`

### 3. Create Test File

```vim
:edit /tmp/test-draft.lua
```

Add content:
```lua
local function hello()
  print("hello")
end
```

Save: `:w`

### 4. Add a Marker

```vim
:normal Gcc
```

This inserts `cc:` marker. Add instruction:
```lua
-- cc: add error handling
local function hello()
  print("hello")
end
```

Save: `:w`

### 5. Verify Draft Captured

In the pairup terminal, you should see:
- Claude thinking about the change
- Message: "Edit captured as draft. Use :Pairup drafts apply when ready."

Check drafts in Neovim:
```vim
:Pairup drafts count
" Should show: "1 pending draft(s)"

:Pairup drafts preview
" Opens quickfix with draft details
```

Check draft file:
```bash
cat /tmp/pairup-drafts.json | jq .
```

Should contain one draft entry with your edit.

### 6. Apply Draft

```vim
:Pairup drafts apply
```

The edit should be applied to the file, and draft count should go to 0.

## Troubleshooting

### Hook not intercepting edits

**Check session ID in pairup terminal:**
```vim
:Pairup toggle
" Switch to terminal, then:
```
```bash
echo $PAIRUP_SESSION_ID
# Should show a numeric session ID
```

**Verify flag file exists:**
```bash
ls -la /tmp/pairup-draft-mode-*
# Should show file matching your session ID
```

**Check if draft mode is enabled:**
```vim
:lua print(vim.g.pairup_draft_mode and "enabled" or "disabled")
```

### Claude applies edits directly (not capturing)

1. Make sure you ran `:Pairup drafts enable`
2. Verify `PAIRUP_SESSION_ID` is set in the pairup terminal (not other terminals)
3. Check hook is not exiting early:
   ```bash
   # Test hook manually:
   echo '{"tool_name":"Edit","tool_input":{"file_path":"/tmp/test.txt","old_string":"old","new_string":"new"}}' | \
     PAIRUP_SESSION_ID="test" \
     bash -c 'touch /tmp/pairup-draft-mode-test && ~/.claude/scripts/__pairup_draft_edit_hook.sh'
   # Should output: {"decision":"block","reason":"Edit captured as draft..."}
   # Exit code should be 2
   echo $?
   ```

### Other Claude Code sessions capturing drafts

This won't happen. The hook checks `PAIRUP_SESSION_ID` and only intercepts if:
1. The env var is set (only in pairup-launched sessions)
2. Draft mode is enabled for that specific session

Regular Claude Code sessions won't have `PAIRUP_SESSION_ID` set, so the hook exits early (line 15 of hook script).

## Session Isolation Explained

**Design:** Draft mode is session-specific by design.

**Why:** You might have multiple Claude Code sessions running:
- One for pairup (pair programming with drafts)
- One for general work (direct edits)
- One for documentation (direct edits)

Only the session started from `:Pairup start` should capture drafts.

**Implementation:**
1. Pairup sets `PAIRUP_SESSION_ID` when starting Claude
2. Hook checks this env var exists
3. Hook checks flag file `/tmp/pairup-draft-mode-$PAIRUP_SESSION_ID` exists
4. Both must be true to intercept edits

**Cleanup:** Flag files are cleaned up when pairup stops or when you run `:Pairup drafts disable`.

## Advanced: Multiple Pairup Instances

You can have multiple Neovim instances each with their own pairup session:

```bash
# Terminal 1 - Neovim instance 1
nvim project1/
:Pairup start
:Pairup drafts enable

# Terminal 2 - Neovim instance 2
nvim project2/
:Pairup start
:Pairup drafts enable
```

Each will have:
- Unique `PAIRUP_SESSION_ID`
- Separate flag file
- **Separate draft queue** (all use `/tmp/pairup-drafts.json` - FIXME: should be per-session)

**Known limitation:** Draft file is currently shared across all sessions. This means if you have multiple pairup instances with draft mode enabled, their drafts will be mixed in one queue. This is tracked in the backlog for a future fix.
