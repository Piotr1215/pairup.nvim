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
> **Need the old features?** Use `git checkout legacy-v3` or `git checkout v3.0.0`

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
The prompt sent to Claude on each save (from `lua/pairup/inline.lua`):

```lua
File: {filepath}

This file contains inline instructions marked with `cc:`.

RULES:
1. Read the file and find all `cc:` markers
2. Execute the instruction at each marker location
3. Remove the `cc:` line after completing each instruction
4. If you need clarification, add `uu: <your question>` on a NEW line right after the `cc:` line, then STOP and wait
5. When you see `uu:` followed by `cc:` answer, act on it and remove BOTH lines
6. Use the Edit tool to modify the file directly
7. NEVER respond in the terminal - ALL communication goes in the file as `uu:` comments
8. Preserve all other code exactly as is

SCOPE HINTS: Markers may include scope hints like `<line>`, `<paragraph>`, `<word>`, `<sentence>`, `<block>`, `<function>`, or `<selection>`.
These indicate what the instruction applies to:
- `<line>` - apply to the line immediately below
- `<paragraph>` - apply to the paragraph below
- `<word>` or `<sentence>` - the captured text follows the hint (e.g., `cc: <word> myVar <- rename`)
- `<selection>` - the captured text follows the hint
- `<block>` or `<function>` - apply to the code block/function below

PROGRESS: ALWAYS run before starting: echo "30:task description" > /tmp/claude_progress
ALWAYS run when finished: echo "done" > /tmp/claude_progress
```

## Neovim-Native Operator

Use `gC` to insert cc: markers with proper comment syntax for any filetype:

| Keybinding | Action | Scope Hint | Captures Text |
|------------|--------|------------|---------------|
| `gCC` | Insert marker above current line | `<line>` | No |
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

**Example:** Select "controller configuration" and press `gC`:
```go
// cc: <selection> controller configuration <-
// Config holds the controller configuration
```

## Signs

Markers show in the gutter:
- 󰭻 (yellow) — `cc:` command marker
- 󰞋 (blue) — `uu:` question marker

## Questions

If Claude needs clarification, it adds `uu:` and you can continue discussion by appending `cc:` in response.

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
    require("pairup").setup({
      providers = {
        claude = {
          path = "claude", -- or your custom path
        },
      },
    })
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

## Status Indicator

The status indicator is updated by Claude via the prompt — Claude writes progress to `/tmp/claude_progress`.

```lua
-- Lualine
{ function() return vim.g.pairup_indicator or '' end }
```

- `[C]` — Claude running
- `[C:pending]` — Waiting for Claude
- `[C:queued]` — Save queued
- `[C:██░░░░░░░░]` — Progress bar (Claude signals estimated duration)
- `[C:ready]` — Task complete

## Configuration

```lua
require("pairup").setup({
  provider = "claude",
  providers = {
    claude = { path = "claude" },
  },
  terminal = {
    split_position = "left",
    split_width = 0.4,
  },
  auto_refresh = {
    enabled = true,
    interval_ms = 500,
  },
  inline = {
    enabled = true,
    markers = {
      command = "cc:",
      question = "uu:",
    },
    quickfix = true,
  },
  operator = {
    key = "gC", -- change to override default
  },
})
```

## Plug Mappings

Available `<Plug>` mappings for custom keybindings:

```lua
vim.keymap.set('n', '<leader>cc', '<Plug>(pairup-toggle-session)')  -- start/stop
vim.keymap.set('n', '<leader>ct', '<Plug>(pairup-toggle)')          -- show/hide terminal
vim.keymap.set('n', '<leader>cl', '<Plug>(pairup-lsp)')             -- send LSP diagnostics
vim.keymap.set('n', '<leader>cd', '<Plug>(pairup-diff)')            -- send git diff
vim.keymap.set('n', '<leader>cq', '<Plug>(pairup-questions)')       -- show uu: in quickfix
vim.keymap.set('n', '<leader>ci', '<Plug>(pairup-inline)')          -- process cc: markers
vim.keymap.set('n', ']C', '<Plug>(pairup-next-marker)')             -- next marker
vim.keymap.set('n', '[C', '<Plug>(pairup-prev-marker)')             -- prev marker
```

## Requirements

- Neovim 0.9+
- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code)

## License

MIT
