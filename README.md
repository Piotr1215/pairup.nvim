# pairup.nvim

Inline AI pair programming for Neovim using Claude Code.

> 🔺 **Breaking Changes in v4.0** 🔺
>
> This version removes the overlay system, sessions, RPC, and marker-based suggestions
> to focus on one thing: simple inline editing with `cc:`/`uu:` markers.
>
> **Why?** Less complexity, more reliability. Claude edits files directly - no parsing,
> no overlays, no state management. Just write `cc:`, save, and Claude handles it.
>
> **Need the old features?** Use `git checkout legacy-v3` or `git checkout v3.0.0`

## How It Works

Write `cc:` markers anywhere in your code, save, and Claude edits the file directly.

```lua
-- cc: add error handling here
function process(data)
  return data.value
end
```

Save → Claude reads the file, executes the instruction, removes the marker.

If Claude needs clarification, it adds `uu:`:

```lua
-- uu: Should I use pcall or assert?
-- cc: add error handling here
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

- `[C]` - Claude running
- `[C:pending]` - Waiting for Claude
- `[C:queued]` - Save queued

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
})
```

## Requirements

- Neovim 0.9+
- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code)

## License

MIT
