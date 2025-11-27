-- Signs for cc:/uu: markers in gutter

local M = {}

local config = require('pairup.config')

local sign_group = 'pairup_markers'

---Setup sign definitions
function M.setup()
  -- Define signs
  vim.fn.sign_define('PairupCC', {
    text = '󰭻',
    texthl = 'DiagnosticWarn',
    numhl = '',
  })

  vim.fn.sign_define('PairupUU', {
    text = '󰞋',
    texthl = 'DiagnosticInfo',
    numhl = '',
  })

  -- Setup autocmd to update signs
  vim.api.nvim_create_autocmd({ 'BufEnter', 'BufWritePost', 'TextChanged', 'TextChangedI' }, {
    group = vim.api.nvim_create_augroup('PairupSigns', { clear = true }),
    pattern = '*',
    callback = function(ev)
      -- Debounce for TextChanged events
      if ev.event == 'TextChanged' or ev.event == 'TextChangedI' then
        vim.defer_fn(function()
          if vim.api.nvim_buf_is_valid(ev.buf) then
            M.update(ev.buf)
          end
        end, 100)
      else
        M.update(ev.buf)
      end
    end,
  })
end

---Update signs for a buffer
---@param bufnr integer|nil Buffer number (defaults to current)
function M.update(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  -- Skip non-file buffers
  local buftype = vim.bo[bufnr].buftype
  if buftype ~= '' then
    return
  end

  -- Clear existing signs
  vim.fn.sign_unplace(sign_group, { buffer = bufnr })

  -- Get markers from config
  local cc_marker = config.get('inline.cc_marker') or 'cc:'
  local uu_marker = config.get('inline.uu_marker') or 'uu:'

  -- Get buffer lines
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  -- Find markers and place signs
  for lnum, line in ipairs(lines) do
    if line:match('^%s*' .. vim.pesc(cc_marker)) then
      vim.fn.sign_place(0, sign_group, 'PairupCC', bufnr, { lnum = lnum, priority = 10 })
    elseif line:match('^%s*' .. vim.pesc(uu_marker)) then
      vim.fn.sign_place(0, sign_group, 'PairupUU', bufnr, { lnum = lnum, priority = 10 })
    end
  end
end

---Clear all signs in a buffer
---@param bufnr integer|nil Buffer number (defaults to current)
function M.clear(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  vim.fn.sign_unplace(sign_group, { buffer = bufnr })
end

return M
