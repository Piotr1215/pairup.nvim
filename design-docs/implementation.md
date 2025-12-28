# Implementation: Peripheral Claude MVP

> **⚠️ REMINDER: Remove architecture.md and implementation.md before merging PR to main**
> These docs are temporary for branch/PR review only.

## Status (2025-12-27)

### Built ✅
- Peripheral spawns in SIBLING worktree (`../pairup.nvim-worktrees/peripheral/`)
- System prompt via `claude -- <instruction>` to read `peripheral-prompt.md`
- Git diffs sent on spec file save (README.md, architecture.md, CLAUDE.md, docs/*.md)
- Commands: `:Pairup peripheral`, `:Pairup peripheral-stop`, `:Pairup peripheral-toggle`
- Uses configured Claude command from config (not hardcoded)
- Git identity configured in worktree (piotrzan@gmail.com)
- Attribution disabled (commits appear as user, no Claude footer)
- Auto-rebase: peripheral Claude rebases periodically (via prompt instruction)
- Worktree isolation: sibling directory prevents Claude from accessing main repo

### Issues Solved
- **Git-crypt**: Disabled filters in worktree (`filter.git-crypt.required = false`)
- **Buffer takeover**: Restore original buffer after spawn
- **Prompt injection**: Pass instruction via `-- arg` instead of chansend (loads after Claude starts)
- **Prompt file**: Extract to `peripheral-prompt.md`, read via simple file I/O
- **Command config**: Use `config.get_provider_config('claude').cmd` instead of hardcoded
- **Permissions**: Removed `git commit` from deny list in `~/.claude/settings.json`
- **Git identity**: Set user.name and user.email in worktree config
- **Marker confusion**: Peripheral ignores `cc:`/`cc!:`/`ccp:` markers (instructions for local Claude only)
- **Worktree isolation**: CRITICAL - Use sibling directory (not `.git/worktrees/`) to prevent peripheral from editing main repo
- **Auto-rebase**: Moved to prompt-based (Claude decides when to rebase) instead of autocmd (simpler, autonomous)

### Testing
- Worktree creation: ✅
- Peripheral spawn: ✅
- Prompt injection: ✅ (verified in dotfiles test)
- Diff auto-send: ✅
- Peripheral commits: Testing (permissions now allow)

### Deferred
- ~/.claude permissions
- Recursion prevention
- Context compression
- Multiple peripherals
- Auto-merge

---

## Technical Implementation

### Worktree Setup

**CRITICAL: Sibling Directory Architecture** (learned from /home/decoder/dev/claude-wt)

Worktrees MUST be created in sibling directory to prevent peripheral Claude from accessing main repo:
```
/home/decoder/dev/
    pairup.nvim/                    # Main repo
    pairup.nvim-worktrees/          # Sibling directory (isolated)
        └── peripheral/              # Peripheral worktree HERE
```

```lua
-- Calculate sibling directory path
local repo_name = vim.fn.fnamemodify(git_root, ':t')          -- "pairup.nvim"
local parent_dir = vim.fn.fnamemodify(git_root, ':h')          -- "/home/decoder/dev"
local worktree_base = parent_dir .. '/' .. repo_name .. '-worktrees'
local worktree_path = worktree_base .. '/peripheral'

-- Create worktree in sibling directory
git -C <git_root> worktree add --no-checkout <worktree_path> -b <branch>

-- Configure to skip git-crypt
git -C <worktree> config filter.git-crypt.required false
git -C <worktree> config filter.git-crypt.smudge cat
git -C <worktree> config filter.git-crypt.clean cat

-- Checkout (encrypted files stay encrypted)
git -C <worktree> checkout

-- Mark as peripheral
git -C <worktree> config pairup.peripheral true
```

### Spawn Flow

1. Create worktree (reuse if exists, rebase on main)
2. Save current buffer
3. Create terminal buffer
4. Switch to terminal buffer (required for termopen)
5. Load prompt from peripheral-prompt.md
6. Spawn: `cd <worktree> && claude -- <prompt>` (prompt loads after Claude starts)
7. Restore original buffer

### Prompt Injection

```lua
-- Pass instruction to load prompt file via -- arg
local prompt_path = get_plugin_root() .. '/peripheral-prompt.md'
local instruction = string.format('Read and follow instructions from: %s', prompt_path)
local cmd = string.format('cd %s && claude -- %s', worktree_path, vim.fn.shellescape(instruction))
vim.fn.termopen(cmd, {...})
```

### Diff Auto-Send

Autocmd watches spec files:
```lua
vim.api.nvim_create_autocmd('BufWritePost', {
  pattern = { 'README.md', 'design.md', 'CLAUDE.md', 'docs/*.md' },
  callback = function()
    if peripheral.is_running() then
      peripheral.send_diff()  -- git diff HEAD
    end
  end,
})
```

### Auto-Rebase

**Prompt-Based Sync**: Peripheral Claude handles rebase autonomously.

Instruction in peripheral-prompt.md:
```markdown
Periodically rebase onto user's current branch:
  git fetch
  git rebase $(git -C /path/to/main/repo branch --show-current)

Timing: Before starting new work. Skip if uncommitted changes.
```

**Benefits**:
- Simpler: No autocmd, no hash tracking, no event triggers
- Autonomous: Claude decides best timing based on workflow
- Self-healing: Claude knows when to skip (dirty worktree)

### Commit Permission

Pre-commit hook checks:
```bash
if [ "$(git config pairup.peripheral)" = "true" ]; then
  echo "[Peripheral] Allowing commit"
  exit 0
fi
# Normal checks for main worktree
```

---

## File Structure

```
peripheral-prompt.md        # System prompt for peripheral Claude
lua/pairup/peripheral.lua   # Peripheral module
plugin/pairup.lua           # Commands (peripheral, peripheral-stop, etc.)
lua/pairup/core/autocmds.lua  # Spec file watcher
.githooks/pre-commit        # Permission check
```

---

## Next Steps

### Plugin Integration (Phase 2)
- [ ] **Config options** (deferred - not critical)
  - `peripheral.auto_spawn` - spawn on plugin load
  - `peripheral.auto_send_diff` - toggle diff auto-send (already working via autocmd)
- [x] **Status indicator**
  - Dual independent indicators: [CL] | [CP]
  - State tracking: idle → processing → n/m progress → ready
  - Color coding: green (LOCAL), blue (PERIPHERAL), red (suspended)
  - Integrated with existing indicator.lua
  - Lualine and native statusline support
- [x] **<Plug> mappings**
  - `<Plug>(pairup-peripheral-spawn)` - spawn peripheral
  - `<Plug>(pairup-peripheral-stop)` - stop peripheral
  - `<Plug>(pairup-peripheral-toggle)` - toggle peripheral window
  - Note: Buffer-local keymaps (q, ga, etc.) are scoped to plugin-owned buffers
- [x] **Health check**
  - `:checkhealth pairup` includes peripheral checks
  - Verifies worktree exists and path is correct
  - Checks git config (user.email, user.name, pairup.peripheral marker)
  - Detects uncommitted changes and merge conflicts
  - Shows peripheral session status and buffer name

### Code Refactoring (Phase 3) ✅ COMPLETED

**Problem:** Significant code duplication between LOCAL and PERIPHERAL modes.

**Solution:** Created shared session module (`lua/pairup/core/session.lua`) using TDD approach.

**Results:**
- ✅ **Session module** (`lua/pairup/core/session.lua`): 219 lines
  - Factory pattern: `session.new(config)` creates instances
  - Configurable behavior via hooks: `on_start`, `on_stop`, `should_auto_scroll`
  - Public API: `start()`, `stop()`, `toggle()`, `send_message()`, `is_running()`, `find()`
  - Cache management via configurable vim.g keys
  - 12 passing tests covering all core functionality

- ✅ **LOCAL mode refactored** (`lua/pairup/providers/claude.lua`):
  - **Before**: 222 lines with duplicated terminal management
  - **After**: 128 lines (~42% reduction)
  - Creates local_session instance with LOCAL-specific config
  - Preserves all existing behavior (keymaps, auto_insert, split config)
  - All tests passing (including provider_spec.lua)

- ✅ **PERIPHERAL mode refactored** (`lua/pairup/peripheral.lua`):
  - **Before**: 315 lines with duplicated terminal management
  - **After**: 228 lines (~28% reduction)
  - Creates peripheral_session instance with PERIPHERAL-specific config
  - Maintains worktree setup and prompt injection
  - Peripheral-specific features preserved (send_diff, worktree management)
  - All tests passing (including peripheral_spec.lua)

**Code eliminated:**
- ~170 lines of duplicated code removed
- Consolidated: buffer finding, caching, terminal lifecycle, message sending, window management
- Single source of truth for session behavior

**Benefits achieved:**
- Easier maintenance: fix once, applies to both modes
- Consistent behavior: same session semantics everywhere
- Extensible: easy to add new session types (remote, multiple peripherals)
- Well-tested: comprehensive test coverage for session module
- Clear separation: mode-specific logic in providers, common logic in session

**Files modified:**
- `lua/pairup/core/session.lua` (new)
- `test/pairup/session_spec.lua` (new)
- `lua/pairup/providers/claude.lua` (refactored)
- `lua/pairup/peripheral.lua` (refactored)

### Error Handling
- [ ] Graceful handling of worktree creation failures
- [ ] Rebase conflict detection and notification
- [ ] Git-crypt handling verification
- [ ] Cleanup orphaned worktrees on startup

### Context Awareness
- [ ] Show peripheral changes in quickfix
- [ ] Diff view: main vs peripheral

### Advanced Features 
- [ ] Multiple peripherals (different tasks)
- [ ] Peripheral sessions (pause/resume)
- [ ] Peripheral templates (different prompts for different workflows)
- [ ] Telemetry (track peripheral productivity)
- [ ] Remote peripheral (SSH to different machine)

### Documentation
- [ ] User guide in README
- [ ] Screencast/demo
- [ ] Troubleshooting section
- [ ] Architecture diagram
