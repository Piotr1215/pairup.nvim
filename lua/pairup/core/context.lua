-- Context management for pairup.nvim

local M = {}
local config = require('pairup.config')
local state = require('pairup.utils.state')
local git = require('pairup.utils.git')
local filters = require('pairup.utils.filters')

-- Batch timer for collecting multiple updates
local batch_timer = nil

-- Setup the context module
function M.setup()
  -- Nothing to setup yet
end

-- Format context update message
local function format_context_update(filepath, diff)
  local timestamp = os.date('%H:%M:%S')
  local message = string.format('\n=== FYI: Context Update [%s] ===\nFile saved: %s\n', timestamp, filepath)

  -- Get statistics about other modified files
  local status = git.parse_status()
  local other_changes = {}

  if #status.staged > 0 then
    table.insert(other_changes, #status.staged .. ' staged')
  end
  if #status.unstaged > 0 then
    -- Exclude current file from count
    local count = 0
    local current_file = vim.fn.fnamemodify(filepath, ':.')
    for _, file in ipairs(status.unstaged) do
      if file ~= current_file then
        count = count + 1
      end
    end
    if count > 0 then
      table.insert(other_changes, count .. ' modified')
    end
  end
  if #status.untracked > 0 then
    table.insert(other_changes, #status.untracked .. ' untracked')
  end

  if #other_changes > 0 then
    message = message .. 'Other files: ' .. table.concat(other_changes, ', ') .. '\n'
  end

  if diff and diff ~= '' then
    -- Clean up the diff output
    local lines = vim.split(diff, '\n')
    local clean_diff = {}
    for _, line in ipairs(lines) do
      -- Skip binary file messages and empty lines at the end
      if not line:match('^Binary files') and (line ~= '' or #clean_diff > 0) then
        table.insert(clean_diff, line)
      end
    end

    if #clean_diff > 0 then
      message = message .. 'Changes:\n```diff\n' .. table.concat(clean_diff, '\n') .. '\n```\n'
    else
      message = message .. 'File saved (no git changes detected)\n'
    end
  else
    message = message .. 'File saved (not in git repository)\n'
  end

  -- Add LSP diagnostics if enabled
  if config.get('lsp.enabled') and config.get('lsp.include_diagnostics') then
    -- Get current buffer number (more reliable than filepath lookup)
    local bufnr = vim.api.nvim_get_current_buf()
    local diagnostics = vim.diagnostic.get(bufnr)
    if #diagnostics > 0 then
      message = message .. '\nLSP Diagnostics:\n'
      for _, diag in ipairs(diagnostics) do
        local severity = ({ 'ERROR', 'WARN', 'INFO', 'HINT' })[diag.severity]
        message = message .. string.format('• Line %d: [%s] %s\n', diag.lnum + 1, severity, diag.message)
      end
    end
  end

  message = message .. config.get('fyi_suffix')
  message = message .. '=== End Context Update ===\n\n'
  return message
end

-- Send batched updates
local function send_batched_updates()
  local pending_updates = state.get_pending_updates()
  if not pending_updates or not next(pending_updates) then
    return
  end

  local providers = require('pairup.providers')
  local timestamp = os.date('%H:%M:%S')
  local message = string.format('\n=== FYI: Batched Context Update [%s] ===\nFiles saved:\n', timestamp)

  -- List files being sent with diffs
  for filepath, _ in pairs(pending_updates) do
    message = message .. string.format('• %s (diff included)\n', filepath)
  end

  -- Get other modified files statistics
  local status = git.parse_status()
  local staged_count = #status.staged
  local modified_count = 0

  for _, file in ipairs(status.unstaged) do
    if not pending_updates[file] then
      modified_count = modified_count + 1
    end
  end

  if staged_count > 0 or modified_count > 0 then
    message = message .. '\nOther changes in workspace:\n'
    if staged_count > 0 then
      message = message .. string.format('  • %d file(s) staged\n', staged_count)
    end
    if modified_count > 0 then
      message = message .. string.format('  • %d file(s) modified\n', modified_count)
    end
  end

  message = message .. '\nChanges:\n'

  -- Only include diffs for the files that were actually saved
  for filepath, update_data in pairs(pending_updates) do
    local diff = update_data.diff or update_data
    message = message .. string.format('\n--- %s ---\n```diff\n%s\n```\n', filepath, diff)
  end

  message = message .. config.get('fyi_suffix')
  message = message .. '=== End Context Update ===\n\n'

  providers.send_to_provider(message)
  state.clear_pending_updates()
end

-- Send current file context with smart filtering
function M.send_context(force)
  local filepath = vim.fn.expand('%:p')
  local relative_path = vim.fn.fnamemodify(filepath, ':.')

  -- Get UNSTAGED changes only
  local diff = git.get_file_diff(filepath)

  -- Check if diff is significant
  if not force and not filters.is_significant_diff(diff) then
    return
  end

  local providers = require('pairup.providers')

  -- If batching is enabled, add to pending updates
  if config.get('filter.batch_delay_ms') > 0 and not force then
    state.add_pending_update(relative_path, { diff = diff })

    -- Cancel existing timer
    if batch_timer then
      batch_timer:stop()
    end

    -- Start new timer
    batch_timer = vim.loop.new_timer()
    batch_timer:start(
      config.get('filter.batch_delay_ms'),
      0,
      vim.schedule_wrap(function()
        send_batched_updates()
        batch_timer = nil
      end)
    )
  else
    -- Send immediately
    local message = format_context_update(relative_path, diff)
    providers.send_to_provider(message)
  end
end

-- Send file information about current buffer
function M.send_file_info()
  local filepath = vim.fn.expand('%:p')
  local filename = vim.fn.expand('%:t')
  local relative_path = vim.fn.fnamemodify(filepath, ':.')

  -- Skip certain files
  if filepath:match('%.git/') or filepath:match('node_modules/') or filepath:match('%.log$') or filename == '' then
    vim.notify('Cannot send info for this file type', vim.log.levels.WARN)
    return
  end

  local providers = require('pairup.providers')
  local timestamp = os.date('%H:%M:%S')
  local message = string.format('\n=== FYI: File Context [%s] ===\n', timestamp)

  message = message .. 'File: ' .. relative_path .. '\n'

  -- Get file info
  local file_stat = vim.loop.fs_stat(filepath)
  if file_stat then
    local size = file_stat.size
    local size_str = size < 1024 and size .. 'B'
      or size < 1024 * 1024 and string.format('%.1fKB', size / 1024)
      or string.format('%.1fMB', size / (1024 * 1024))
    message = message .. 'Size: ' .. size_str .. '\n'

    -- File type
    local filetype = vim.bo.filetype
    if filetype ~= '' then
      message = message .. 'Type: ' .. filetype .. '\n'
    end
  end

  -- Get git info if in git repo
  local git_info = git.get_file_info(filepath)
  if git_info.last_commit and git_info.last_commit ~= '' then
    message = message .. 'Last commit: ' .. git_info.last_commit .. '\n'
  end

  if git_info.status then
    message = message .. 'Status: ' .. git_info.status .. '\n'
  end

  if git_info.changes then
    message = message .. 'Changes: ' .. git_info.changes .. '\n'
  end

  message = message .. config.get('fyi_suffix')
  message = message .. '=== End File Context ===\n\n'

  providers.send_to_provider(message)
end

-- Add current directory to AI assistant
function M.add_current_directory()
  local providers = require('pairup.providers')

  -- Only proceed if AI is running
  local buf = providers.find_terminal()
  if not buf then
    return
  end

  -- Determine which directory to add
  local dir_to_add = git.get_root() or vim.fn.getcwd()

  -- Check if already added
  if state.has_directory(dir_to_add) then
    -- Directory already added
    return
  end

  -- Mark as added and send command (Claude-specific for now)
  state.add_directory(dir_to_add)
  local add_dir_msg = string.format('/add-dir %s', dir_to_add)
  providers.send_to_provider(add_dir_msg)

  -- Added directory to AI assistant
end

return M
