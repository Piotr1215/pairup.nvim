-- Conflict marker resolution
local M = {}

-- Store diff context for accepting from diff view
M._diff_ctx = nil

-- Pattern prefix to match optional comment chars (supports --, #, //)
local COMMENT_PAT = '^[%-#/]*%s*'

---Find conflict block at cursor and determine which section cursor is in
---@return table|nil {start_marker, separator, end_marker, in_current}
function M.find_block()
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)[1]
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  -- Search backwards for <<<<<<<
  local start_marker = nil
  for i = cursor, 1, -1 do
    if lines[i]:match(COMMENT_PAT .. '<<<<<<<') then
      start_marker = i
      break
    end
    if lines[i]:match(COMMENT_PAT .. '>>>>>>>') then
      break
    end
  end

  if not start_marker then
    return nil
  end

  -- Find ======= and >>>>>>>
  local separator, end_marker = nil, nil
  for i = start_marker + 1, #lines do
    if not separator and lines[i]:match(COMMENT_PAT .. '=======') then
      separator = i
    elseif separator and lines[i]:match(COMMENT_PAT .. '>>>>>>>') then
      end_marker = i
      break
    end
  end

  if not separator or not end_marker then
    return nil
  end

  local in_current = cursor > start_marker and cursor < separator
  local reason = lines[end_marker]:match('>>>>>>> PROPOSED:%s*(.*)$') or ''
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
  pcall(vim.api.nvim_buf_set_name, current_buf, 'CURRENT (ga=accept, ge=edit)')
  pcall(vim.api.nvim_buf_set_name, proposed_buf, 'PROPOSED (ga=accept, ge=edit)')
  vim.bo[current_buf].filetype = ft
  vim.bo[proposed_buf].filetype = ft

  local function set_keymaps(buf, is_current)
    vim.keymap.set('n', 'ga', function()
      M.accept_from_diff(is_current)
    end, { buffer = buf, desc = 'Accept this side' })
    vim.keymap.set('n', 'ge', function()
      M.to_edit()
    end, { buffer = buf, desc = 'Switch to edit mode' })
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

  -- Better diff display with patience algorithm for cleaner results
  vim.cmd('set diffopt+=algorithm:patience,indent-heuristic')
end

---Find all conflict blocks in buffer
---@param bufnr number
---@return table[] List of {start_marker, separator, end_marker, preview}
function M.find_all(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local conflicts = {}
  local i = 1
  while i <= #lines do
    if lines[i]:match(COMMENT_PAT .. '<<<<<<<') then
      local start_marker = i
      local separator, end_marker = nil, nil
      for j = i + 1, #lines do
        if not separator and lines[j]:match(COMMENT_PAT .. '=======') then
          separator = j
        elseif separator and lines[j]:match(COMMENT_PAT .. '>>>>>>>') then
          end_marker = j
          break
        end
      end
      if separator and end_marker then
        local reason = lines[end_marker]:match('>>>>>>> PROPOSED:%s*(.*)$') or ''
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

---Jump to next proposal block
function M.next()
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)[1]
  local conflicts = M.find_all(bufnr)

  for _, c in ipairs(conflicts) do
    if c.start_marker > cursor then
      vim.api.nvim_win_set_cursor(0, { c.start_marker, 0 })
      vim.cmd('normal! zz')
      return
    end
  end

  -- Wrap around to first
  if #conflicts > 0 then
    vim.api.nvim_win_set_cursor(0, { conflicts[1].start_marker, 0 })
    vim.cmd('normal! zz')
  end
end

---Jump to previous proposal block
function M.prev()
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)[1]
  local conflicts = M.find_all(bufnr)

  for i = #conflicts, 1, -1 do
    local c = conflicts[i]
    if c.end_marker < cursor then
      vim.api.nvim_win_set_cursor(0, { c.start_marker, 0 })
      vim.cmd('normal! zz')
      return
    end
  end

  -- Wrap around to last
  if #conflicts > 0 then
    vim.api.nvim_win_set_cursor(0, { conflicts[#conflicts].start_marker, 0 })
    vim.cmd('normal! zz')
  end
end

---Switch from diff view to edit mode
function M.to_edit()
  local ctx = M._diff_ctx
  if not ctx then
    vim.notify('No diff context', vim.log.levels.WARN)
    return
  end

  -- Close diff tab and return to source
  vim.cmd('tabclose')
  vim.api.nvim_set_current_buf(ctx.bufnr)
  vim.api.nvim_win_set_cursor(0, { ctx.block.start_marker, 0 })
  M._diff_ctx = nil

  -- Open edit mode
  require('pairup.edit').enter()
end

return M
