-- Status indicator for pairup.nvim

local M = {}
local config = require('pairup.config')

-- Update status indicator for lualine
function M.update()
  local providers = require('pairup.providers')
  local buf = providers.find_terminal()
  if not buf then
    vim.g.pairup_indicator = '' -- AI not running
  else
    -- AI is running - show provider indicator with status
    local provider = config.get_provider()
    local prefix = provider:sub(1, 1):upper()
    local inline_mode = config.get('inline.enabled')

    if inline_mode then
      -- Check for pending/queued status
      if vim.g.pairup_queued then
        vim.g.pairup_indicator = string.format('[%s:queued]', prefix)
      elseif vim.g.pairup_pending then
        vim.g.pairup_indicator = string.format('[%s:pending]', prefix)
      else
        vim.g.pairup_indicator = string.format('[%s]', prefix)
      end
    elseif config.get('enabled') then
      vim.g.pairup_indicator = string.format('[%s]', prefix)
    else
      vim.g.pairup_indicator = string.format('[%s-off]', prefix)
    end
  end

  -- Legacy indicator for backward compatibility
  vim.g.claude_context_indicator = vim.g.pairup_indicator
end

-- Set status to pending for a file
function M.set_pending(filepath)
  vim.g.pairup_pending = filepath
  vim.g.pairup_pending_time = os.time()
  M.update()
end

-- Clear pending status
function M.clear_pending()
  vim.g.pairup_pending = nil
  vim.g.pairup_pending_time = nil
  vim.g.pairup_queued = false
  M.update()
end

-- Set queued status (user saved while pending)
function M.set_queued()
  vim.g.pairup_queued = true
  M.update()
end

-- Check if file is pending (with 60s timeout)
function M.is_pending(filepath)
  if vim.g.pairup_pending ~= filepath then
    return false
  end
  -- Timeout after 60 seconds
  local elapsed = os.time() - (vim.g.pairup_pending_time or 0)
  if elapsed > 60 then
    M.clear_pending()
    return false
  end
  return true
end

-- Get indicator for statusline
function M.get()
  return vim.g.pairup_indicator or ''
end

return M
