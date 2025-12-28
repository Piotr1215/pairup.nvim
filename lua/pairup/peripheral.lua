-- Peripheral Claude: autonomous parallel development

local M = {}
local git = require('pairup.utils.git')
local config = require('pairup.config')
local session_factory = require('pairup.core.session')

-- Worktree config (sibling directory to prevent Claude confusion)
local WORKTREE_BRANCH = 'peripheral/' .. os.date('%Y%m%d-%H%M%S')

-- Find plugin root directory
local function get_plugin_root()
  local source = debug.getinfo(1, 'S').source:sub(2)
  return vim.fn.fnamemodify(source, ':h:h:h')
end

-- Setup peripheral worktree in sibling directory
function M.setup_worktree()
  local git_root = git.get_root()
  if not git_root then
    vim.notify('[Peripheral] Not in git repo', vim.log.levels.ERROR)
    return false
  end

  -- Create sibling directory: repo-name-worktrees/peripheral
  local repo_name = vim.fn.fnamemodify(git_root, ':t')
  local parent_dir = vim.fn.fnamemodify(git_root, ':h')
  local worktree_base = parent_dir .. '/' .. repo_name .. '-worktrees'
  local worktree_path = worktree_base .. '/peripheral'

  -- Ensure worktree base directory exists
  vim.fn.mkdir(worktree_base, 'p')

  -- Check if worktree exists
  local exists = vim.fn.isdirectory(worktree_path) == 1

  if exists then
    -- Get user's current branch (what they're actively working on)
    local current_branch = vim.fn.system('git -C ' .. git_root .. ' branch --show-current 2>/dev/null'):gsub('%s+', '')
    if current_branch == '' then
      -- Fallback to default branch
      current_branch = git.get_default_branch(git_root)
    end

    -- Rebase on user's current branch to stay synced
    vim.fn.system(string.format('git -C %s rebase %s 2>&1', worktree_path, current_branch))
    if vim.v.shell_error == 0 then
      return worktree_path
    else
      vim.notify('[Peripheral] Rebase failed, recreating', vim.log.levels.WARN)
      vim.fn.system(string.format('git worktree remove %s --force', vim.fn.shellescape(worktree_path)))
    end
  end

  -- Create new worktree in sibling directory (no-checkout to avoid git-crypt issues)
  local cmd = string.format(
    'git -C %s worktree add --no-checkout %s -b %s',
    vim.fn.shellescape(git_root),
    vim.fn.shellescape(worktree_path),
    WORKTREE_BRANCH
  )
  local output = vim.fn.system(cmd)

  if vim.v.shell_error ~= 0 then
    vim.notify('[Peripheral] Failed to create worktree: ' .. output, vim.log.levels.ERROR)
    return false
  end

  -- Configure git-crypt filter as not required in worktree
  vim.fn.system(string.format('git -C %s config filter.git-crypt.required false', worktree_path))
  vim.fn.system(string.format('git -C %s config filter.git-crypt.smudge cat', worktree_path))
  vim.fn.system(string.format('git -C %s config filter.git-crypt.clean cat', worktree_path))

  -- Checkout (encrypted files will be in encrypted form)
  local checkout_output = vim.fn.system(string.format('git -C %s checkout 2>&1', worktree_path))
  if vim.v.shell_error ~= 0 then
    vim.fn.system(string.format('git worktree remove %s --force', worktree_path))
    vim.notify('[Peripheral] Checkout failed: ' .. checkout_output, vim.log.levels.ERROR)
    return false
  end

  -- Set git config to mark as peripheral
  vim.fn.system(string.format('git -C %s config pairup.peripheral true', worktree_path))

  -- Set git identity for commits
  vim.fn.system(string.format('git -C %s config user.email "piotrzan@gmail.com"', worktree_path))
  vim.fn.system(string.format('git -C %s config user.name "Piotr Zaniewski"', worktree_path))

  return worktree_path
end

-- Create session instance for peripheral Claude
local peripheral_session = session_factory.new({
  type = 'peripheral',
  buffer_name = 'claude-peripheral',
  cache_prefix = 'pairup_peripheral',

  -- Identify peripheral buffers
  buffer_marker = function(buf)
    return vim.b[buf].is_peripheral
  end,

  -- Generate terminal command with prompt injection
  terminal_cmd = function(cwd)
    local claude_config = config.get_provider_config('claude')
    local claude_cmd = claude_config.cmd or 'claude'

    local prompt_path = get_plugin_root() .. '/peripheral-prompt.md'
    local instruction = string.format('Read and follow instructions from: %s', prompt_path)

    return string.format('cd %s && %s -- %s', cwd, claude_cmd, vim.fn.shellescape(instruction))
  end,

  -- Called after terminal is created
  on_start = function(buf, job_id)
    -- Mark buffer for identification
    vim.b[buf].is_peripheral = true

    -- Store worktree path for later use
    local worktree_path = vim.g.pairup_peripheral_worktree_path
    if worktree_path then
      vim.b[buf].worktree_path = worktree_path
    end

    -- Update indicator to show [CP]
    require('pairup.utils.indicator').update_peripheral()
  end,

  -- Called before cleanup
  on_stop = function()
    -- Clear indicator
    require('pairup.utils.indicator').update_peripheral()

    -- Clear worktree path
    vim.g.pairup_peripheral_worktree_path = nil
  end,
})

-- Public API (delegates to session with peripheral-specific enhancements)

function M.is_running()
  return peripheral_session:is_running()
end

function M.find_peripheral()
  return peripheral_session:find()
end

function M.spawn()
  if M.is_running() then
    vim.notify('[Peripheral] Already running', vim.log.levels.WARN)
    return false
  end

  local worktree_path = M.setup_worktree()
  if not worktree_path then
    return false
  end

  -- Store worktree path for on_start hook
  vim.g.pairup_peripheral_worktree_path = worktree_path

  return peripheral_session:start({
    cwd = worktree_path,
    termopen_opts = {
      env = { PAIRUP_PERIPHERAL = '1' },
    },
  })
end

function M.stop()
  local buf, win, job_id = M.find_peripheral()

  if not buf then
    vim.notify('[Peripheral] Not running', vim.log.levels.WARN)
    return
  end

  peripheral_session:stop()
end

function M.toggle()
  return peripheral_session:toggle()
end

function M.send_message(message)
  return peripheral_session:send_message(message)
end

-- Send diff to peripheral (peripheral-specific feature)
function M.send_diff()
  -- Check if suspended
  if vim.g.pairup_peripheral_suspended then
    return false
  end

  local buf, _, _ = M.find_peripheral()
  if not buf then
    vim.notify('[Peripheral] Not running', vim.log.levels.WARN)
    return false
  end

  local worktree_path = vim.b[buf].worktree_path
  if not worktree_path then
    vim.notify('[Peripheral] No worktree path found', vim.log.levels.ERROR)
    return false
  end

  -- Get unstaged changes (specs)
  local diff_cmd = 'git diff HEAD'
  local diff = vim.fn.system(diff_cmd)

  if diff == '' then
    return false
  end

  -- Deduplicate: skip if diff unchanged since last send
  local diff_hash = vim.fn.sha256(diff)
  if vim.g.pairup_peripheral_last_diff_hash == diff_hash then
    return false
  end
  vim.g.pairup_peripheral_last_diff_hash = diff_hash

  local message = string.format(
    [[

=== SPEC CHANGES ===
The user changed the following specifications:

%s

Based on these changes, infer the intent and take action autonomously.
Remember: You are in worktree %s
Commit your work when complete.

]],
    diff,
    worktree_path
  )

  -- Set pending state before sending
  require('pairup.utils.indicator').set_peripheral_pending('analyzing')

  return M.send_message(message)
end

return M
