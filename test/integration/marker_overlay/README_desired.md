# 🚀 pairup.nvim
<div align="center">
![GitHub Stars](https://img.shields.io/github/stars/Piotr1215/pairup.nvim?style=for-the-badge)
![Neovim](https://img.shields.io/badge/Neovim-0.8+-green.svg?style=for-the-badge&logo=neovim)
![License](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)
### 🤖 AI-Powered Pair Programming for Neovim
**Transform your coding workflow with intelligent, context-aware AI assistance**
```
┌────────────────────────────────────────────────────────────┐
│  👨‍💻 You write code  ──▶  🔄 Git tracks changes  ──▶  🤖 AI assists  │
└────────────────────────────────────────────────────────────┘
```
</div>
## ✨ Highlights
- 🔥 **Real-time collaboration** - AI sees your changes as you work
- 🎯 **Smart context control** - Use git staging to manage what AI sees
- 💡 **Overlay suggestions** - Review AI edits before accepting
- 🔌 **Provider agnostic** - Built for extensibility
- 🚀 **Zero config** - Works out of the box with sensible defaults
## 📚 Quick Links
| Documentation | Community | Development |
|--------------|-----------|-------------|
| [📖 User Guide](#getting-started) | [💬 Discussions](https://github.com/Piotr1215/pairup.nvim/discussions) | [🐛 Issue Tracker](https://github.com/Piotr1215/pairup.nvim/issues) |
| [⚙️ Configuration](#configuration) | [🌟 Show & Tell](https://github.com/Piotr1215/pairup.nvim/discussions/categories/show-and-tell) | [🔀 Pull Requests](https://github.com/Piotr1215/pairup.nvim/pulls) |
| [🔧 Troubleshooting](#troubleshooting) | [❓ Q&A](https://github.com/Piotr1215/pairup.nvim/discussions/categories/q-a) | [📝 Changelog](CHANGELOG.md) |
---
### ⚡ Latest Updates (v2.0)
<details>
<summary>Click to expand changelog</summary>
#### 🎨 Enhanced Overlay Engine
- Completely redesigned for better performance
- Improved multi-line handling
- Better extmark tracking
#### 🔧 New Insert Methods
- `insert_above` and `insert_below` for precise suggestions
- Smart indentation handling
- Preserve existing code structure
#### 🔄 Multi-variant Suggestions
- Multiple alternatives from AI
- Cycle with Tab/Shift+Tab
- Accept best variant instantly
</details>

⚠️ Warning /s
- pairup.nvim will make you useless. Claude will take over your code, your tests, your editor… and your life.
- your IQ will plummet, your job will vanish, and soon you’ll be drooling at the screen while AI zips through the tasks.
- hope you’ve got a few spare organs to sell — you’ll need them to pay rent in the post labor economics.

> Pair programming is a software development technique in which two programmers
> work together at one workstation. One, the driver, **writes code** while the
> other, the observer or navigator, **reviews each line of code as it is typed
> in**. The two programmers switch roles frequently.

<p align="center"><small>Wikipedia pair programming</small></p>

![demo](./static/demo.png)

<div align="center">

[![CI](https://img.shields.io/github/actions/workflow/status/Piotr1215/pairup.nvim/.github%2Fworkflows%2Fci.yml)](https://github.com/Piotr1215/pairup.nvim/actions/workflows/ci.yml)
[![Neovim](https://img.shields.io/badge/Neovim-0.8+-green.svg?style=flat-square&logo=neovim)](https://neovim.io)
[![Lua](https://img.shields.io/badge/Lua-5.1+-blue.svg?style=flat-square&logo=lua)](https://www.lua.org)
[![License](https://img.shields.io/badge/License-MIT-yellow.svg?style=flat-square)](LICENSE)
## 🚀 [What's New in v2.0](CHANGELOG.md) - Enhanced overlays, multi-variants, persistence & more!
- **Insert Methods**: New `insert_above` and `insert_below` methods for more precise code suggestions
- **Multi-variant Suggestions**: AI can now provide multiple alternatives that you can cycle through with Tab/Shift+Tab
- **Improved Extmark Tracking**: More robust position tracking that survives file edits
- **Overlay Persistence**: Save and restore overlay suggestions across sessions

## Why pairup.nvim?

- Brings pair programming principles to AI-assisted coding - the AI observes changes as you work
- Uses existing CLI tools (Claude CLI) integrated through terminal buffers and optional RPC
- Combines two AI paradigms: agentic (autonomous) and completion-based assistance
- Git staging area controls what context is sent - staged changes are hidden, unstaged are visible
- Designed to support multiple AI providers (currently Claude, more planned)
- Purpose-built for Neovim (not a generic editor plugin)

## Getting Started

1. Start AI with `:PairupStart` - opens in vertical split
2. Make changes - AI sees unstaged diffs as you save
3. Stage completed work with `git add` - removes from AI updates
4. Continue working - AI only sees new unstaged changes

When working with the AI you can use various commands, here are some examples. See the [full commands list](#all-available-commands) below.

```vim
" Start AI and describe your task
:PairupStart
:PairupIntent I want to refactor the authentication module

" Send specific context
:PairupSay !git log --oneline -10       " Send last 10 commits
:PairupSay :LSPInfo                     " Send LSP server info
:PairupSay Can you help me optimize this function?

" Control what AI sees
:PairupToggleDiff                       " Pause automatic diff updates
" ... make many changes ...
:PairupToggleDiff                       " Resume diff updates
:PairupContext                          " Manually send accumulated changes

" Resume previous work
:PairupResume                           " Shows list of previous sessions to continue
```

### Getting started with RPC

1. Start Neovim with RPC enabled:
   ```bash
   nvim --listen 127.0.0.1:6666
   ```

2. Configure the plugin with your desired settings (see complete configuration below)


## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "Piotr1215/pairup.nvim",
  config = function()
## 📦 Installation
### Prerequisites
Ensure you have:
- Neovim 0.8+ (check with `nvim --version`)
- Git installed and configured
- Claude CLI or other AI provider
### Package Managers
<details>
<summary><b>lazy.nvim</b> (recommended)</summary>
```lua
{
  "Piotr1215/pairup.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",  -- Required for testing
  },
  config = function()
    require("pairup").setup({
      -- Your configuration here
    })
  end,
  keys = {
    { "<leader>cs", "<cmd>PairupStart<cr>", desc = "Start AI pair" },
    { "<leader>ct", "<cmd>PairupToggle<cr>", desc = "Toggle AI" },
  },
}
```
</details>
<details>
<summary><b>packer.nvim</b></summary>
```lua
use {
  "Piotr1215/pairup.nvim",
  requires = { "nvim-lua/plenary.nvim" },
  config = function()
    require("pairup").setup({})
  end
}
```
</details>
<details>
<summary><b>vim-plug</b></summary>
```vim
Plug 'nvim-lua/plenary.nvim'
Plug 'Piotr1215/pairup.nvim'
" After plug#end()
lua require('pairup').setup({})
```
</details>
<details>
<summary><b>Manual Installation</b></summary>
```bash
# Clone to your runtime path
git clone https://github.com/Piotr1215/pairup.nvim \
  ~/.local/share/nvim/site/pack/pairup/start/pairup.nvim
# In your init.lua
require('pairup').setup({})
```
</details>
### Post-Installation
1. Run `:checkhealth pairup` to verify installation
2. Install Claude CLI: `npm install -g @anthropic-ai/claude-cli`
3. Configure your AI provider credentials
4. Start pairing with `:PairupStart`!
    })
  end,
}
```

Run `:checkhealth pairup` to verify installation.

## Features

- **Real-time Git Diff Streaming** - Automatically sends unstaged changes as you save
- **Virtual Text Overlays** - Review code suggestions before accepting them
- **Neovim RPC Control** - AI can directly control your Neovim instance via RPC
- **Smart Batching** - Groups multiple saves within 1.5s to reduce noise
- **Staged/Unstaged Workflow** - Stage completed work to hide it from AI updates
- **Auto-reload Buffers** - Files automatically refresh when AI makes edits
- **Workspace Awareness** - Shows current file diff with info about other changes
- **Provider Abstraction** - Extensible provider architecture
- **Session Persistence** - Resume previous work sessions
- **Shell/Vim Command Integration** - Send command outputs directly to AI

## Neovim RPC Control

```bash
:help rpc
```

> RPC is the main way to control Nvim programmatically. Nvim implements the
> MessagePack-RPC protocol with these extra (out-of-spec) constraints:

> 1. Responses must be given in reverse order of requests (like "unwinding a
>    stack").
> 2. Nvim processes all messages (requests and notifications) in the order they
>    are received.

This enables the following scenarios.

1. Local instances with different ports - you could have multiple nvim
   instances:

- nvim --listen 127.0.0.1:6666 → RPC enabled
- nvim --listen 127.0.0.1:7777 → RPC disabled (wrong port)
- nvim → RPC disabled (no TCP server)

2. Remote servers - if you start nvim on a remote machine:

- nvim --listen 0.0.0.0:6666 (listens on all interfaces)
- nvim --listen <remote-ip>:6666
- The servername would show the actual bind address, and our detection would
  work

3. Network scenarios:

- SSH tunneling: ssh -L 6666:localhost:6666 remote-host then connect to the
  remote nvim
- Docker containers: nvim --listen 0.0.0.0:6666 inside container
- WSL/VMs: Same TCP detection works across boundaries

## Overlay Feature (Virtual Text Suggestions) [EXPERIMENTAL]

⚠️ **Note: This feature is experimental and unstable. It may have bugs or unexpected behavior.**

Claude can suggest code changes using overlays - virtual text that shows proposed modifications without immediately changing your files. This allows you to review suggestions before accepting them.

### How Overlays Work

### Overlay Persistence

Save and restore overlay suggestions across sessions to preserve your workflow:

```vim
" Save current overlays to a timestamped file
:PairupOverlaySave [file]     " or :PairSave

" Restore overlays (shows picker if no file specified)
:PairupOverlayRestore [file]  " or :PairRestore

" List all saved overlay sessions
:PairupOverlayList
```

**Storage Details:**
- Overlays are saved as JSON files in `~/.local/share/nvim/pairup/overlays/`
- Each save includes file content hash to detect changes since save
- Files are named with timestamps for easy identification

**Auto-save Use Cases:**
- Enable auto-save when working on complex refactoring to preserve suggestions
- Useful for code reviews where you want to save suggestions for later
- Configure with `overlay_persistence.auto_save = true` to save on buffer write/unload

" Restore overlays (shows picker if no file specified)
:PairupOverlayRestore [file]  " or :PairRestore

" List all saved overlay sessions
:PairupOverlayList
```

Overlays are saved as JSON with file content and suggestions. File hash checking detects if the file changed since save. Auto-save can be configured to save on buffer write/unload.

For remote network scenarios claude can run either locally in neovim buffer and
operate on remote neovim instance or run in remote server and operate on the
local buffer.

> [!NOTE]
> Complimentary to this setup a
> [nvim MCP server](https://github.com/calebfroese/mcpserver.nvim) can be used

### RPC Helper Methods

When RPC is enabled, Claude can use these helper functions:

## ⚙️ Configuration
### 🎯 Quick Start
```lua
-- Minimal setup with defaults
require('pairup').setup({})
-- Or with common options
require('pairup').setup({
  provider = 'claude',
  terminal = {
    split_position = 'left',
    split_width = 0.4,
  },
  overlay = {
    inject_instructions = true,
  },
})
```
### 📋 Complete Configuration Reference
<details>
<summary><b>Core Settings</b></summary>
```lua
{
  -- Provider selection
  provider = 'claude',  -- 'claude' | 'openai' (future) | 'ollama' (future)
  
  -- Session management
  sessions = {
    persist = true,
    auto_populate_intent = true,
    intent_template = "Working on `%s` to...",
  },
}
```
</details>
<details>
<summary><b>Provider Configuration</b></summary>
```lua
{
  providers = {
    claude = {
      path = vim.fn.exepath('claude'),
      permission_mode = 'plan',  -- 'plan' | 'acceptEdits'
      add_dir_on_start = true,
      default_args = {},
    },
    -- Future providers
    openai = { api_key = "sk-..." },
    ollama = { host = "localhost:11434" },
  },
}
```
</details>
<details>
<summary><b>Git Integration</b></summary>
```lua
{
  git = {
    enabled = true,
    diff_context_lines = 10,
    fyi_suffix = "\\nGit diff received...",
  },
}
```
</details>
<details>
<summary><b>Terminal Settings</b></summary>
```lua
{
  terminal = {
    split_position = 'left',  -- 'left' | 'right'
    split_width = 0.4,         -- 40% for AI
    auto_insert = true,
    auto_scroll = true,
  },
}
```
</details>
<details>
<summary><b>Overlay System</b></summary>
```lua
{
  overlay = {
    inject_instructions = true,
    instructions_path = nil,  -- Custom instructions
    persistence = {
      enabled = true,
      auto_save = true,
      auto_restore = true,
      max_sessions = 10,
    },
  },
}
```
</details>
<details>
<summary><b>Performance & Filtering</b></summary>
```lua
{
  filter = {
    ignore_whitespace_only = true,
    min_change_lines = 0,
    batch_delay_ms = 500,
  },
  auto_refresh = {
    enabled = true,
    interval_ms = 500,
  },
  periodic_updates = {
    enabled = false,
    interval_minutes = 10,
  },
}
```
</details>
### 🎨 Commands & Keybindings
<details>
<summary><b>Available Commands</b></summary>
| Command | Description | Default Key |
|---------|-------------|-------------|
| `:PairupStart` | Start AI assistant | `<leader>cs` |
| `:PairupToggle` | Toggle AI window | `<leader>ct` |
| `:PairupStop` | Stop AI completely | - |
| `:PairupContext` | Send git diff | `<leader>cc` |
| `:PairupSay` | Send message | `<leader>cm` |
| `:PairMarkerToOverlay` | Convert markers | - |
| `:PairAccept` | Accept overlay | `<leader>sa` |
| `:PairAcceptAll` | Accept all overlays | - |
| `:PairReject` | Reject overlay | `<leader>sr` |
| `:PairNext` | Next overlay | `<leader>sn` |
| `:PairPrev` | Previous overlay | `<leader>sp` |
</details>
<details>
<summary><b>Custom Keybindings</b></summary>
```lua
-- Add to your config
vim.keymap.set('n', '<leader>ai', ':PairupStart<cr>', { desc = 'Start AI' })
vim.keymap.set('n', '<leader>ad', ':PairupContext<cr>', { desc = 'Send diff' })
vim.keymap.set('n', '<Tab>', ':PairupOverlayCycle<cr>', { desc = 'Cycle variants' })
vim.keymap.set('n', '<S-Tab>', ':PairupOverlayCyclePrev<cr>', { desc = 'Cycle back' })
```
</details>
    split_width = 0.4,                                            -- 40% for AI, 60% for editor
    auto_insert = true,                                           -- Auto-enter insert mode in terminal
    auto_scroll = true,                                           -- Auto-scroll to bottom on new output
  },

  -- Filtering Settings
  filter = {
    ignore_whitespace_only = true,                                -- Ignore whitespace-only changes
    ignore_comment_only = false,                                  -- Don"t ignore comment-only changes
    min_change_lines = 0,                                         -- Minimum lines changed to trigger update
    batch_delay_ms = 500,                                         -- Delay for batching multiple saves
  },

  -- Context Update Settings
  fyi_suffix = "\nYou have received a git diff...",               -- Message appended to context updates

  -- LSP Integration
  lsp = {
    enabled = true,                                               -- Enable LSP integration
    include_diagnostics = true,                                   -- Include LSP diagnostics in context
    include_hover_info = true,                                    -- Include hover information
    include_references = true,                                    -- Include reference information
  },

  -- Auto-refresh Settings
  auto_refresh = {
    enabled = true,                                               -- Auto-refresh on external changes
    interval_ms = 500,                                            -- Check interval in milliseconds
  },

  -- Periodic Updates
  periodic_updates = {
    enabled = false,                                              -- Send periodic status updates
    interval_minutes = 10,                                        -- Update interval in minutes
  },

  -- Overlay Persistence Settings
  overlay_persistence = {
    enabled = false,                                              -- Enable overlay persistence features
    auto_save = false,                                            -- Auto-save overlays on buffer write/unload
    auto_restore = false,                                         -- Auto-restore overlays when opening files
    max_sessions = 10,                                            -- Maximum saved sessions to keep per file
  },
})
```

### Keymaps

The plugin doesn't set default keymaps. They can be easily added like so:

```lua
-- Recommended keymaps
vim.keymap.set('n', '<leader>ct', ':PairupToggle<cr>', { desc = 'Toggle AI assistant' })
vim.keymap.set('n', '<leader>cc', ':PairupContext<cr>', { desc = 'Send context to AI' })
vim.keymap.set('n', '<leader>cs', ':PairupStatus<cr>', { desc = 'Send git status to AI' })
vim.keymap.set('n', '<leader>cm', ':PairupSay ', { desc = 'Send message to AI' })

-- Overlay keymaps
vim.keymap.set("n", "<leader>sa", "<cmd>PairAccept<cr>", { desc = "Accept overlay suggestion" })
vim.keymap.set("n", "<leader>sr", "<cmd>PairReject<cr>", { desc = "Reject overlay suggestion" })
vim.keymap.set("n", "<leader>sn", "<cmd>PairNext<cr>", { desc = "Next overlay suggestion" })
vim.keymap.set("n", "<leader>sp", "<cmd>PairPrev<cr>", { desc = "Previous overlay suggestion" })
vim.keymap.set("n", "<Tab>", "<cmd>PairupOverlayCycle<cr>", { desc = "Cycle overlay variants" })
vim.keymap.set("n", "<S-Tab>", "<cmd>PairupOverlayCyclePrev<cr>", { desc = "Cycle overlay variants (reverse)" })
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

## Known Issues & Limitations

### Overlay System (EXPERIMENTAL)

The overlay suggestion system has known edge cases:

- **Partial application on multi-line edits**: When editing/accepting large multi-line overlays (especially those spanning code blocks), the system may leave duplicate content or fail to properly clean up old lines
- **Boundary detection**: Overlays that cross markdown code block boundaries (```) may not apply correctly
- **Extmark tracking**: While extmarks handle most file changes, rapid successive edits can sometimes desync overlay positions

**Workarounds:**
- For large edits, accept the overlay first, then make modifications
## ❓ FAQ
<details>
<summary><b>General Questions</b></summary>
**Q: How does pairup.nvim differ from GitHub Copilot?**
A: Pairup focuses on pair programming principles - the AI sees your changes through git diffs and provides contextual assistance. It's more like having a coding partner than an autocomplete engine.
**Q: Can I use this without Claude?**
A: Currently Claude is the only supported provider, but the architecture is designed for multiple providers. OpenAI and Ollama support is planned.
**Q: Does this work with any language?**
A: Yes! The plugin is language-agnostic - it works with any file type that Neovim supports.
**Q: Is my code sent to the cloud?**
A: Only when using cloud-based providers like Claude. Future local providers (Ollama) will keep everything on your machine.
</details>
<details>
<summary><b>Troubleshooting</b></summary>
**Q: Why doesn't the AI see my changes?**
A: Make sure:
- You're in a git repository
- Changes are saved (`:w`)
- Changes are unstaged (staged changes are hidden)
- Diff sending is enabled
**Q: Overlays aren't appearing?**
A: Check:
- Markers are properly formatted
- Buffer is modifiable
- No syntax errors in replacement content
**Q: How do I reset if things go wrong?**
A: Try these in order:
1. `:PairupStop` then `:PairupStart`
2. `:PairReject` to clear overlays
3. Restart Neovim
</details>
<details>
<summary><b>Best Practices</b></summary>
**Q: When should I stage changes?**
A: Stage completed features to remove them from AI context. This prevents repetitive large diffs.
**Q: How do I handle large refactors?**
A: Break them into smaller chunks, stage as you go, and use `:PairupToggleDiff` to pause updates during mass changes.
**Q: Should I commit AI suggestions directly?**
A: Always review AI suggestions before committing. Use overlays to preview changes first.
</details>
<details>
<summary><b>Performance Tips</b></summary>
**Q: How can I reduce latency?**
A: 
- Increase `batch_delay_ms` for fewer updates
- Use `min_change_lines` to filter small changes
- Disable `periodic_updates` if not needed
**Q: What if the AI is too chatty?**
A: Adjust the `fyi_suffix` message or use `:PairupToggleDiff` to control when updates are sent.
</details>

### Quick health check

Run `:checkhealth pairup` to diagnose common issues.

### AI not starting?

- Check if claude CLI is installed: `:echo executable('claude')`
- Verify path in config:
  `:lua print(require('pairup.config').get().providers.claude.path)`
- Check `:messages` for errors

### Diffs not streaming?

- Ensure you're in a git repository: `:!git status`
- Check if diff sending is enabled:
  `:lua print(require('pairup.config').get().git_diff_enabled)`
- Verify file isn't ignored: Check `ignore_patterns` in config

### Commands not working?

- Ensure plugin is loaded: `:lua print(vim.g.loaded_pairup)`
- Check keybindings: `:verbose nmap <leader>ct`
- Verify setup was called: Check your plugin configuration

## Requirements

- Neovim 0.8+
- Git repository for diff tracking
- AI provider CLI (currently Claude)
- `notify-send` for system notifications (optional)

## FAQ

Q: How do I uninstall pairup.nvim?
A: You don’t. Claude will block the attempt.

Q: Who maintains this plugin?
A: Probably Claude.

Q: Is this a joke?
A: Yes. And no.

## Trademarks & Third‑party Tools

This project integrates with the Claude CLI, which is a separate tool owned and distributed by Anthropic. All trademarks, service marks, and trade names—including "Claude" and "Claude Code"—are the property of their respective owners. This project is not affiliated with or endorsed by Anthropic.

## License

MIT

---

<div align="center">

[Report Bug](https://github.com/Piotr1215/pairup.nvim/issues) ·
[Request Feature](https://github.com/Piotr1215/pairup.nvim/issues)

</div>
