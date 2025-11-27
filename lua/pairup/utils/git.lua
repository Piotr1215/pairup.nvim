-- Git utilities for pairup.nvim

local M = {}
local config = require('pairup.config')

-- Get git root directory
function M.get_root()
  local git_root = vim.fn.system('git rev-parse --show-toplevel 2>/dev/null'):gsub('\n', '')
  if vim.v.shell_error == 0 and git_root ~= '' then
    return git_root
  end
  return nil
end

-- Check if file is in git repo
function M.is_in_repo(filepath)
  local result = vim.fn.system(
    string.format('git ls-files --error-unmatch %s 2>/dev/null', vim.fn.shellescape(filepath or vim.fn.expand('%:p')))
  )
  return vim.v.shell_error == 0
end

-- Get unstaged diff for file
function M.get_file_diff(filepath)
  local context = config.get('git.diff_context_lines') or 10
  local diff_cmd = string.format('git diff --unified=%d -- %s', context, vim.fn.shellescape(filepath))
  return vim.fn.system(diff_cmd)
end

-- Get git status
function M.get_status()
  return vim.fn.system('git status --porcelain 2>/dev/null')
end

-- Parse git status
function M.parse_status()
  local status = M.get_status()
  local staged_files = {}
  local unstaged_files = {}
  local untracked_files = {}

  for line in status:gmatch('[^\n]+') do
    local status_code = line:sub(1, 2)
    local filename = line:sub(4)

    -- First character is staged status, second is unstaged status
    local staged_char = status_code:sub(1, 1)
    local unstaged_char = status_code:sub(2, 2)

    if staged_char:match('[MADRC]') then
      table.insert(staged_files, filename)
    end
    if unstaged_char:match('[MD]') then
      table.insert(unstaged_files, filename)
    end
    if status_code == '??' then
      table.insert(untracked_files, filename)
    end
  end

  return {
    staged = staged_files,
    unstaged = unstaged_files,
    untracked = untracked_files,
  }
end

-- Send comprehensive git status
function M.send_git_status()
  local providers = require('pairup.providers')
  local timestamp = os.date('%H:%M:%S')
  local message = string.format('\n=== COMPREHENSIVE GIT OVERVIEW [%s] ===\n', timestamp)

  -- Current branch and upstream
  local branch = vim.fn.system('git branch --show-current 2>/dev/null'):gsub('\n', '')
  local upstream = vim.fn.system('git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null'):gsub('\n', '')
  message = message .. 'Branch: ' .. branch
  if upstream ~= '' then
    message = message .. ' → ' .. upstream
  end
  message = message .. '\n'

  -- Behind/ahead of upstream
  local rev_list = vim.fn.system('git rev-list --left-right --count HEAD...@{u} 2>/dev/null'):gsub('\n', '')
  if rev_list ~= '' then
    local ahead, behind = rev_list:match('(%d+)%s+(%d+)')
    if ahead and behind then
      message = message .. string.format('↑ %s ahead, ↓ %s behind upstream\n', ahead, behind)
    end
  end

  -- File status
  local files = M.parse_status()

  message = message .. '\nFILE STATUS:\n'
  if #files.staged > 0 then
    message = message .. 'Staged (' .. #files.staged .. '):\n'
    for _, file in ipairs(files.staged) do
      message = message .. '  + ' .. file .. '\n'
    end
  end

  if #files.unstaged > 0 then
    message = message .. 'Unstaged (' .. #files.unstaged .. '):\n'
    for _, file in ipairs(files.unstaged) do
      message = message .. '  M ' .. file .. '\n'
    end
  end

  if #files.untracked > 0 then
    message = message .. 'Untracked (' .. #files.untracked .. '):\n'
    for _, file in ipairs(files.untracked) do
      message = message .. '  ? ' .. file .. '\n'
    end
  end

  -- Staged changes diff
  local staged_diff = vim.fn.system('git diff --cached --stat 2>/dev/null')
  if staged_diff ~= '' then
    message = message .. '\nSTAGED CHANGES (will be committed):\n```\n' .. staged_diff .. '```\n'

    local staged_diff_full = vim.fn.system('git diff --cached --unified=3 2>/dev/null')
    local lines = vim.split(staged_diff_full, '\n')
    if #lines > 50 then
      local truncated = table.concat(vim.list_slice(lines, 1, 50), '\n')
      message = message .. '```diff\n' .. truncated .. '\n... (truncated, ' .. (#lines - 50) .. ' more lines)\n```\n'
    elseif #lines > 1 then
      message = message .. '```diff\n' .. staged_diff_full .. '```\n'
    end
  end

  -- Unstaged changes diff
  local unstaged_diff = vim.fn.system('git diff --stat 2>/dev/null')
  if unstaged_diff ~= '' then
    message = message .. '\nUNSTAGED CHANGES (working directory):\n```\n' .. unstaged_diff .. '```\n'

    local unstaged_diff_full = vim.fn.system('git diff --unified=3 2>/dev/null')
    local lines = vim.split(unstaged_diff_full, '\n')
    if #lines > 50 then
      local truncated = table.concat(vim.list_slice(lines, 1, 50), '\n')
      message = message .. '```diff\n' .. truncated .. '\n... (truncated, ' .. (#lines - 50) .. ' more lines)\n```\n'
    elseif #lines > 1 then
      message = message .. '```diff\n' .. unstaged_diff_full .. '```\n'
    end
  end

  -- Recent commits
  local commits = vim.fn.system('git log --oneline -10 2>/dev/null')
  if commits ~= '' then
    message = message .. '\nRECENT COMMITS:\n```\n' .. commits .. '```\n'
  end

  -- Stash status
  local stash = vim.fn.system('git stash list 2>/dev/null')
  if stash ~= '' then
    local stash_count = select(2, stash:gsub('\n', '\n'))
    message = message .. '\nSTASHES: ' .. stash_count .. ' stashed changes\n'
  end

  message = message .. '=== End Overview ===\n'
  message = message .. 'This is for your information only. No action required.\n\n'

  providers.send_to_provider(message)
end

-- Send unstaged files list
function M.send_unstaged_files()
  local providers = require('pairup.providers')
  local timestamp = os.date('%H:%M:%S')
  local files = M.parse_status()

  if #files.untracked == 0 and #files.unstaged == 0 then
    vim.notify('No untracked or modified unstaged files', vim.log.levels.INFO)
    return
  end

  local message = string.format('\n=== File Reading Request [%s] ===\n', timestamp)

  if #files.untracked > 0 then
    message = message .. 'Please read these NEW untracked files:\n'
    for _, file in ipairs(files.untracked) do
      message = message .. '• ' .. file .. '\n'
    end
  end

  if #files.unstaged > 0 then
    if #files.untracked > 0 then
      message = message .. '\n'
    end
    message = message .. 'These tracked files have unstaged changes (use git diff to see changes):\n'
    for _, file in ipairs(files.unstaged) do
      message = message .. '• ' .. file .. '\n'
    end
  end

  message = message .. '\nYou can read these files with your tools if I ask you to.\n'
  message = message .. '=== End Request ===\n\n'

  providers.send_to_provider(message)
end

-- Get file info
function M.get_file_info(filepath)
  local info = {}

  -- Last commit for file
  info.last_commit = vim.fn
    .system(string.format("git log -1 --pretty='%%h %%s (%%ar by %%an)' -- %s 2>/dev/null", vim.fn.shellescape(filepath)))
    :gsub('\n', '')

  -- Check if tracked
  info.is_tracked = M.is_in_repo(filepath)

  if info.is_tracked then
    -- Check for changes
    local has_changes = vim.fn
      .system(string.format('git diff --name-only -- %s 2>/dev/null', vim.fn.shellescape(filepath)))
      :gsub('\n', '')

    local has_staged = vim.fn
      .system(string.format('git diff --cached --name-only -- %s 2>/dev/null', vim.fn.shellescape(filepath)))
      :gsub('\n', '')

    if has_staged ~= '' then
      info.status = 'Has staged changes'
    elseif has_changes ~= '' then
      info.status = 'Has unstaged changes'
    else
      info.status = 'Clean (no changes)'
    end

    -- Count lines changed
    local diff_stat =
      vim.fn.system(string.format('git diff --numstat -- %s 2>/dev/null', vim.fn.shellescape(filepath))):gsub('\n', '')

    if diff_stat ~= '' then
      local added, removed = diff_stat:match('(%d+)%s+(%d+)')
      if added and removed then
        info.changes = string.format('+%s -%s lines', added, removed)
      end
    end
  else
    info.status = 'Untracked file'
  end

  return info
end

return M
