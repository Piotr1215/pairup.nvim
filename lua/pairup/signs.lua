-- Signs and highlighting for cc:/uu: markers

local M = {}

local config = require('pairup.config')

local sign_group = 'pairup_markers'
local hl_ns = vim.api.nvim_create_namespace('pairup_highlight')

---Setup sign definitions
function M.setup()
  -- Define highlight groups for markers (respects light/dark background)
  -- Users can override these in their colorscheme with:
  --   vim.api.nvim_set_hl(0, 'PairupMarkerCC', { ... })
  --   vim.api.nvim_set_hl(0, 'PairupMarkerUU', { ... })
  local is_light = vim.o.background == 'light'

  -- Only set defaults if user hasn't defined them
  local cc_hl = vim.api.nvim_get_hl(0, { name = 'PairupMarkerCC' })
  if vim.tbl_isempty(cc_hl) then
    vim.api.nvim_set_hl(0, 'PairupMarkerCC', {
      bg = is_light and '#fff3cd' or '#3d3200', -- yellow/orange for cc:
    })
  end

  local uu_hl = vim.api.nvim_get_hl(0, { name = 'PairupMarkerUU' })
  if vim.tbl_isempty(uu_hl) then
    vim.api.nvim_set_hl(0, 'PairupMarkerUU', {
      bg = is_light and '#cfe2ff' or '#1a3a4a', -- blue for uu:
    })
  end

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

  -- Setup autocmd to update signs (only when pairup is running)
  vim.api.nvim_create_autocmd({ 'BufEnter', 'BufWritePost', 'TextChanged', 'TextChangedI' }, {
    group = vim.api.nvim_create_augroup('PairupSigns', { clear = true }),
    pattern = '*',
    callback = function(ev)
      local ok, providers = pcall(require, 'pairup.providers')
      if not ok or not providers.is_running or not providers.is_running() then
        return
      end

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

  -- Clear existing signs and highlights
  vim.fn.sign_unplace(sign_group, { buffer = bufnr })
  vim.api.nvim_buf_clear_namespace(bufnr, hl_ns, 0, -1)

  -- Get markers from config
  local cc_marker = config.get('inline.markers.command') or 'cc:'
  local uu_marker = config.get('inline.markers.question') or 'uu:'
  local const_marker = config.get('inline.markers.constitution') or 'cc!:'
  local plan_marker = config.get('inline.markers.plan') or 'ccp:'

  -- Get buffer lines
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  -- Find markers, place signs, and highlight
  -- Check longer patterns first (plan, constitution before command)
  for lnum, line in ipairs(lines) do
    local uu_start = line:find(uu_marker, 1, true)
    local plan_start = line:find(plan_marker, 1, true)
    local const_start = line:find(const_marker, 1, true)
    local cc_start = line:find(cc_marker, 1, true)

    if uu_start then
      vim.fn.sign_place(0, sign_group, 'PairupUU', bufnr, { lnum = lnum, priority = 10 })
      vim.api.nvim_buf_set_extmark(bufnr, hl_ns, lnum - 1, 0, {
        end_col = #line,
        hl_group = 'PairupMarkerUU',
      })
    elseif plan_start then
      -- Plan uses CC sign (it's a command variant)
      vim.fn.sign_place(0, sign_group, 'PairupCC', bufnr, { lnum = lnum, priority = 10 })
      vim.api.nvim_buf_set_extmark(bufnr, hl_ns, lnum - 1, 0, {
        end_col = #line,
        hl_group = 'PairupMarkerCC',
      })
    elseif const_start then
      -- Constitution uses CC sign (it's a command variant)
      vim.fn.sign_place(0, sign_group, 'PairupCC', bufnr, { lnum = lnum, priority = 10 })
      vim.api.nvim_buf_set_extmark(bufnr, hl_ns, lnum - 1, 0, {
        end_col = #line,
        hl_group = 'PairupMarkerCC',
      })
    elseif cc_start then
      vim.fn.sign_place(0, sign_group, 'PairupCC', bufnr, { lnum = lnum, priority = 10 })
      vim.api.nvim_buf_set_extmark(bufnr, hl_ns, lnum - 1, 0, {
        end_col = #line,
        hl_group = 'PairupMarkerCC',
      })
    end
  end
end

---Clear all signs and highlights in a buffer
---@param bufnr integer|nil Buffer number (defaults to current)
function M.clear(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  vim.fn.sign_unplace(sign_group, { buffer = bufnr })
  vim.api.nvim_buf_clear_namespace(bufnr, hl_ns, 0, -1)
end

---Clear signs and highlights from all buffers
function M.clear_all()
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(bufnr) then
      M.clear(bufnr)
    end
  end
end

---Get all command marker line numbers in buffer (command + constitution + plan)
---@param bufnr integer|nil Buffer number (defaults to current)
---@return integer[] Line numbers (1-indexed)
function M.get_marker_lines(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local cc_marker = config.get('inline.markers.command') or 'cc:'
  local const_marker = config.get('inline.markers.constitution') or 'cc!:'
  local plan_marker = config.get('inline.markers.plan') or 'ccp:'
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local markers = {}
  for lnum, line in ipairs(lines) do
    if line:find(plan_marker, 1, true) or line:find(const_marker, 1, true) or line:find(cc_marker, 1, true) then
      table.insert(markers, lnum)
    end
  end
  return markers
end

---Jump to next cc: marker
function M.next()
  local cursor = vim.api.nvim_win_get_cursor(0)[1]
  local markers = M.get_marker_lines()
  for _, lnum in ipairs(markers) do
    if lnum > cursor then
      vim.api.nvim_win_set_cursor(0, { lnum, 0 })
      return
    end
  end
  -- Wrap to first marker
  if #markers > 0 then
    vim.api.nvim_win_set_cursor(0, { markers[1], 0 })
  end
end

---Jump to previous cc: marker
function M.prev()
  local cursor = vim.api.nvim_win_get_cursor(0)[1]
  local markers = M.get_marker_lines()
  for i = #markers, 1, -1 do
    if markers[i] < cursor then
      vim.api.nvim_win_set_cursor(0, { markers[i], 0 })
      return
    end
  end
  -- Wrap to last marker
  if #markers > 0 then
    vim.api.nvim_win_set_cursor(0, { markers[#markers], 0 })
  end
end

return M
