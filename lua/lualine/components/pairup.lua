-- Lualine component for pairup.nvim
-- Usage: Add 'pairup' to your lualine sections
--   lualine_c = { 'filename', 'pairup' }

local M = require('lualine.component'):extend()

function M:init(options)
  local default_color = options.color or { fg = '#00ff00' }
  local suspended_color = options.suspended_color or { fg = '#ff5555' }
  options.color = function()
    return vim.g.pairup_suspended and suspended_color or default_color
  end
  M.super.init(self, options)
end

function M:update_status()
  local indicator = vim.g.pairup_indicator
  return (indicator and indicator ~= '') and indicator or ''
end

return M
