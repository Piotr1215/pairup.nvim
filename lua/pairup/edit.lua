-- Floating editor for proposal blocks (FeMaco-inspired)
local M = {}

local conflict = require('pairup.conflict')

-- Float state
M._state = {
  buf = nil,
  win = nil,
  backdrop_buf = nil,
  backdrop_win = nil,
  source_buf = nil,
  source_win = nil,
  block = nil,
  proposed_range = nil, -- {start, end} lines in source buffer
}

---Create backdrop window for dimming effect
---@return number buf, number win
local function create_backdrop()
  -- Ensure highlight group exists
  if vim.fn.hlexists('PairupBackdrop') == 0 then
    vim.api.nvim_set_hl(0, 'PairupBackdrop', { bg = '#000000', default = true })
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'

  local win = vim.api.nvim_open_win(buf, false, {
    relative = 'editor',
    width = vim.o.columns,
    height = vim.o.lines,
    row = 0,
    col = 0,
    style = 'minimal',
    focusable = false,
    zindex = 40, -- Below edit float (50)
  })
  vim.wo[win].winblend = 60 -- 60% transparent
  vim.wo[win].winhighlight = 'Normal:PairupBackdrop'

  return buf, win
end

---Calculate float dimensions and position
---@param lines string[]
---@param footer_count number number of footer virtual lines
---@return table opts for nvim_open_win
local function float_opts(lines, footer_count)
  local width = math.floor(vim.o.columns * 0.9)

  local visual_lines = 0
  for _, line in ipairs(lines) do
    visual_lines = visual_lines + math.max(1, math.ceil(#line / (width - 4)))
  end

  -- +2 header (CURRENT + empty), +1 footer empty, +footer_count, +2 breathing room
  local height = visual_lines + 5 + footer_count
  height = math.min(height, vim.o.lines - 4)

  return {
    relative = 'cursor',
    width = width,
    height = height,
    anchor = 'NW',
    row = 2,
    col = 0,
    style = 'minimal',
    border = 'rounded',
    zindex = 50,
    title = ' Edit Proposal ',
    title_pos = 'center',
  }
end

---Build floating buffer content (only editable PROPOSED lines)
---@param block table from conflict.find_block()
---@param source_lines string[]
---@return string[] content
local function build_content(block, source_lines)
  local content = {}
  for i = block.separator + 1, block.end_marker - 1 do
    table.insert(content, source_lines[i] or '')
  end
  return content
end

---Build virtual text for header and footer
---@param block table from conflict.find_block()
---@param source_lines string[]
---@return string header_text, string[] footer_lines
local function build_virtual_text(block, source_lines)
  -- Header: CURRENT info
  local current_preview = source_lines[block.start_marker + 1] or ''
  if #current_preview > 60 then
    current_preview = current_preview:sub(1, 57) .. '...'
  end
  local current_count = block.separator - block.start_marker - 1
  local header = string.format('▶ CURRENT (%d lines): %s', current_count, current_preview)

  -- Footer: reason + legend
  local footer = {}
  if block.reason and block.reason ~= '' then
    table.insert(footer, '── Reason: ' .. block.reason)
  end
  table.insert(footer, '── :w save  q discard  ga accept  gd diff ──')

  return header, footer
end

---Sync float edits back to source buffer
local function sync_to_source()
  local s = M._state
  if not s.buf or not vim.api.nvim_buf_is_valid(s.buf) then
    return
  end
  if not s.source_buf or not vim.api.nvim_buf_is_valid(s.source_buf) then
    return
  end

  local new_proposed = vim.api.nvim_buf_get_lines(s.buf, 0, -1, false)
  vim.api.nvim_buf_set_lines(s.source_buf, s.block.separator, s.block.end_marker - 1, false, new_proposed)
end

---Close floating editor
function M.close()
  local s = M._state
  if s.win and vim.api.nvim_win_is_valid(s.win) then
    vim.api.nvim_win_close(s.win, true)
  end
  if s.buf and vim.api.nvim_buf_is_valid(s.buf) then
    vim.api.nvim_buf_delete(s.buf, { force = true })
  end
  if s.backdrop_win and vim.api.nvim_win_is_valid(s.backdrop_win) then
    vim.api.nvim_win_close(s.backdrop_win, true)
  end
  if s.backdrop_buf and vim.api.nvim_buf_is_valid(s.backdrop_buf) then
    vim.api.nvim_buf_delete(s.backdrop_buf, { force = true })
  end
  s.buf, s.win, s.backdrop_buf, s.backdrop_win, s.source_buf, s.source_win, s.block = nil, nil, nil, nil, nil, nil, nil
end

---Switch from edit mode to diff view
function M.to_diff()
  local s = M._state
  if not s.block then
    vim.notify('No edit context', vim.log.levels.WARN)
    return
  end

  -- Sync any changes first
  sync_to_source()

  -- Store source info before closing
  local source_buf = s.source_buf
  local block_start = s.block.start_marker

  -- Close float
  M.close()

  -- Position cursor and open diff
  if source_buf and vim.api.nvim_buf_is_valid(source_buf) then
    vim.api.nvim_set_current_buf(source_buf)
    vim.api.nvim_win_set_cursor(0, { block_start, 0 })
    conflict.diff()
  end
end

---Open floating editor for proposal at cursor
function M.enter()
  local block = conflict.find_block()
  if not block then
    vim.notify('No proposal at cursor', vim.log.levels.INFO)
    return
  end

  -- Close existing float if open
  if M._state.buf and vim.api.nvim_buf_is_valid(M._state.buf) then
    M.close()
  end

  local source_buf = vim.api.nvim_get_current_buf()
  local source_win = vim.api.nvim_get_current_win()
  local source_lines = vim.api.nvim_buf_get_lines(source_buf, 0, -1, false)
  local ft = vim.bo[source_buf].filetype

  local content = build_content(block, source_lines)
  local header, footer = build_virtual_text(block, source_lines)

  local float_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[float_buf].buftype = 'acwrite'
  vim.bo[float_buf].bufhidden = 'wipe'
  vim.bo[float_buf].swapfile = false
  vim.api.nvim_buf_set_name(float_buf, 'pairup://proposal')
  vim.api.nvim_buf_set_lines(float_buf, 0, -1, false, content)
  vim.bo[float_buf].filetype = ft

  -- Create backdrop for dimming effect
  local backdrop_buf, backdrop_win = create_backdrop()

  -- Open float window
  local opts = float_opts(content, #footer)
  local float_win = vim.api.nvim_open_win(float_buf, true, opts)
  vim.wo[float_win].winhighlight = 'Normal:Normal,NormalFloat:Normal'
  vim.wo[float_win].signcolumn = 'no'
  vim.wo[float_win].number = true
  vim.wo[float_win].relativenumber = false
  vim.wo[float_win].cursorline = true
  vim.wo[float_win].wrap = true

  M._state = {
    buf = float_buf,
    win = float_win,
    backdrop_buf = backdrop_buf,
    backdrop_win = backdrop_win,
    source_buf = source_buf,
    source_win = source_win,
    block = block,
  }

  -- Position cursor on first line and scroll to show virtual header above
  vim.api.nvim_win_set_cursor(float_win, { 1, 0 })
  -- Scroll view up to reveal virtual text above line 1 (2 lines: header + separator)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('2<C-y>', true, false, true), 'n', false)

  -- Keymaps
  local kopts = { buffer = float_buf, nowait = true }
  vim.keymap.set('n', 'q', function()
    M.close()
  end, vim.tbl_extend('force', kopts, { desc = 'Close edit float' }))

  vim.keymap.set('n', 'gd', function()
    M.to_diff()
  end, vim.tbl_extend('force', kopts, { desc = 'Switch to diff view' }))

  vim.keymap.set('n', 'ga', function()
    sync_to_source()
    -- Position cursor in PROPOSED section before accepting
    vim.api.nvim_set_current_win(source_win)
    vim.api.nvim_win_set_cursor(source_win, { block.separator + 1, 0 })
    M.close()
    conflict.accept()
  end, vim.tbl_extend('force', kopts, { desc = 'Accept proposal' }))

  -- BufWriteCmd: sync on :w
  vim.api.nvim_create_autocmd('BufWriteCmd', {
    buffer = float_buf,
    callback = function()
      sync_to_source()
      vim.bo[float_buf].modified = false
    end,
  })

  -- WinClosed: cleanup only (no sync - :q! should discard changes, use :w to save)
  vim.api.nvim_create_autocmd('WinClosed', {
    buffer = float_buf,
    callback = function()
      -- Close backdrop
      if backdrop_win and vim.api.nvim_win_is_valid(backdrop_win) then
        vim.api.nvim_win_close(backdrop_win, true)
      end
      M._state = {
        buf = nil,
        win = nil,
        backdrop_buf = nil,
        backdrop_win = nil,
        source_buf = nil,
        source_win = nil,
        block = nil,
      }
    end,
  })

  -- BufHidden: cleanup
  vim.api.nvim_create_autocmd('BufHidden', {
    buffer = float_buf,
    callback = function()
      vim.schedule(function()
        if vim.api.nvim_buf_is_loaded(float_buf) then
          vim.api.nvim_buf_delete(float_buf, { force = true })
        end
      end)
    end,
  })

  -- Add virtual text for header (above first line) and footer (below last line)
  local ns = vim.api.nvim_create_namespace('pairup_edit_virt')

  -- Header: CURRENT info as virtual line above content
  vim.api.nvim_buf_set_extmark(float_buf, ns, 0, 0, {
    virt_lines_above = true,
    virt_lines = {
      { { header, 'Comment' } },
      { { '', 'Normal' } }, -- Empty line separator
    },
  })

  -- Footer: reason and legend as virtual lines below content
  local last_line = #content - 1
  if last_line < 0 then
    last_line = 0
  end
  local footer_virt = {}
  table.insert(footer_virt, { { '', 'Normal' } }) -- Empty line separator
  for _, line in ipairs(footer) do
    table.insert(footer_virt, { { line, 'Comment' } })
  end
  vim.api.nvim_buf_set_extmark(float_buf, ns, last_line, 0, {
    virt_lines = footer_virt,
  })
end

---Check if cursor is in proposal block and auto-enter if configured
function M.maybe_auto_enter()
  -- Skip if already in float
  if M._state.buf and vim.api.nvim_buf_is_valid(M._state.buf) then
    return
  end

  -- Skip terminal buffers
  if vim.bo.buftype == 'terminal' then
    return
  end

  local block = conflict.find_block()
  if block then
    M.enter()
  end
end

return M
