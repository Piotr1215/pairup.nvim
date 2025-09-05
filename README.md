# pairup.nvim

**🤖 Real-time AI pair programming with intelligent context awareness for Neovim.**

`pairup.nvim` transforms your Neovim into an AI-powered pair programming environment with real-time git diff streaming, intelligent code awareness, and seamless workflow integration.

> Pair programming is a software development technique in which two programmers work together at one workstation. One, the driver, **writes code** while the other, the observer or navigator, **reviews each line of code as it is typed in**. The two programmers switch roles frequently.
<p style="text-align: center;"><small>Wikipedia pair programming</small></p>

![demo](./static/demo.png) 

<div align="center">

[![CI](https://img.shields.io/github/actions/workflow/status/Piotr1215/pairup.nvim/.github%2Fworkflows%2Fci.yml)](https://github.com/Piotr1215/pairup.nvim/actions/workflows/ci.yml)
[![Neovim](https://img.shields.io/badge/Neovim-0.8+-green.svg?style=flat-square&logo=neovim)](https://neovim.io)
[![Lua](https://img.shields.io/badge/Lua-5.1+-blue.svg?style=flat-square&logo=lua)](https://www.lua.org)
[![License](https://img.shields.io/badge/License-MIT-yellow.svg?style=flat-square)](LICENSE)

</div>

## Quick Examples

```vim
:PairupStart          " Start AI pair programmer in split window
:PairupContext        " Send current file's diff to AI
:PairupStatus         " Send git status and recent commits
:PairupSay Fix this   " Direct message to AI
<leader>ct            " Toggle AI window visibility
```

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "Piotr1215/pairup.nvim",
  config = function()
    require("pairup").setup({
      provider = "claude",  -- Currently supports 'claude', future: 'openai', 'ollama'
    })
  end,
}
```

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  "Piotr1215/pairup.nvim",
  config = function()
    require("pairup").setup({
      provider = "claude",
    })
  end,
}
```

**Note:** The plugin requires explicit setup to configure AI providers and keybindings. Currently Claude is supported with OpenAI and Ollama support planned.

## Features

- **Real-time Git Diff Streaming** - Automatically sends unstaged changes as you save
- **Smart Batching** - Groups multiple saves within 1.5s to reduce noise
- **Staged/Unstaged Workflow** - Once you stage changes, they disappear from updates
- **Critical Notifications** - AI can alert you via `notify-send` for important issues
- **Auto-reload Buffers** - Files automatically refresh when AI makes edits
- **Workspace Awareness** - Shows current file diff with info about other changes
- **Provider Abstraction** - Designed for multiple AI providers (Claude, OpenAI, Ollama) *(roadmap)*
- **Intelligent Context** - Uses git staging area to track work progress
- **Periodic Updates** - Optional automatic status updates at intervals
- **Shell/Vim Command Integration** - Send command outputs directly to AI

## Usage

### How it Works

1. Start AI with `:PairupStart` - opens in vertical split
2. Make changes - AI sees unstaged diffs as you save
3. Stage completed work with `git add` - removes from AI updates
4. Continue working - AI only sees new unstaged changes

### Basic Commands

| Command | Description |
|---------|-------------|
| `:PairupStart` | Start AI in vertical split (40% width) |
| `:PairupToggle` | Toggle AI window visibility |
| `:PairupContext` | Manually send current file's diff |
| `:PairupStatus` | Send git status, branch, and commits |
| `:PairupSay [text]` | Send a message to AI |
| `:PairupSay ![cmd]` | Execute shell command and send output |
| `:PairupSay :[cmd]` | Execute vim command and send output |
| `:PairupStartUpdates [min]` | Start periodic updates (default 10 min) |
| `:PairupStopUpdates` | Stop periodic updates |
| `:PairupToggleGitDiffSend` | Pause/resume automatic diff sending |

### Keybindings

Default keybindings (customizable in setup):

| Keys | Description |
|------|-------------|
| `<leader>ct` | Toggle AI window |
| `<leader>cc` | Send context manually |
| `<leader>cs` | Send git status |
| `<leader>cm` | Send message to AI |

### The Staged/Unstaged Philosophy

This integration uses git's staging area intelligently:

- **Unstaged changes** = Work in progress (sent to AI)
- **Staged changes** = Completed work (hidden from updates)

This prevents repetitive large diffs - once you stage a refactor, AI only sees new changes on top.

### AI Provider Capabilities

#### Claude (Current)
- Receives only unstaged changes in real-time
- Can fix issues in code you just modified
- Uses `notify-send` for critical alerts
- Can run git commands to understand repository
- Helps with selective staging (`git add -p`)
- Auto-accepts edits with permission mode

#### OpenAI (Planned)
- GPT-4 integration with streaming responses
- Function calling for structured operations
- Vision capabilities for screenshots

#### Ollama (Planned)
- Local LLM support for privacy
- Multiple model selection
- Custom model configurations

## Configuration

> **Note**: The source of truth for all configuration options is [`lua/pairup/config.lua`](lua/pairup/config.lua). The examples below show the default values.

### Default Setup

```lua
require('pairup').setup({
  -- Provider selection
  provider = "claude",              -- 'claude', 'openai' (future), 'ollama' (future)
  
  -- Window settings
  split_cmd = "vsplit",            -- Split command for AI window
  split_width = 0.4,               -- Width as percentage (0.4 = 40%)
  
  -- Git integration
  batch_delay_ms = 1500,           -- Delay for batching multiple saves
  context_lines = 10,              -- Lines of context in diffs
  ignore_patterns = {              -- Patterns to ignore in diffs
    "%.git/",
    "%.svg$",
    "%.png$",
    "%.jpg$",
    "%.jpeg$",
    "%.gif$",
    "%.ico$",
    "package%-lock%.json$",
    "yarn%.lock$",
  },
  
  -- Behavior
  enable_default_keymaps = true,   -- Use default keybindings
  auto_reload_delay_ms = 500,      -- Check for external changes interval
  update_time_ms = 1000,           -- Update frequency for git checks
  git_diff_enabled_on_start = true,-- Auto-start diff streaming
  
  -- Keymaps (when enable_default_keymaps = true)
  keymaps = {
    toggle = "<leader>ct",
    send_context = "<leader>cc",
    send_status = "<leader>cs",
    send_message = "<leader>cm",
  },
})
```

### Provider-Specific Configuration

```lua
require('pairup').setup({
  provider = "claude",
  
  -- Provider configurations
  providers = {
    claude = {
      path = vim.fn.exepath('claude'),      -- Path to claude CLI
      permission_mode = "acceptEdits",       -- Auto-accept edits
      add_dir_on_start = true,              -- Auto-add project directory
      extra_args = {},                      -- Additional CLI arguments
    },
    openai = {                              -- Future
      api_key = os.getenv("OPENAI_API_KEY"),
      model = "gpt-4",
      temperature = 0.7,
    },
    ollama = {                              -- Future
      host = "http://localhost:11434",
      model = "llama2",
      context_window = 4096,
    },
  },
})
```

### Advanced Configuration

```lua
require('pairup').setup({
  -- Core settings
  provider = "claude",
  
  -- Custom keybindings
  enable_default_keymaps = false,   -- Disable defaults
  keymaps = {
    toggle = "<C-a>",               -- Custom toggle key
    send_context = "<C-c>",         -- Custom context key
    -- Leave others undefined
  },
  
  -- Performance tuning
  batch_delay_ms = 2000,            -- Longer batching window
  update_time_ms = 2000,            -- Less frequent updates
  auto_reload_delay_ms = 1000,      -- Slower reload checks
  
  -- Git workflow
  git_diff_enabled_on_start = false,-- Manual diff control
  context_lines = 20,               -- More context in diffs
  
  -- Custom ignore patterns
  ignore_patterns = {
    "%.git/",
    "node_modules/",
    "dist/",
    "build/",
    "%.test%.js$",
    "%.spec%.ts$",
  },
  
  -- Provider settings
  providers = {
    claude = {
      path = "/usr/local/bin/claude",
      permission_mode = "ask",      -- Ask before edits
      add_dir_on_start = false,     -- Manual directory control
      extra_args = { "--verbose" },
    },
  },
})
```

### Statusline Integration

Add AI status indicator to your statusline:

```lua
-- Lualine
sections = {
  lualine_x = {
    function()
      local pairup = require('pairup.utils.indicator')
      return pairup and pairup.get() or ''
    end
  }
}

-- Native statusline
vim.opt.statusline:append('%{luaeval("require(\'pairup.utils.indicator\').get()")}')
```

## Integration with Other Tools

### Git Integration

The plugin deeply integrates with git:

```vim
" AI sees unstaged changes automatically
:w                      " Save file → AI sees diff

" Stage completed work (removes from AI view)
:!git add file.lua      " Stage → AI no longer sees

" Selective staging with AI help
:PairupSay !git diff --cached   " Show AI what's staged
:!git add -p            " AI can guide selective staging
```

### Shell Command Integration

```vim
" Send command output to AI
:PairupSay !npm test           " Test results
:PairupSay !git log --oneline  " Recent commits
:PairupSay !rg "TODO"          " Search results
```

### Vim Command Integration

```vim
" Send vim info to AI
:PairupSay :registers          " Register contents
:PairupSay :messages           " Recent messages
:PairupSay :ls                 " Buffer list
```

## Troubleshooting

### Quick health check
Run `:checkhealth pairup` to diagnose common issues.

### AI not starting?
- Check if claude CLI is installed: `:echo executable('claude')`
- Verify path in config: `:lua print(require('pairup.config').get().providers.claude.path)`
- Check `:messages` for errors

### Diffs not streaming?
- Ensure you're in a git repository: `:!git status`
- Check if diff sending is enabled: `:lua print(require('pairup.config').get().git_diff_enabled)`
- Verify file isn't ignored: Check `ignore_patterns` in config

### Commands not working?
- Ensure plugin is loaded: `:lua print(vim.g.loaded_pairup)`
- Check keybindings: `:verbose nmap <leader>ct`
- Verify setup was called: Check your plugin configuration

## Why This is Better Than Cursor

- **True pair programming** - AI watches actual git diffs, not just cursor position
- **Respects your workflow** - Uses YOUR editor, YOUR keybindings
- **Smart notifications** - Only alerts for critical issues
- **Git-aware** - Understands staged vs unstaged changes
- **Multi-provider ready** - Not locked to one AI service
- **Open source** - Customize and extend as needed

## Requirements

- Neovim 0.8+
- Git repository for diff tracking
- AI provider CLI (currently Claude)
- `notify-send` for system notifications (optional)

## License

MIT

---

<div align="center">

[Report Bug](https://github.com/Piotr1215/pairup.nvim/issues) · [Request Feature](https://github.com/Piotr1215/pairup.nvim/issues)

</div>
