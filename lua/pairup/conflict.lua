-- Conflict marker resolution
local M = {}

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
  return { start_marker = start_marker, separator = separator, end_marker = end_marker, in_current = in_current }
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
end

return M
