-- Operator for wrapping text in cc: markers
-- Usage: gC{motion} or gC in visual mode

local M = {}

local config = require('pairup.config')

---Get the cc: marker from config
---@return string
local function get_marker()
  return config.get('inline.cc_marker') or 'cc:'
end

---Get text from range
---@param start_line integer 1-indexed
---@param start_col integer 0-indexed
---@param end_line integer 1-indexed
---@param end_col integer 0-indexed
---@return string
local function get_text(start_line, start_col, end_line, end_col)
  local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
  if #lines == 0 then
    return ''
  end
  if #lines == 1 then
    return lines[1]:sub(start_col + 1, end_col + 1)
  end
  lines[1] = lines[1]:sub(start_col + 1)
  lines[#lines] = lines[#lines]:sub(1, end_col + 1)
  return table.concat(lines, '\n')
end

---Get comment prefix for current buffer
---@return string prefix, string suffix
local function get_comment_parts()
  local cs = vim.bo.commentstring
  if not cs or cs == '' then
    return '', ''
  end
  -- commentstring is like "// %s" or "/* %s */"
  local prefix, suffix = cs:match('^(.-)%%s(.-)$')
  return (prefix or ''):gsub('%s+$', ''), (suffix or ''):gsub('^%s+', '')
end

---Insert cc: marker with context (as a comment)
---@param start_line integer 1-indexed start line
---@param context string|nil Selected text as context
function M.insert_marker(start_line, context)
  local marker = get_marker()
  local bufnr = vim.api.nvim_get_current_buf()
  local prefix, suffix = get_comment_parts()

  -- Build marker content: "cc: " + context (always space after colon)
  local marker_content
  if context and context ~= '' then
    local clean_context = context:gsub('\n', ' '):gsub('%s+', ' ')
    marker_content = marker .. ' ' .. clean_context
  else
    -- Ensure space after marker for cursor positioning
    marker_content = marker .. ' '
  end

  -- Wrap in comment syntax
  local marker_text
  if prefix ~= '' then
    if suffix ~= '' then
      marker_text = prefix .. ' ' .. marker_content .. ' ' .. suffix
    else
      marker_text = prefix .. ' ' .. marker_content
    end
  else
    marker_text = marker_content
  end

  -- Insert marker above the range
  vim.api.nvim_buf_set_lines(bufnr, start_line - 1, start_line - 1, false, { marker_text })

  -- Position cursor after "// cc: " or similar for typing instructions
  local cursor_col = #prefix + (prefix ~= '' and 1 or 0) + #marker + 1
  vim.api.nvim_win_set_cursor(0, { start_line, cursor_col })
  vim.cmd('startinsert')
end

---Operatorfunc for gC motion (no context - just line marker)
---@param type string 'line', 'char', or 'block'
function M.operatorfunc(type)
  local start_line = vim.fn.line("'[")
  M.insert_marker(start_line, nil)
end

---Wrap lines in cc: marker (legacy, for direct calls)
---@param start_line integer 1-indexed start line
---@param end_line integer 1-indexed end line
---@param prompt string|nil Optional prompt text
function M.wrap_lines(start_line, end_line, prompt)
  M.insert_marker(start_line, prompt)
end

---Setup the gC operator
---@param opts table|nil Options (key: string to override default 'gC')
function M.setup(opts)
  opts = opts or {}
  local key = opts.key or 'gC'

  -- Normal mode: gC{motion}
  vim.keymap.set('n', key, function()
    vim.o.operatorfunc = "v:lua.require'pairup.operator'.operatorfunc"
    return 'g@'
  end, { expr = true, desc = 'Pairup: wrap in cc: marker' })

  -- Visual mode: gC wraps selection with context
  vim.keymap.set('x', key, function()
    -- Get visual selection range
    local start_pos = vim.fn.getpos('v')
    local end_pos = vim.fn.getpos('.')
    local start_line, start_col = start_pos[2], start_pos[3] - 1
    local end_line, end_col = end_pos[2], end_pos[3] - 1

    -- Ensure start <= end
    if start_line > end_line or (start_line == end_line and start_col > end_col) then
      start_line, end_line = end_line, start_line
      start_col, end_col = end_col, start_col
    end

    -- Get selected text before exiting visual mode
    local context = get_text(start_line, start_col, end_line, end_col)

    -- Exit visual mode
    vim.cmd('normal! ' .. vim.api.nvim_replace_termcodes('<Esc>', true, false, true))

    M.insert_marker(start_line, context)
  end, { desc = 'Pairup: wrap selection in cc: marker' })

  -- Line-wise: gCC wraps current line (like gcc for comments)
  vim.keymap.set('n', key .. key:sub(-1), function()
    local line = vim.fn.line('.')
    M.wrap_lines(line, line)
  end, { desc = 'Pairup: wrap line in cc: marker' })
end

return M
