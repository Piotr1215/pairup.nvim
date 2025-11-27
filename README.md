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

Save → Claude reads the file, executes the instruction, removes the marker.

## Neovim-Native Operator

Use `gC` to insert cc: markers with proper comment syntax for any filetype:

| Keybinding | Action |
|------------|--------|
| `gC{motion}` | Insert marker above motion (e.g., `gCip` for paragraph) |
| `gCC` | Insert marker above current line |
| `gC` (visual) | Insert marker with selected text as context |

**Example:** Select "controller configuration" and press `gC`:
```go
// cc: controller configuration
// Config holds the controller configuration
```
Cursor positions after `cc:` for typing your instruction.

## Signs

Markers show in the gutter:
- 󰭻 (yellow) — `cc:` command marker
- 󰞋 (blue) — `uu:` question marker

## Questions

If Claude needs clarification, it adds `uu:`:

```lua
-- cc: add error handling here
-- uu: Should I use pcall or assert?
function process(data)
  return data.value
end
```

Respond with `cc:` after `uu:`, then save.

## Installation

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
| `diff` | Toggle git diff sending |
| `lsp` | Toggle LSP integration |

## Status Indicator

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
vim.keymap.set('n', '<leader>cc', '<Plug>(pairup-start)')
vim.keymap.set('n', '<leader>cx', '<Plug>(pairup-stop)')
vim.keymap.set('n', '<leader>ct', '<Plug>(pairup-toggle)')
vim.keymap.set('n', '<leader>cq', '<Plug>(pairup-questions)')
vim.keymap.set('n', '<leader>ci', '<Plug>(pairup-inline)')
```

## Requirements

- Neovim 0.9+
- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code)

## License

MIT
