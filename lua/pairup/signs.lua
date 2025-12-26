-- Signs and highlighting for cc:/uu: markers

local M = {}

local config = require('pairup.config')

local sign_group = 'pairup_markers'
local hl_ns = vim.api.nvim_create_namespace('pairup_highlight')
local draft_ns = vim.api.nvim_create_namespace('pairup_drafts')

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

  -- Draft overlay highlight groups (adapted from legacy-v3)
  vim.api.nvim_set_hl(0, 'PairupHeader', { link = 'DiagnosticInfo', default = true })
  vim.api.nvim_set_hl(0, 'PairupSubHeader', { link = 'Comment', default = true })
  vim.api.nvim_set_hl(0, 'PairupBorder', { link = 'NonText', default = true })
  vim.api.nvim_set_hl(0, 'PairupDelete', { link = 'DiffDelete', default = true })
  vim.api.nvim_set_hl(0, 'PairupAdd', { link = 'DiffAdd', default = true })
  vim.api.nvim_set_hl(0, 'PairupHint', { link = 'Comment', default = true })
  vim.api.nvim_set_hl(0, 'PairupAcceptKey', { link = 'String', default = true })
  vim.api.nvim_set_hl(0, 'PairupRejectKey', { link = 'Error', default = true })

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

  vim.fn.sign_define('PairupDraft', {
    text = '󰄲',
    texthl = 'DiagnosticOk',
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

---Place sign and highlight for a marker
---@param bufnr integer
---@param lnum integer
---@param line string
---@param is_question boolean
local function place_marker(bufnr, lnum, line, is_question)
  local sign = is_question and 'PairupUU' or 'PairupCC'
  local hl = is_question and 'PairupMarkerUU' or 'PairupMarkerCC'
  vim.fn.sign_place(0, sign_group, sign, bufnr, { lnum = lnum, priority = 10 })
  vim.api.nvim_buf_set_extmark(bufnr, hl_ns, lnum - 1, 0, { end_col = #line, hl_group = hl })
end

---Find where old_string matches in buffer content
---@param bufnr integer
---@param old_string string
---@return integer|nil start_line, integer|nil start_col
local function find_text_position(bufnr, old_string)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local old_lines = vim.split(old_string, '\n', { plain = true })

  -- Try to find exact multi-line match
  for start_lnum = 1, #lines - #old_lines + 1 do
    local matches = true
    for i, old_line in ipairs(old_lines) do
      if lines[start_lnum + i - 1] ~= old_line then
        matches = false
        break
      end
    end
    if matches then
      return start_lnum, 0
    end
  end

  return nil, nil
end

---Get draft positions for a file (line numbers where drafts start)
---@param filepath string
---@param bufnr integer
---@return table<integer, boolean> Map of line numbers with drafts
local function get_draft_positions(filepath, bufnr)
  local drafts = require('pairup.drafts')
  local all = drafts.get_all()
  local positions = {}

  for _, draft in ipairs(all) do
    if draft.file == filepath and draft.old_string then
      local lnum, col = find_text_position(bufnr, draft.old_string)
      if lnum then
        positions[lnum] = true
      end
    end
  end

  return positions
end

---Update signs for a buffer
---@param bufnr integer|nil Buffer number (defaults to current)
function M.update(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if vim.bo[bufnr].buftype ~= '' then
    return
  end

  vim.fn.sign_unplace(sign_group, { buffer = bufnr })
  vim.api.nvim_buf_clear_namespace(bufnr, hl_ns, 0, -1)
  vim.api.nvim_buf_clear_namespace(bufnr, draft_ns, 0, -1)

  local filepath = vim.api.nvim_buf_get_name(bufnr)
  local draft_positions = get_draft_positions(filepath, bufnr)

  -- Markers sorted by length (longest first to match ccp: before cc:)
  local markers = {
    { pattern = config.get('inline.markers.plan') or 'ccp:', is_question = false },
    { pattern = config.get('inline.markers.constitution') or 'cc!:', is_question = false },
    { pattern = config.get('inline.markers.command') or 'cc:', is_question = false },
    { pattern = config.get('inline.markers.question') or 'uu:', is_question = true },
  }

  for lnum, line in ipairs(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)) do
    if draft_positions[lnum] then
      vim.api.nvim_buf_set_extmark(bufnr, draft_ns, lnum - 1, 0, {
        sign_text = '󰄲',
        sign_hl_group = 'DiagnosticOk',
        priority = 11,
      })
    end
    for _, m in ipairs(markers) do
      if line:find(m.pattern, 1, true) then
        place_marker(bufnr, lnum, line, m.is_question)
        break
      end
    end
  end
end

---Clear all signs and highlights in a buffer
---@param bufnr integer|nil Buffer number (defaults to current)
function M.clear(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  vim.fn.sign_unplace(sign_group, { buffer = bufnr })
  vim.api.nvim_buf_clear_namespace(bufnr, hl_ns, 0, -1)
  vim.api.nvim_buf_clear_namespace(bufnr, draft_ns, 0, -1)
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
