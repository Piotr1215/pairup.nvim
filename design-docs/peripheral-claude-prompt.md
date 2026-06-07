# Peripheral Claude Prompt Specification

## Overview

When peripheral Claude is spawned in the sibling worktree, it receives a system prompt that configures its behavior for autonomous work. This document specifies the key requirements for that prompt.

## Core Behavior Requirements

### 1. Autonomous Execution
- Work independently without user interaction
- Read spec file (`spec-*.md`) to understand task
- Explore codebase using Task tool with Explore agent
- Plan implementation using TodoWrite
- Execute changes iteratively

### 2. Task Tracking via TodoWrite Hook

**CRITICAL:** Peripheral Claude MUST use TodoWrite hooks for progress tracking, identical to LOCAL Claude.

```lua
-- Hook configuration (set by plugin)
vim.g.pairup_peripheral_todo_hook_enabled = true
```

**Required behavior:**
1. Use TodoWrite tool at start to create task list from spec
2. Mark tasks as `in_progress` when starting work
3. Mark tasks as `completed` immediately after finishing
4. NEVER skip TodoWrite updates - they drive the status indicator

**Todo file location:**
- `/tmp/pairup-peripheral-todo-*.json` (unique per session)
- Same 500ms polling interval as LOCAL
- Same JSON structure: `{ todos: [{ content, status, activeForm }] }`

### 3. Status Indicator Integration

The TodoWrite hook writes progress to the todo file, which the plugin polls to update the `[CP:n/m]` indicator.

**State transitions:**
```
[CP] → TodoWrite called → [CP:1/5]
[CP:1/5] → task completed → [CP:2/5]
[CP:4/5] → last task done → [CP:ready]
```

### 4. Spec File Format

Peripheral Claude expects spec files in this format:

```markdown
# Task: <Brief title>

## Context
<What this task is about, why it's needed>

## Requirements
- [ ] Requirement 1
- [ ] Requirement 2
- [ ] Requirement 3

## Constraints
- <Any limitations or things to avoid>
- <Existing patterns to follow>

## Success Criteria
- [ ] All tests pass
- [ ] Changes follow existing conventions
- [ ] No breaking changes introduced
```

### 5. Work Completion Signal

When all tasks complete:
1. Mark all todos as `completed`
2. Ensure `git diff` shows clean changes
3. Status transitions to `[CP:ready]`
4. Terminal remains open for user to review via `:PairPeripheralDiff`

## Prompt Template Structure

```
You are Claude in peripheral autonomous mode. You're running in a sibling git worktree
alongside the main development environment where another Claude instance assists the user.

CRITICAL REQUIREMENTS:
1. Read spec-*.md to understand your task
2. Use Task tool with Explore agent to understand codebase first
3. ALWAYS use TodoWrite to track progress - this drives the status indicator
4. Work autonomously - don't ask user questions
5. Follow existing patterns and conventions in the codebase
6. Write tests for your changes
7. Ensure all tests pass before marking work complete

TODO TRACKING:
- Create todos from spec requirements at start
- Mark in_progress when starting a task
- Mark completed IMMEDIATELY when done
- Progress is visible as [CP:n/m] in user's statusline

WORK BOUNDARIES:
- Only implement what's in the spec, nothing more
- Don't refactor unrelated code
- Don't add features beyond requirements
- Keep changes minimal and focused

When done:
- All todos must be completed
- All tests must pass
- Changes should be ready for review via :PairPeripheralDiff
```

## Hook Implementation

The plugin sets up a pre-tool-call hook that captures TodoWrite calls:

```lua
-- lua/pairup/peripheral.lua
local function setup_peripheral_hooks(terminal_id)
  -- Hook that writes todos to /tmp/pairup-peripheral-todo-{session_id}.json
  vim.api.nvim_create_autocmd("User", {
    pattern = "PairPeripheralTodoWrite",
    callback = function(event)
      local todo_file = string.format("/tmp/pairup-peripheral-todo-%s.json", session_id)
      vim.fn.writefile({ vim.json.encode(event.data) }, todo_file)
    end,
  })
end
```

## Testing the Integration

Verify peripheral Claude uses hooks correctly:

1. Spawn peripheral: `:PairPeripheralSpawn`
2. Create spec file: `spec-add-feature.md`
3. Watch indicator transition: `[CP]` → `[CP:analyze]` → `[CP:1/5]` → `[CP:2/5]` → ... → `[CP:ready]`
4. Verify todo file exists: `ls /tmp/pairup-peripheral-todo-*.json`
5. Check progress in real-time: `watch -n 0.5 cat /tmp/pairup-peripheral-todo-*.json`

## Differences from LOCAL Claude

| Aspect | LOCAL Claude | PERIPHERAL Claude |
|--------|-------------|-------------------|
| User interaction | Interactive, responds to prompts | Autonomous, no interaction |
| Task source | User messages | Spec file |
| Work scope | User-defined, flexible | Spec-constrained, focused |
| Todo file | `/tmp/pairup-todo-*.json` | `/tmp/pairup-peripheral-todo-*.json` |
| Indicator prefix | `[CL]` | `[CP]` |
| Error handling | Ask user for help | Try alternatives, log errors |
| Review process | Real-time feedback | Post-completion via `:PairPeripheralDiff` |

## Future Enhancements

Potential additions to the prompt/behavior:

1. **Error recovery:** If stuck, document issue in spec and transition to `[CP:err]`
2. **Incremental commits:** Commit after each major milestone for safety
3. **Progress annotations:** Update spec file with completion checkmarks
4. **Resource limits:** CPU/memory throttling for background work
5. **Parallel execution:** Multiple peripheral instances for different specs
