# Pairup Status Indicator - Current Implementation

## State Variables

| Variable | Type | Purpose | Location |
|----------|------|---------|----------|
| `vim.g.pairup_indicator` | string | Display value for statusline | indicator.lua:15 |
| `vim.g.pairup_pending` | string\|nil | Filepath being processed | indicator.lua:173 |
| `vim.g.pairup_pending_time` | number\|nil | Timestamp when processing started | indicator.lua:174 |
| `vim.g.pairup_queued` | boolean | Multiple files queued | indicator.lua:188 |
| `/tmp/pairup-todo-*.json` | file | Hook-based todo progress | indicator.lua:76 |

## States

| State | Display | Condition | Meaning |
|-------|---------|-----------|---------|
| Not Running | `''` | No terminal buffer | Claude not started |
| Idle | `[C]` | Terminal exists, no pending/queued | Claude waiting |
| Queued | `[C:queued]` | `vim.g.pairup_queued = true` | Multiple files queued |
| Processing | `[C:processing]` | `vim.g.pairup_pending` set | Claude editing file |
| Progress | `[C:n/m]` | Todo total > 0, completed < total | Claude working through todos |
| Ready | `[C:ready]` | Todo completed == total | All todos done |

## State Transitions (Functions)

### `M.update()` - Main state calculator
```lua
if not providers.find_terminal() then
  set_indicator('')  -- Not Running
elseif vim.g.pairup_queued then
  set_indicator('[C:queued]')  -- Queued
elseif vim.g.pairup_pending then
  set_indicator('[C:processing]')  -- Processing
else
  set_indicator('[C]')  -- Idle
end
```

### `check_hook_state()` - Todo progress updater (500ms poll)
```lua
if total == 0 then
  set_indicator('[C]')  -- No todos
elseif completed == total then
  set_indicator('[C:ready]')  -- All done
  -- Auto-clear after 3s
else
  set_indicator('[C:n/m]')  -- In progress
end
```

### `M.set_pending(filepath)` - Mark file being processed
- Sets `vim.g.pairup_pending = filepath`
- Sets `vim.g.pairup_pending_time = os.time()`
- Calls `M.update()`

### `M.clear_pending()` - Clear processing state
- Clears `vim.g.pairup_pending`
- Clears `vim.g.pairup_pending_time`
- Sets `vim.g.pairup_queued = false`
- Calls `M.update()`

### `M.set_queued()` - Mark queue active
- Sets `vim.g.pairup_queued = true`
- Calls `M.update()`

## Timeout Logic

### Processing timeout (60s)
```lua
-- indicator.lua:197-199
local elapsed = os.time() - (vim.g.pairup_pending_time or 0)
if elapsed > 60 then
  M.clear_pending()  -- Auto-clear stale
end
```

### Ready timeout (3s)
```lua
-- indicator.lua:140-144
vim.defer_fn(function()
  if vim.g.pairup_indicator == '[C:ready]' then
    M.update()  -- Transition back to idle
  end
end, 3000)
```

## Hook-based Progress

- File: `/tmp/pairup-todo-{session_id}.json`
- Format: `{ total: number, completed: number, current: string }`
- Polling: 500ms timer (indicator.lua:216)
- Priority: Hook state overrides pending/queued state
