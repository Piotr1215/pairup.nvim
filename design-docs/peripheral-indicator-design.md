# Peripheral Status Indicator Design

## Overview

This document outlines the design for integrating peripheral Claude status indicators with the existing LOCAL Claude indicator system in pairup.nvim.

## State Models

### LOCAL Claude States
See diagram: `diagrams/pairup-status-states.puml`

**Color:** Green (to distinguish from PERIPHERAL)

Six states tracked via global variables:
1. **Not Running** - `''` (no terminal)
2. **Idle** - `'[CL]'` (terminal exists, waiting)
3. **Queued** - `'[CL:queued]'` (vim.g.pairup_queued = true)
4. **Processing** - `'[CL:processing]'` (vim.g.pairup_pending set)
5. **Progress** - `'[CL:n/m]'` (todo tracking via hook)
6. **Ready** - `'[CL:ready]'` (todos completed)

### PERIPHERAL Claude States
See diagram: `diagrams/pairup-peripheral-states.puml`

**Color:** Blue (to distinguish from LOCAL)

Seven states for autonomous Claude in sibling worktree:
1. **Not Running** - `''` (no worktree exists)
2. **Spawning** - `'[CP:spawn]'` (creating worktree + terminal, 30s timeout)
3. **Idle** - `'[CP]'` (terminal exists, waiting for work)
4. **Analyzing** - `'[CP:analyze]'` (reading spec, exploring codebase)
5. **Working** - `'[CP:n/m]'` (active implementation with todo tracking)
6. **Ready** - `'[CP:ready]'` (task complete, awaiting review)
7. **Error** - `'[CP:err]'` (spawn failed or runtime error)

## Integration Strategy (SIMPLIFIED)

See diagram: `diagrams/pairup-indicator-integration.puml`

### Independent Indicators with Separator

**Display:** Show only active indicators, separate with `|` when both running

**Rules:**
- LOCAL active → show `[CL:state]` (green)
- PERIPHERAL active → show `[CP:state]` (blue)
- Both active → show `[CL:state] | [CP:state]`
- Neither active → show nothing (hidden)

**Example states:**
- `[CL:3/10]` - only LOCAL working
- `[CP:ready]` - only PERIPHERAL ready
- `[CL:processing] | [CP:3/8]` - both active
- `` - neither running

**Rationale:**
- Simple and predictable behavior
- No mode switching or complex logic
- Shows exactly what's happening
- Clean visual separation with `|` divider
- Color coding provides instant recognition (green=LOCAL, blue=PERIPHERAL)

## Technical Implementation

### Color Coding

Indicators use highlight groups for visual distinction:

```lua
-- lua/pairup/utils/indicator.lua
vim.api.nvim_set_hl(0, 'PairLocalIndicator', { fg = '#50fa7b', bold = true })   -- Green
vim.api.nvim_set_hl(0, 'PairPeripheralIndicator', { fg = '#8be9fd', bold = true }) -- Blue
```

Statusline integration:
```lua
-- Example with custom statusline
local local_indicator = '%#PairLocalIndicator#' .. vim.g.pairup_indicator .. '%*'
local peripheral_indicator = '%#PairPeripheralIndicator#' .. vim.g.pairup_peripheral_indicator .. '%*'
```

### Variables to Add

```lua
-- Peripheral state tracking (mirrors LOCAL pattern)
vim.g.pairup_peripheral_indicator = ''
vim.g.pairup_peripheral_pending = nil
vim.g.pairup_peripheral_queued = false

-- Statusline config
vim.g.pairup_statusline_separator = '|'  -- Separator between indicators
```

### Todo Tracking

Reuse existing hook-based system with different file prefix:
- LOCAL: `/tmp/pairup-todo-*.json`
- PERIPHERAL: `/tmp/pairup-peripheral-todo-*.json`

Same 500ms polling interval, same JSON structure.

### Indicator Update Logic

```lua
-- lua/pairup/utils/indicator.lua

-- Update LOCAL indicator
function M.update_local()
  local state = get_local_state()
  vim.g.pairup_indicator = state
end

-- Update PERIPHERAL indicator
function M.update_peripheral()
  local state = get_peripheral_state()
  vim.g.pairup_peripheral_indicator = state
end

-- Called by statusline component to build display
function M.get_display()
  local local_ind = vim.g.pairup_indicator or ''
  local periph_ind = vim.g.pairup_peripheral_indicator or ''
  local sep = vim.g.pairup_statusline_separator or '|'

  if local_ind ~= '' and periph_ind ~= '' then
    return local_ind .. ' ' .. sep .. ' ' .. periph_ind
  elseif local_ind ~= '' then
    return local_ind
  elseif periph_ind ~= '' then
    return periph_ind
  else
    return ''
  end
end
```

## Next Steps

1. Implement peripheral state detection in `lua/pairup/peripheral.lua`
2. Extend `lua/pairup/utils/indicator.lua` with mode-aware update logic
3. Add config option to `lua/pairup/config.lua`
4. Update health check to verify peripheral indicator
5. Document in README with examples

## Files to Modify

- `lua/pairup/peripheral.lua` - Add state tracking variables
- `lua/pairup/utils/indicator.lua` - Extend update() with peripheral support
- `lua/pairup/config.lua` - Add indicator_mode option
- `lua/pairup/health.lua` - Verify peripheral indicator working
- `test/pairup/indicator_spec.lua` - Add tests for all three modes

## Testing Strategy

Test matrix for all three modes × all state combinations:
- Both idle
- LOCAL working, PERIPHERAL idle
- LOCAL idle, PERIPHERAL working
- Both working
- LOCAL ready, PERIPHERAL working
- Error states
- Worktree context switching
