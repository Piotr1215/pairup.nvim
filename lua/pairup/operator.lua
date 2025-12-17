-- Operator for wrapping text in cc: markers
-- Usage: gC{motion} or gC in visual mode

local M = {}

local config = require('pairup.config')

---Get marker from config by type
---@param marker_type? string 'command'|'constitution' (default: 'command')
---@return string
local function get_marker(marker_type)
  marker_type = marker_type or 'command'
  return config.get('inline.markers.' .. marker_type) or (marker_type == 'constitution' and 'cc!:' or 'cc:')
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
---@param scope string|nil Scope hint: 'line', 'paragraph', 'word', 'selection'
---@param marker_type? string 'command'|'constitution' (default: 'command')
function M.insert_marker(start_line, context, scope, marker_type)
  local marker = get_marker(marker_type)
  local bufnr = vim.api.nvim_get_current_buf()
  local prefix, suffix = get_comment_parts()

  -- Build scope hint
  local scope_hint = ''
  if scope then
    scope_hint = '<' .. scope .. '> '
  end

  -- Build marker content: "cc: <scope> context <- " (cursor at end after arrow)
  local marker_content
  if context and context ~= '' then
    local clean_context = context:gsub('\n', ' '):gsub('%s+', ' ')
    marker_content = marker .. ' ' .. scope_hint .. clean_context .. ' <- '
  else
    marker_content = marker .. ' ' .. scope_hint
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

  -- Position cursor at end of line for typing instructions
  vim.api.nvim_win_set_cursor(0, { start_line, #marker_text })
  vim.cmd('startinsert!')
end

-- Track last motion for scope detection
M._last_motion = nil

-- Motion to scope mapping
local motion_scopes = {
  ip = 'paragraph',
  ap = 'paragraph',
  iw = 'word',
  aw = 'word',
  iW = 'word',
  aW = 'word',
  is = 'sentence',
  as = 'sentence',
  ['i}'] = 'block',
  ['a}'] = 'block',
  iB = 'block',
  aB = 'block',
  ['if'] = 'function',
  af = 'function',
}

---Operatorfunc for gC motion
---@param type string 'line', 'char', or 'block'
function M.operatorfunc(type)
  local start_line = vim.fn.line("'[")
  local end_line = vim.fn.line("']")

  local motion = M._last_motion
  M._last_motion = nil

  local scope = motion_scopes[motion]
  if not scope and type == 'line' then
    scope = start_line == end_line and 'line' or 'lines'
  end

  M.insert_marker(start_line, nil, scope)
end

---Wrap lines in cc: marker (legacy, for direct calls)
---@param start_line integer 1-indexed start line
---@param end_line integer 1-indexed end line
---@param prompt string|nil Optional prompt text
function M.wrap_lines(start_line, end_line, prompt)
  M.insert_marker(start_line, prompt)
end

-- Text objects with their scopes
local text_objects = {
  { motion = 'ip', scope = 'paragraph' },
  { motion = 'ap', scope = 'paragraph' },
  { motion = 'iw', scope = 'word', capture = true },
  { motion = 'aw', scope = 'word', capture = true },
  { motion = 'iW', scope = 'WORD', capture = true },
  { motion = 'aW', scope = 'WORD', capture = true },
  { motion = 'is', scope = 'sentence', capture = true },
  { motion = 'as', scope = 'sentence', capture = true },
  { motion = 'i}', scope = 'block' },
  { motion = 'a}', scope = 'block' },
  { motion = 'i{', scope = 'block' },
  { motion = 'a{', scope = 'block' },
  { motion = 'iB', scope = 'block' },
  { motion = 'aB', scope = 'block' },
  { motion = 'if', scope = 'function' },
  { motion = 'af', scope = 'function' },
}

---Create keymaps for a marker type
---@param key string Base key (e.g., 'gC')
---@param marker_type string 'command'|'constitution'
---@param motions boolean Whether to create text object mappings
local function create_keymaps(key, marker_type, motions)
  local marker_name = get_marker(marker_type):gsub(':', '')

  -- Line-wise (doubled key like gCC, or suffix like gC!)
  vim.keymap.set('n', key, function()
    M.insert_marker(vim.fn.line('.'), nil, 'line', marker_type)
  end, { desc = 'Pairup: ' .. marker_name .. ' marker on line' })

  if not motions then
    return
  end

  -- Visual mode
  vim.keymap.set('x', key, function()
    local start_pos = vim.fn.getpos('v')
    local end_pos = vim.fn.getpos('.')
    local start_line, start_col = start_pos[2], start_pos[3] - 1
    local end_line, end_col = end_pos[2], end_pos[3] - 1
    if start_line > end_line or (start_line == end_line and start_col > end_col) then
      start_line, end_line = end_line, start_line
      start_col, end_col = end_col, start_col
    end
    local context = get_text(start_line, start_col, end_line, end_col)
    vim.cmd('normal! ' .. vim.api.nvim_replace_termcodes('<Esc>', true, false, true))
    M.insert_marker(start_line, context, 'selection', marker_type)
  end, { desc = 'Pairup: ' .. marker_name .. ' marker on selection' })

  -- Text objects
  for _, obj in ipairs(text_objects) do
    vim.keymap.set('n', key .. obj.motion, function()
      local esc = vim.api.nvim_replace_termcodes('<Esc>', true, false, true)
      vim.cmd('normal! v' .. obj.motion .. esc)
      local start_line = vim.fn.line("'<")
      local start_col = vim.fn.col("'<") - 1
      local end_col = vim.fn.col("'>") - 1
      local context = obj.capture and get_text(start_line, start_col, vim.fn.line("'>"), end_col) or nil
      M.insert_marker(start_line, context, obj.scope, marker_type)
    end, { desc = 'Pairup: ' .. marker_name .. ' marker on ' .. obj.scope })
  end
end

---Setup the gC operator
---@param opts table|nil Options (key: string to override default 'gC')
function M.setup(opts)
  opts = opts or {}
  local key = opts.key or 'gC'

  -- Generic operator for arbitrary motions (fallback)
  vim.keymap.set('n', key, function()
    vim.o.operatorfunc = "v:lua.require'pairup.operator'.operatorfunc"
    return 'g@'
  end, { expr = true, desc = 'Pairup: wrap in cc: marker' })

  -- Command marker: gCC (line), gCip, gCiw, etc.
  create_keymaps(key .. key:sub(-1), 'command', true)

  -- Constitution marker: gC! (line only for now)
  create_keymaps(key .. '!', 'constitution', false)
end

return M
