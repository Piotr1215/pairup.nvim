-- Git utilities for pairup.nvim

local M = {}

-- Get git root directory
function M.get_root()
  local git_root = vim.fn.system('git rev-parse --show-toplevel 2>/dev/null'):gsub('\n', '')
  if vim.v.shell_error == 0 and git_root ~= '' then
    return git_root
  end
  return nil
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

-- Format a diff with truncation
---@param diff_cmd string Git diff command
---@param header string Section header
---@param max_lines integer Maximum lines before truncation
---@return string
local function format_diff(diff_cmd, header, max_lines)
  local stat = vim.fn.system(diff_cmd .. ' --stat 2>/dev/null')
  if stat == '' then
    return ''
  end

  local result = '\n' .. header .. ':\n```\n' .. stat .. '```\n'
  local full = vim.fn.system(diff_cmd .. ' --unified=3 2>/dev/null')
  local lines = vim.split(full, '\n')

  if #lines > max_lines then
    local truncated = table.concat(vim.list_slice(lines, 1, max_lines), '\n')
    result = result .. '```diff\n' .. truncated .. '\n... (truncated, ' .. (#lines - max_lines) .. ' more lines)\n```\n'
  elseif #lines > 1 then
    result = result .. '```diff\n' .. full .. '```\n'
  end
  return result
end

-- Format file list
---@param files string[] List of filenames
---@param prefix string Display prefix (e.g., '+', 'M', '?')
---@param label string Section label
---@return string
local function format_file_list(files, prefix, label)
  if #files == 0 then
    return ''
  end
  local result = label .. ' (' .. #files .. '):\n'
  for _, file in ipairs(files) do
    result = result .. '  ' .. prefix .. ' ' .. file .. '\n'
  end
  return result
end

-- Get branch and upstream info
---@return string
local function get_branch_info()
  local branch = vim.fn.system('git branch --show-current 2>/dev/null'):gsub('\n', '')
  local upstream = vim.fn.system('git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null'):gsub('\n', '')
  local result = 'Branch: ' .. branch
  if upstream ~= '' then
    result = result .. ' → ' .. upstream
  end

  local rev_list = vim.fn.system('git rev-list --left-right --count HEAD...@{u} 2>/dev/null'):gsub('\n', '')
  if rev_list ~= '' then
    local ahead, behind = rev_list:match('(%d+)%s+(%d+)')
    if ahead and behind then
      result = result .. string.format('\n↑ %s ahead, ↓ %s behind upstream', ahead, behind)
    end
  end
  return result .. '\n'
end

-- Send comprehensive git status
function M.send_git_status()
  local providers = require('pairup.providers')
  local timestamp = os.date('%H:%M:%S')
  local parts = { string.format('\n=== COMPREHENSIVE GIT OVERVIEW [%s] ===\n', timestamp) }

  parts[#parts + 1] = get_branch_info()

  local files = M.parse_status()
  parts[#parts + 1] = '\nFILE STATUS:\n'
  parts[#parts + 1] = format_file_list(files.staged, '+', 'Staged')
  parts[#parts + 1] = format_file_list(files.unstaged, 'M', 'Unstaged')
  parts[#parts + 1] = format_file_list(files.untracked, '?', 'Untracked')

  parts[#parts + 1] = format_diff('git diff --cached', 'STAGED CHANGES (will be committed)', 50)
  parts[#parts + 1] = format_diff('git diff', 'UNSTAGED CHANGES (working directory)', 50)

  local commits = vim.fn.system('git log --oneline -10 2>/dev/null')
  if commits ~= '' then
    parts[#parts + 1] = '\nRECENT COMMITS:\n```\n' .. commits .. '```\n'
  end

  local stash = vim.fn.system('git stash list 2>/dev/null')
  if stash ~= '' then
    local stash_count = select(2, stash:gsub('\n', '\n'))
    parts[#parts + 1] = '\nSTASHES: ' .. stash_count .. ' stashed changes\n'
  end

  parts[#parts + 1] = '=== End Overview ===\n'
  parts[#parts + 1] = 'This is for your information only. No action required.\n\n'

  providers.send_to_provider(table.concat(parts))
end

-- Get default branch (respects git config, origin/HEAD, or fallback)
---@param git_root string? Optional git root path
---@return string
function M.get_default_branch(git_root)
  local prefix = git_root and ('git -C ' .. git_root .. ' ') or 'git '

  -- Try origin/HEAD first (most reliable for cloned repos)
  local origin_head = vim.fn.system(prefix .. 'symbolic-ref refs/remotes/origin/HEAD 2>/dev/null')
  if vim.v.shell_error == 0 and origin_head ~= '' then
    return origin_head:gsub('refs/remotes/origin/', ''):gsub('%s+', '')
  end

  -- Try git config init.defaultBranch
  local config_default = vim.fn.system(prefix .. 'config init.defaultBranch 2>/dev/null'):gsub('%s+', '')
  if vim.v.shell_error == 0 and config_default ~= '' then
    return config_default
  end

  -- Check which common branch exists
  for _, branch in ipairs({ 'main', 'master', 'trunk', 'develop' }) do
    vim.fn.system(prefix .. 'rev-parse --verify ' .. branch .. ' 2>/dev/null')
    if vim.v.shell_error == 0 then
      return branch
    end
  end

  return 'main' -- Last resort fallback
end

return M
