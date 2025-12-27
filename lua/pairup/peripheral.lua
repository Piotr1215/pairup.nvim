-- Peripheral Claude: autonomous parallel development

local M = {}
local git = require('pairup.utils.git')
local config = require('pairup.config')

-- Worktree config (sibling directory to prevent Claude confusion)
local WORKTREE_BRANCH = 'peripheral/' .. os.date('%Y%m%d-%H%M%S')

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
    -- Rebase on main to sync
    vim.fn.system(string.format('git -C %s rebase main 2>&1', worktree_path))
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
    vim.fn.system(string.format('git worktree remove %s --force', WORKTREE_DIR))
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

-- Find peripheral terminal
function M.find_peripheral()
  local cached_buf = vim.g.pairup_peripheral_buf
  if cached_buf and vim.api.nvim_buf_is_valid(cached_buf) then
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_buf(win) == cached_buf then
        return cached_buf, win, vim.g.pairup_peripheral_job
      end
    end
    return cached_buf, nil, vim.g.pairup_peripheral_job
  end

  -- Cache miss
  vim.g.pairup_peripheral_buf = nil
  vim.g.pairup_peripheral_job = nil

  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) and vim.b[buf].is_peripheral then
      vim.g.pairup_peripheral_buf = buf
      vim.g.pairup_peripheral_job = vim.b[buf].terminal_job_id
      return buf, nil, vim.b[buf].terminal_job_id
    end
  end

  return nil, nil, nil
end

-- Check if peripheral is running
function M.is_running()
  local buf = vim.g.pairup_peripheral_buf
  return buf and vim.api.nvim_buf_is_valid(buf)
end

-- Find plugin root directory
local function get_plugin_root()
  local source = debug.getinfo(1, 'S').source:sub(2)
  return vim.fn.fnamemodify(source, ':h:h:h')
end

-- Load system prompt from peripheral-prompt.md
local function load_system_prompt()
  local prompt_path = get_plugin_root() .. '/peripheral-prompt.md'
  local f = io.open(prompt_path, 'r')
  if not f then
    return ''
  end

  local content = f:read('*all')
  f:close()

  return content
end

-- Spawn peripheral Claude
function M.spawn()
  if M.is_running() then
    vim.notify('[Peripheral] Already running', vim.log.levels.WARN)
    return false
  end

  local worktree_path = M.setup_worktree()
  if not worktree_path then
    return false
  end

  local orig_buf = vim.api.nvim_get_current_buf()

  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_set_current_buf(buf)

  local claude_config = config.get_provider_config('claude')
  local claude_cmd = claude_config.cmd or 'claude'

  local prompt_path = get_plugin_root() .. '/peripheral-prompt.md'
  local instruction = string.format('Read and follow instructions from: %s', prompt_path)
  local cmd = string.format('cd %s && %s -- %s', worktree_path, claude_cmd, vim.fn.shellescape(instruction))

  local job_id = vim.fn.termopen(cmd, {
    cwd = worktree_path,
    env = { PAIRUP_PERIPHERAL = '1' },
    on_exit = function()
      vim.g.pairup_peripheral_buf = nil
      vim.g.pairup_peripheral_job = nil
      -- Clear indicator on exit
      require('pairup.utils.indicator').update_peripheral()
    end,
  })

  if job_id <= 0 then
    vim.api.nvim_set_current_buf(orig_buf)
    vim.api.nvim_buf_delete(buf, { force = true })
    vim.notify('[Peripheral] Failed to spawn', vim.log.levels.ERROR)
    return false
  end

  -- Set buffer name after terminal opens to override automatic term:// naming
  pcall(vim.api.nvim_buf_set_name, buf, 'claude-peripheral')

  vim.api.nvim_set_current_buf(orig_buf)

  vim.b[buf].is_peripheral = true
  vim.b[buf].terminal_job_id = job_id
  vim.b[buf].worktree_path = worktree_path

  vim.g.pairup_peripheral_buf = buf
  vim.g.pairup_peripheral_job = job_id

  -- Update indicator to show [CP]
  require('pairup.utils.indicator').update_peripheral()

  return true
end

-- Stop peripheral
function M.stop()
  local buf, win, job_id = M.find_peripheral()

  if not buf then
    vim.notify('[Peripheral] Not running', vim.log.levels.WARN)
    return
  end

  if win and #vim.api.nvim_list_wins() > 1 then
    vim.api.nvim_win_close(win, false)
  end

  if job_id then
    vim.fn.jobstop(job_id)
  end

  vim.api.nvim_buf_delete(buf, { force = true })

  vim.g.pairup_peripheral_buf = nil
  vim.g.pairup_peripheral_job = nil

  -- Clear indicator
  require('pairup.utils.indicator').update_peripheral()
end

-- Send message to peripheral (matches providers/claude.lua pattern)
function M.send_message(message)
  local buf, win, job_id = M.find_peripheral()

  if not buf or not job_id then
    vim.notify('[Peripheral] Not running', vim.log.levels.WARN)
    return false
  end

  local ok = pcall(vim.fn.chansend, job_id, message)
  if not ok then
    vim.g.pairup_peripheral_buf = nil
    vim.g.pairup_peripheral_job = nil
    return false
  end

  -- Send Enter and scroll after delay
  vim.defer_fn(function()
    pcall(vim.fn.chansend, job_id, string.char(13))

    if win then
      vim.api.nvim_win_call(win, function()
        if vim.api.nvim_get_mode().mode ~= 't' then
          vim.cmd('norm G')
        end
      end)
    end
  end, 500)

  return true
end

-- Send diff to peripheral
function M.send_diff()
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

-- Toggle peripheral window
function M.toggle()
  local buf, win = M.find_peripheral()

  if win then
    if #vim.api.nvim_list_wins() > 1 then
      vim.api.nvim_win_close(win, false)
    end
    return true
  elseif buf then
    vim.cmd('vsplit')
    vim.api.nvim_set_current_buf(buf)
    vim.cmd('wincmd p')
    return false
  else
    M.spawn()
    vim.defer_fn(M.toggle, 500)
    return false
  end
end

return M
