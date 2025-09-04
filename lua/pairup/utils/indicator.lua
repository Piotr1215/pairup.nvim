-- Status indicator for pairup.nvim

local M = {}
local config = require('pairup.config')

-- Update status indicator for lualine
function M.update()
  local providers = require('pairup.providers')
  local buf = providers.find_terminal()
  if not buf then
    vim.g.pairup_indicator = '' -- AI not running
  elseif config.get('enabled') then
    local provider = config.get_provider()
    vim.g.pairup_indicator = string.format('[%s]', provider:sub(1, 1):upper()) -- [C] for Claude, [O] for Ollama, etc.
  else
    local provider = config.get_provider()
    vim.g.pairup_indicator = string.format('[%s-off]', provider:sub(1, 1):upper()) -- [C-off] for Claude disabled
  end

  -- Legacy indicator for backward compatibility
  vim.g.claude_context_indicator = vim.g.pairup_indicator
end

-- Get indicator for statusline
function M.get()
  return vim.g.pairup_indicator or ''
end

return M
