-- Conflict marker resolution
local M = {}

-- Store diff context for accepting from diff view
M._diff_ctx = nil

-- Scope state for conflict navigation
M._scope = {
  buf = nil,
  win = nil,
  source_buf = nil,
  source_win = nil,
  conflicts = {},
  line_to_conflict = {},
  ns = vim.api.nvim_create_namespace('pairup_conflict_scope'),
}

---Find conflict block at cursor and determine which section cursor is in
---@return table|nil {start_marker, separator, end_marker, in_current}
function M.find_block()
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)[1]
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  -- Search backwards for <<<<<<<
  local start_marker = nil
  for i = cursor, 1, -1 do
    if lines[i]:match('^<<<<<<<') then
      start_marker = i
      break
    end
    if lines[i]:match('^>>>>>>>') then
      break
    end
  end

  if not start_marker then
    return nil
  end

  -- Find ======= and >>>>>>>
  local separator, end_marker = nil, nil
  for i = start_marker + 1, #lines do
    if not separator and lines[i]:match('^=======') then
      separator = i
    elseif separator and lines[i]:match('^>>>>>>>') then
      end_marker = i
      break
    end
  end

  if not separator or not end_marker then
    return nil
  end

  local in_current = cursor > start_marker and cursor < separator
  local reason = lines[end_marker]:match('^>>>>>>> PROPOSED:%s*(.*)$') or ''
  return {
    start_marker = start_marker,
    separator = separator,
    end_marker = end_marker,
    in_current = in_current,
    reason = reason,
  }
end

---Accept section at cursor (CURRENT or PROPOSED based on cursor position)
function M.accept()
  local block = M.find_block()
  if not block then
    vim.notify('No conflict block at cursor', vim.log.levels.WARN)
    return
  end

  local bufnr = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local new_lines = {}

  if block.in_current then
    for i = block.start_marker + 1, block.separator - 1 do
      table.insert(new_lines, lines[i])
    end
  else
    for i = block.separator + 1, block.end_marker - 1 do
      table.insert(new_lines, lines[i])
    end
  end

  vim.api.nvim_buf_set_lines(bufnr, block.start_marker - 1, block.end_marker, false, new_lines)

  -- Position cursor on first line of accepted content
  local target_line = block.start_marker
  if target_line > vim.api.nvim_buf_line_count(bufnr) then
    target_line = vim.api.nvim_buf_line_count(bufnr)
  end
  vim.api.nvim_win_set_cursor(0, { target_line, 0 })
end

---Accept from diff view (use_current: true=CURRENT, false=PROPOSED)
---@param use_current boolean
function M.accept_from_diff(use_current)
  local ctx = M._diff_ctx
  if not ctx then
    vim.notify('No diff context', vim.log.levels.WARN)
    return
  end

  local new_lines = use_current and ctx.current_lines or ctx.proposed_lines
  vim.api.nvim_buf_set_lines(ctx.bufnr, ctx.block.start_marker - 1, ctx.block.end_marker, false, new_lines)

  vim.cmd('tabclose')
  vim.api.nvim_set_current_buf(ctx.bufnr)
  vim.api.nvim_win_set_cursor(0, { ctx.block.start_marker, 0 })
  M._diff_ctx = nil
end

---Show conflict as diff in split view
function M.diff()
  local block = M.find_block()
  if not block then
    vim.notify('No conflict block at cursor', vim.log.levels.WARN)
    return
  end

  local bufnr = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local ft = vim.bo[bufnr].filetype

  local current_lines, proposed_lines = {}, {}
  for i = block.start_marker + 1, block.separator - 1 do
    table.insert(current_lines, lines[i])
  end
  for i = block.separator + 1, block.end_marker - 1 do
    table.insert(proposed_lines, lines[i])
  end

  M._diff_ctx = { bufnr = bufnr, block = block, current_lines = current_lines, proposed_lines = proposed_lines }

  local current_buf = vim.api.nvim_create_buf(false, true)
  local proposed_buf = vim.api.nvim_create_buf(false, true)

  vim.api.nvim_buf_set_lines(current_buf, 0, -1, false, current_lines)
  vim.api.nvim_buf_set_lines(proposed_buf, 0, -1, false, proposed_lines)
  pcall(vim.api.nvim_buf_set_name, current_buf, 'CURRENT (ga=accept)')
  pcall(vim.api.nvim_buf_set_name, proposed_buf, 'PROPOSED (ga=accept)')
  vim.bo[current_buf].filetype = ft
  vim.bo[proposed_buf].filetype = ft

  local function set_keymaps(buf, is_current)
    vim.keymap.set('n', 'ga', function()
      M.accept_from_diff(is_current)
    end, { buffer = buf, desc = 'Accept this side' })
    vim.keymap.set('n', 'q', function()
      M._diff_ctx = nil
      vim.cmd('tabclose')
    end, { buffer = buf, desc = 'Close diff' })
  end

  set_keymaps(current_buf, true)
  set_keymaps(proposed_buf, false)

  vim.cmd('tabnew')
  vim.api.nvim_set_current_buf(current_buf)
  vim.cmd('diffthis')
  vim.cmd('vsplit')
  vim.api.nvim_set_current_buf(proposed_buf)
  vim.cmd('diffthis')
end

---Find all conflict blocks in buffer
---@param bufnr number
---@return table[] List of {start_marker, separator, end_marker, preview}
function M.find_all(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local conflicts = {}
  local i = 1
  while i <= #lines do
    if lines[i]:match('^<<<<<<<') then
      local start_marker = i
      local separator, end_marker = nil, nil
      for j = i + 1, #lines do
        if not separator and lines[j]:match('^=======') then
          separator = j
        elseif separator and lines[j]:match('^>>>>>>>') then
          end_marker = j
          break
        end
      end
      if separator and end_marker then
        local reason = lines[end_marker]:match('^>>>>>>> PROPOSED:%s*(.*)$') or ''
        local preview = reason ~= '' and reason or (lines[start_marker + 1] or '')
        if #preview > 50 then
          preview = preview:sub(1, 47) .. '...'
        end
        table.insert(conflicts, {
          start_marker = start_marker,
          separator = separator,
          end_marker = end_marker,
          reason = reason,
          preview = preview,
        })
        i = end_marker
      end
    end
    i = i + 1
  end
  return conflicts
end

---Update preview when cursor moves in scope window
local function update_scope_preview(line)
  local s = M._scope
  local idx = s.line_to_conflict[line]
  if not idx or not s.conflicts[idx] then
    return
  end
  local conflict = s.conflicts[idx]
  if not vim.api.nvim_win_is_valid(s.source_win) then
    return
  end
  vim.api.nvim_win_set_cursor(s.source_win, { conflict.start_marker, 0 })
  vim.api.nvim_win_call(s.source_win, function()
    vim.cmd('normal! zz')
  end)
  -- Highlight conflict block
  vim.api.nvim_buf_clear_namespace(s.source_buf, s.ns, 0, -1)
  for i = conflict.start_marker, conflict.end_marker do
    vim.api.nvim_buf_add_highlight(s.source_buf, s.ns, 'Visual', i - 1, 0, -1)
  end
end

---Navigate to next/prev conflict in scope
---@param direction number 1 for next, -1 for prev
function M.scope_navigate(direction)
  local s = M._scope
  if not s.buf or not vim.api.nvim_buf_is_valid(s.buf) then
    return
  end
  local line = vim.api.nvim_win_get_cursor(0)[1]
  local idx = s.line_to_conflict[line] or 1
  idx = idx + direction
  if idx < 1 then
    idx = #s.conflicts
  elseif idx > #s.conflicts then
    idx = 1
  end
  -- Find line for this conflict
  for l, i in pairs(s.line_to_conflict) do
    if i == idx then
      vim.api.nvim_win_set_cursor(0, { l, 0 })
      update_scope_preview(l)
      break
    end
  end
end

---Jump to suggestion and close scope
function M.scope_jump()
  local s = M._scope
  local line = vim.api.nvim_win_get_cursor(0)[1]
  local idx = s.line_to_conflict[line]
  if not idx or not s.conflicts[idx] then
    return
  end
  local conflict = s.conflicts[idx]
  local target_line = conflict.start_marker
  M.scope_close()
  vim.api.nvim_win_set_cursor(0, { target_line, 0 })
  vim.cmd('normal! zz')
end

---Show diff view for conflict at cursor
function M.scope_diff()
  local s = M._scope
  local line = vim.api.nvim_win_get_cursor(0)[1]
  local idx = s.line_to_conflict[line]
  if not idx or not s.conflicts[idx] then
    return
  end
  local conflict = s.conflicts[idx]
  vim.api.nvim_set_current_win(s.source_win)
  vim.api.nvim_win_set_cursor(s.source_win, { conflict.start_marker, 0 })
  M.scope_close()
  M.diff()
end

---Close scope window
function M.scope_close()
  local s = M._scope
  if s.buf and vim.api.nvim_buf_is_valid(s.buf) then
    vim.api.nvim_buf_delete(s.buf, { force = true })
  end
  if s.source_buf then
    vim.api.nvim_buf_clear_namespace(s.source_buf, s.ns, 0, -1)
  end
  s.buf, s.win, s.source_buf, s.source_win = nil, nil, nil, nil
  s.conflicts, s.line_to_conflict = {}, {}
end

---Open scope window showing all conflicts
function M.scope()
  local source_buf = vim.api.nvim_get_current_buf()
  local source_win = vim.api.nvim_get_current_win()
  local conflicts = M.find_all(source_buf)

  if #conflicts == 0 then
    vim.notify('No suggestions found', vim.log.levels.INFO)
    M.scope_close()
    return
  end

  -- Close existing scope
  if M._scope.buf and vim.api.nvim_buf_is_valid(M._scope.buf) then
    vim.api.nvim_buf_delete(M._scope.buf, { force = true })
  end

  -- Create scope buffer
  local scope_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[scope_buf].buftype = 'nofile'
  vim.bo[scope_buf].bufhidden = 'wipe'
  vim.bo[scope_buf].swapfile = false

  -- Build content with full suggestion display
  local lines = vim.api.nvim_buf_get_lines(source_buf, 0, -1, false)
  local ft = vim.bo[source_buf].filetype
  local content = { '  Suggestions (' .. #conflicts .. ')', '' }
  local line_to_conflict = {}
  for i, c in ipairs(conflicts) do
    table.insert(content, string.format('── %d. Line %d ──', i, c.start_marker))
    line_to_conflict[#content] = i
    for j = c.start_marker, c.end_marker do
      table.insert(content, '  ' .. (lines[j] or ''))
      line_to_conflict[#content] = i
    end
    table.insert(content, '')
  end
  table.insert(content, '  <CR> jump  g diff  q close')

  vim.api.nvim_buf_set_lines(scope_buf, 0, -1, false, content)
  vim.bo[scope_buf].filetype = ft
  vim.bo[scope_buf].modifiable = false

  -- Open window
  vim.cmd('topleft 40vsplit')
  local scope_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(scope_win, scope_buf)
  vim.wo[scope_win].number = false
  vim.wo[scope_win].relativenumber = false
  vim.wo[scope_win].signcolumn = 'no'
  vim.wo[scope_win].cursorline = true

  -- Store state
  M._scope.buf = scope_buf
  M._scope.win = scope_win
  M._scope.source_buf = source_buf
  M._scope.source_win = source_win
  M._scope.conflicts = conflicts
  M._scope.line_to_conflict = line_to_conflict

  -- Keymaps
  local opts = { buffer = scope_buf, nowait = true }
  vim.keymap.set('n', '<C-n>', function()
    M.scope_navigate(1)
  end, opts)
  vim.keymap.set('n', '<C-p>', function()
    M.scope_navigate(-1)
  end, opts)
  vim.keymap.set('n', '<CR>', M.scope_jump, opts)
  vim.keymap.set('n', 'g', M.scope_diff, opts)
  vim.keymap.set('n', 'q', M.scope_close, opts)

  -- CursorMoved autocmd for preview
  vim.api.nvim_create_autocmd('CursorMoved', {
    buffer = scope_buf,
    callback = function()
      update_scope_preview(vim.api.nvim_win_get_cursor(0)[1])
    end,
  })

  -- Position on first conflict
  vim.api.nvim_win_set_cursor(scope_win, { 3, 0 })
  update_scope_preview(3)
end

return M
