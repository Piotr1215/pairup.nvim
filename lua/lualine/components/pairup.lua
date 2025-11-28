-- Lualine component for pairup.nvim
-- Usage: Add 'pairup' to your lualine sections
--   lualine_c = { 'filename', 'pairup' }

local M = require('lualine.component'):extend()

function M:init(options)
  -- Set green color as default
  options.color = options.color or { fg = '#00ff00' }
  M.super.init(self, options)
end

function M:update_status()
  local indicator = vim.g.pairup_indicator
  if not indicator or indicator == '' then
    return ''
  end
  return indicator
end

return M
