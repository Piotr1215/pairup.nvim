# pairup.nvim

Inline AI pair programming for Neovim.

> 🔺 **Breaking Changes in v4.0** 🔺
>
> This version removes the overlay system, sessions, RPC, and marker-based suggestions
> to focus on one thing: simple inline editing with `cc:`/`uu:` markers.
> See [v4-architecture.md](./v4-architecture.md) for details.
>
> **Why?** Less complexity, more reliability. Claude edits files directly — no parsing,
> no overlays, no state management. Just write `cc:`, save, and Claude handles it.
>
> **Need the old features?** Use `git checkout legacy-v3` or `git checkout v3.0.0`.

## How It Works

Write `cc:` markers anywhere in your code, save, and Claude edits the file directly.

```lua
-- cc: add error handling here
-- uu: Should I use pcall or assert?
function process(data)
  return data.value
end
```

Save → Claude reads the file → executes the instruction → removes the marker.

See [`prompt.md`](prompt.md) for the full prompt.

## Neovim-Native Operator

Use `gC` to insert cc: markers with proper comment syntax for any filetype:

| Keybinding | Action | Scope Hint | Captures Text |
|------------|--------|------------|---------------|
| `gCC` | Insert `cc:` marker above current line | `<line>` | No |
| `gC!` | Insert `cc!:` constitution marker | `<line>` | No |
| `gC?` | Insert `ccp:` plan marker | `<line>` | No |
| `gC?` (visual) | Insert plan marker with selection | `<selection>` | Yes |
| `gCip`/`gCap` | Insert marker for paragraph | `<paragraph>` | No |
| `gCiw`/`gCaw` | Insert marker for word | `<word>` | Yes |
| `gCis`/`gCas` | Insert marker for sentence | `<sentence>` | Yes |
| `gCi}`/`gCa}` | Insert marker for block | `<block>` | No |
| `gCif`/`gCaf` | Insert marker for function | `<function>` | No |
| `gC` (visual) | Insert marker with selected text | `<selection>` | Yes |

**Scope hints** tell Claude what the instruction applies to:
```lua
-- cc: <paragraph> refactor this section
-- cc: <line> add error handling
-- cc: <selection> some_variable <- rename to camelCase
```

**Example:** Select “controller configuration” and press `gC`:
```go
// cc: <selection> controller configuration <-
// Config holds the controller configuration
```

## Signs

Markers show in the gutter:
- 󰭻 (yellow) — `cc:` command / `cc!:` constitution / `ccp:` plan
- 󰞋 (blue) — `uu:` question marker

## Plan Marker (Review Before Apply)

Use `ccp:` when you want to review Claude's changes before applying them:

```lua
-- ccp: add error handling
function process(data)
  return data.value
end
```

Claude wraps changes in conflict markers:

```lua
<<<<<<< CURRENT
function process(data)
  return data.value
end
=======
function process(data)
  if not data then
    return nil, "missing data"
  end
  return data.value
end
>>>>>>> PROPOSED
```

**Accept/Reject:** Position cursor in the section you want to keep, then `:Pairup accept` (or `<Plug>(pairup-accept)`):
- Cursor in CURRENT → keep original (reject proposal)
- Cursor in PROPOSED → keep Claude's change (accept proposal)

**Mix and match:** Add `cc:` inside PROPOSED to refine before accepting:

```lua
<<<<<<< CURRENT
function process(data)
  return data.value
end
=======
-- cc: also add logging
function process(data)
  if not data then
    return nil, "missing data"
  end
  return data.value
end
>>>>>>> PROPOSED
```

Save → Claude refines the PROPOSED section → review again → accept when satisfied.

## Constitution Marker

Use `cc!:` when you want Claude to both execute an instruction AND extract the underlying rule into `CLAUDE.md`:

```lua
-- cc!: use snake_case for all variable names
local myVar = 1
```

Claude will rename `myVar` to `my_var` and add "use snake_case for variables" to your project's `CLAUDE.md`.

## Questions

When Claude needs more information, it adds `uu:` and you can continue discussion by appending `cc:` in response.

```lua
-- cc: add error handling here
-- uu: Should I use pcall or assert?
function process(data)
  return data.value
end
```

## Installation

Key bindings are optional — the plugin works with `:Pairup` commands alone. 

```lua
-- lazy.nvim
{
  "Piotr1215/pairup.nvim",
  cmd = { "Pairup" },
  keys = {
    { "<leader>cc", "<cmd>Pairup start<cr>", desc = "Start Claude" },
    { "<leader>ct", "<cmd>Pairup toggle<cr>", desc = "Toggle terminal" },
    { "<leader>cq", "<cmd>Pairup questions<cr>", desc = "Show questions" },
    { "<leader>cx", "<cmd>Pairup stop<cr>", desc = "Stop Claude" },
  },
  config = function()
    require("pairup").setup()
    -- Default works out of the box. Override only if needed:
    -- require("pairup").setup({
    --   providers = {
    --     claude = { cmd = "claude --permission-mode plan" },
    --   },
    -- })
  end,
}
```

## Commands

`:Pairup <subcommand>`

| Command | Description |
|---------|-------------|
| `start` | Start Claude (hidden terminal) |
| `stop` | Stop Claude |
| `toggle` | Show/hide terminal |
| `say <msg>` | Send message to Claude |
| `questions` | Show `uu:` in quickfix |
| `inline` | Manual cc: trigger |
| `diff` | Send git diff to Claude |
| `lsp` | Send LSP diagnostics to Claude |
| `suspend` | Pause auto-processing (indicator turns red) |
| `accept` | Accept conflict section at cursor |

## Status Indicator

Automatically injected into lualine (or native statusline if no lualine). No config needed.

- `[C]` — Claude running
- `[C:pending]` — Waiting for Claude
- `[C:██░░░░░░░░]` — Progress bar
- `[C:ready]` — Task complete

**Manual setup** (only if you disable auto-inject or use a custom statusline plugin):
```lua
-- Disable auto-inject
require("pairup").setup({ statusline = { auto_inject = false } })

-- Add to native statusline manually
vim.o.statusline = '%f %m%=%{g:pairup_indicator} %l:%c'
```

## Configuration

**Default:** The `--permission-mode acceptEdits` flag is included by default. This allows Claude to edit files without prompting for confirmation on each change, which is required for the inline editing workflow to function smoothly.

All settings below are defaults. You only need to include values you want to change:

```lua
require("pairup").setup({
  provider = "claude",
  providers = {
    claude = {
      -- Full command with flags (default includes acceptEdits)
      cmd = "claude --permission-mode acceptEdits",
    },
  },
  terminal = {
    split_position = "left",
    split_width = 0.4,
    auto_insert = false, -- Enter insert mode when opening terminal
  },
  auto_refresh = {
    enabled = true,
    interval_ms = 500,
  },
  inline = {
    markers = {
      command = "cc:",
      question = "uu:",
      constitution = "cc!:",
      plan = "ccp:",
    },
    quickfix = true,
  },
  statusline = {
    auto_inject = true, -- auto-inject into lualine/native statusline
  },
  -- Progress bar (optional, disabled by default)
  -- NOTE: When enabled, YOU must grant Claude write access to the progress file directory.
  -- Add to your claude command: --add-dir /tmp (or your custom path)
  progress = {
    enabled = false,
    file = "/tmp/claude_progress", -- Default path, change if needed
  },
  flash = {
    scroll_to_changes = false, -- Auto-scroll to first changed line
  },
  operator = {
    key = "gC", -- change to override default
  },
})
```

### Highlight Groups

Customizable highlight groups (respects light/dark background by default):

```lua
-- In your colorscheme or after/plugin/colors.lua:
vim.api.nvim_set_hl(0, 'PairupMarkerCC', { bg = '#your_color' }) -- cc: marker line
vim.api.nvim_set_hl(0, 'PairupMarkerUU', { bg = '#your_color' }) -- uu: marker line
vim.api.nvim_set_hl(0, 'PairupFlash', { bg = '#your_color' })    -- changed lines flash
```

### Plug Mappings

Available `<Plug>` mappings for custom keybindings:

```lua
vim.keymap.set('n', '<leader>cc', '<Plug>(pairup-toggle-session)')  -- start/stop
vim.keymap.set('n', '<leader>ct', '<Plug>(pairup-toggle)')          -- show/hide terminal
vim.keymap.set('n', '<leader>cs', '<Plug>(pairup-suspend)')         -- pause auto-processing
vim.keymap.set('n', '<leader>cl', '<Plug>(pairup-lsp)')             -- send LSP diagnostics
vim.keymap.set('n', '<leader>cd', '<Plug>(pairup-diff)')            -- send git diff
vim.keymap.set('n', '<leader>cq', '<Plug>(pairup-questions)')       -- show uu: in quickfix
vim.keymap.set('n', '<leader>ci', '<Plug>(pairup-inline)')          -- process cc: markers
vim.keymap.set('n', ']C', '<Plug>(pairup-next-marker)')             -- next marker
vim.keymap.set('n', '[C', '<Plug>(pairup-prev-marker)')             -- prev marker
vim.keymap.set('n', '<leader>co', '<Plug>(pairup-accept)')          -- accept conflict at cursor
```

## Requirements

- Neovim 0.11+ 
- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code)

## License

MIT
