-- Lualine component for pairup.nvim
-- Usage: Add 'pairup' to your lualine sections
--   lualine_c = { 'filename', 'pairup' }

local M = require('lualine.component'):extend()

function M:init(options)
  -- Set up colors for LOCAL (green) and PERIPHERAL (blue) indicators
  local default_color = options.color
    or function()
      local local_ind = vim.g.pairup_indicator or ''
      local periph_ind = vim.g.pairup_peripheral_indicator or ''

      -- If both active, use green (LOCAL takes precedence for color)
      -- If only peripheral, use blue
      if periph_ind ~= '' and local_ind == '' then
        return { fg = '#8be9fd', bold = true } -- Blue for PERIPHERAL only
      else
        return { fg = '#50fa7b', bold = true } -- Green for LOCAL or both
      end
    end

  local suspended_color = options.suspended_color or { fg = '#ff5555' }

  options.color = function()
    return vim.g.pairup_suspended and suspended_color or default_color()
  end

  M.super.init(self, options)
end

function M:update_status()
  local indicator = require('pairup.utils.indicator')
  local local_ind = indicator.get()
  local periph_ind = indicator.get_peripheral()
  local sep = vim.g.pairup_statusline_separator or '|'

  local local_hl = vim.g.pairup_suspended and 'PairSuspendedIndicator' or 'PairLocalIndicator'

  -- Build display with color codes
  if local_ind ~= '' and periph_ind ~= '' then
    -- Both active: LOCAL (red if suspended, green otherwise) | gray sep | blue PERIPHERAL
    return string.format(
      '%%#%s#%s%%* %%#PairSeparator#%s%%* %%#PairPeripheralIndicator#%s%%*',
      local_hl,
      local_ind,
      sep,
      periph_ind
    )
  elseif local_ind ~= '' then
    -- Only LOCAL: red if suspended, green otherwise
    return string.format('%%#%s#%s%%*', local_hl, local_ind)
  elseif periph_ind ~= '' then
    -- Only PERIPHERAL: blue
    return string.format('%%#PairPeripheralIndicator#%s%%*', periph_ind)
  else
    return ''
  end
end

return M
