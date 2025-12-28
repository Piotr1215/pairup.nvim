# Indicator Placement Design

## Current Implementation

**Lualine:** Injected into `lualine_c` (center-left, with filename)
**Native:** Appended to end of statusline (right side before line/column)

```
Current lualine:
┌────────────────────────────────────────────────────────────────┐
│ file.lua [+] [CL] │                      │ main  utf-8  lua │
└────────────────────────────────────────────────────────────────┘
   lualine_a  lualine_c    lualine_x           lualine_y  lualine_z

Current native:
┌────────────────────────────────────────────────────────────────┐
│ file.lua [+][CL]                                    100,25 50% │
└────────────────────────────────────────────────────────────────┘
```

## Placement Options for Dual Indicators

### Option 1: Keep Both in Current Location (lualine_c)

**Layout:**
```
┌────────────────────────────────────────────────────────────────┐
│ file.lua [+] [CL:3/5][CP:ready] │               │ main  utf-8 │
└────────────────────────────────────────────────────────────────┘
```

**Pros:**
- Minimal change to existing setup
- Indicators stay grouped together
- Left side is traditionally for "what am I working on"

**Cons:**
- Can get crowded in lualine_c with filename
- Takes space from filename display

### Option 2: Split Across Sections

**Layout A - LOCAL left, PERIPHERAL right:**
```
┌────────────────────────────────────────────────────────────────┐
│ file.lua [+] [CL:3/5] │                  │ [CP:ready]  main │
└────────────────────────────────────────────────────────────────┘
   lualine_c                lualine_x         lualine_y
```

**Layout B - Both on right:**
```
┌────────────────────────────────────────────────────────────────┐
│ file.lua [+] │                  │ [CL:3/5][CP:ready]  main  │
└────────────────────────────────────────────────────────────────┘
   lualine_c      lualine_x         lualine_y          lualine_z
```

**Pros:**
- Clear visual separation (LOCAL = my work, PERIPHERAL = background work)
- More space for each indicator
- Right side traditionally for status info

**Cons:**
- Harder to compare states at a glance
- Less intuitive grouping

### Option 3: Context-Aware Single Location

**Shows only relevant indicator based on mode:**

```
# In main worktree:
┌────────────────────────────────────────────────────────────────┐
│ file.lua [+] [CL:3/5] │                      │ main  utf-8 lua │
└────────────────────────────────────────────────────────────────┘

# In peripheral worktree:
┌────────────────────────────────────────────────────────────────┐
│ file.lua [+] [CP:ready] │                    │ main  utf-8 lua │
└────────────────────────────────────────────────────────────────┘

# When either is working/ready (always show):
┌────────────────────────────────────────────────────────────────┐
│ file.lua [+] [CL:processing][CP:3/8] │        │ main  utf-8 │
└────────────────────────────────────────────────────────────────┘
```

**Pros:**
- Cleanest display - no clutter
- Focuses on what matters in current context
- Automatic adaptation to workflow

**Cons:**
- May miss peripheral progress if focused in main worktree
- Requires smart detection logic

## Recommended Placement (SIMPLIFIED)

**Single Location, Independent Display:**

**Placement:** lualine_c (keep current location)
```lua
lualine_c = { 'filename', 'pairup' }
```

**Display Logic:**
- Only LOCAL running: `[CL:3/5]`
- Only PERIPHERAL running: `[CP:ready]`
- Both running: `[CL:3/5] | [CP:ready]`
- Neither running: `` (empty, hidden)

**Rationale:**
- Simple and predictable
- Shows only what's active
- Clear separation with `|` divider when both run
- No complex mode switching

## Color Coding Implementation

### Lualine Component Update

```lua
-- lua/lualine/components/pairup.lua
function M:update_status()
  local local_ind = vim.g.pairup_indicator or ''
  local periph_ind = vim.g.pairup_peripheral_indicator or ''

  -- Build display: only show active indicators
  local parts = {}

  if local_ind ~= '' then
    table.insert(parts, '%#PairLocalIndicator#' .. local_ind .. '%*')
  end

  if periph_ind ~= '' then
    table.insert(parts, '%#PairPeripheralIndicator#' .. periph_ind .. '%*')
  end

  -- Join with separator if both present
  if #parts == 0 then
    return ''
  elseif #parts == 1 then
    return parts[1]
  else
    return parts[1] .. ' %#PairSeparator#|%* ' .. parts[2]
  end
end
```

### Native Statusline Update

```vim
" For native statusline with colors
set statusline=%f\ %m%r%h%w%=
set statusline+=%{luaeval('require(\"pairup.utils.indicator\").get_colored_indicator()')}
set statusline+=\ %l,%c\ %P
```

## Visual Hierarchy

**Color + Position = Instant Recognition**

```
GREEN [CL:3/5]  ← My active work, immediate attention
BLUE [CP:ready] ← Background work, review when ready
```

**State Priority (Combined Mode):**
1. Error (red) - immediate attention
2. Working/Progress (green/blue) - active
3. Ready (green/blue) - review needed
4. Processing (yellow) - waiting
5. Idle (dim) - nothing happening

## Configuration Options

Allow users to customize placement and separator:

```lua
require('pairup').setup({
  statusline = {
    auto_inject = true,  -- Auto-inject into statusline
    separator = '|',     -- Separator between [CL] and [CP] when both active

    -- Lualine-specific
    lualine = {
      section = 'lualine_c',  -- or 'lualine_y', 'lualine_x'
      position = nil,         -- auto-append to section
    },

    -- Color overrides
    colors = {
      local_fg = '#50fa7b',      -- Green for [CL]
      peripheral_fg = '#8be9fd', -- Blue for [CP]
      separator_fg = '#6272a4',  -- Gray for separator
      error_fg = '#ff5555',      -- Red for errors
      suspended_fg = '#6272a4',  -- Gray for suspended
    },
  },
})
```

## Implementation Priority

1. **Phase 1:** Add `vim.g.pairup_peripheral_indicator` variable support
2. **Phase 2:** Update lualine component to show both indicators with separator
3. **Phase 3:** Add color coding (green for [CL], blue for [CP], gray separator)
4. **Phase 4:** Update native statusline support for dual indicators
5. **Phase 5:** Add configuration options for separator and colors

## Display Examples

**Only LOCAL active:**
```
┌────────────────────────────────────────────────────────────────┐
│ file.lua [+] [CL:3/5] │                      │ main  utf-8 lua │
└────────────────────────────────────────────────────────────────┘
```

**Only PERIPHERAL active:**
```
┌────────────────────────────────────────────────────────────────┐
│ file.lua [+] [CP:ready] │                    │ main  utf-8 lua │
└────────────────────────────────────────────────────────────────┘
```

**Both active:**
```
┌────────────────────────────────────────────────────────────────┐
│ file.lua [+] [CL:processing] | [CP:3/8] │     │ main  utf-8 │
└────────────────────────────────────────────────────────────────┘
                    green          gray   blue
```

**Neither active:**
```
┌────────────────────────────────────────────────────────────────┐
│ file.lua [+] │                              │ main  utf-8 lua │
└────────────────────────────────────────────────────────────────┘
```

## Testing Scenarios

Test placement with different statusline setups:

1. **Minimal lualine:** Only filename + pairup
2. **Busy lualine:** Git, diagnostics, LSP, filename, pairup
3. **Native statusline:** Default Neovim statusline
4. **Custom statusline:** User-configured with other plugins

Verify visual clarity in each scenario.
