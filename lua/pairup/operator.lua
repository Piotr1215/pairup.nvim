local M = {}

local config = require('pairup.config')
local text_objects_mod = require('pairup.text_objects')

---@param marker_type? string
---@return string
local function get_marker(marker_type)
  marker_type = marker_type or 'command'
  local marker = config.get('inline.markers.' .. marker_type)
  if marker then
    return marker
  end
  local defaults = { command = 'cc:', constitution = 'cc!:', plan = 'ccp:' }
  return defaults[marker_type] or 'cc:'
end

---@param start_line integer
---@param start_col integer
---@param end_line integer
---@param end_col integer
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

---@return string prefix, string suffix
local function get_comment_parts()
  local cs = vim.bo.commentstring
  if not cs or cs == '' then
    return '', ''
  end
  local prefix, suffix = cs:match('^(.-)%%s(.-)$')
  return (prefix or ''):gsub('%s+$', ''), (suffix or ''):gsub('^%s+', '')
end

---@param start_line integer
---@param context string|nil
---@param scope string|nil
---@param marker_type? string
function M.insert_marker(start_line, context, scope, marker_type)
  local marker = get_marker(marker_type)
  local bufnr = vim.api.nvim_get_current_buf()
  local prefix, suffix = get_comment_parts()

  local scope_hint = scope and ('<' .. scope .. '> ') or ''
  local marker_content
  if context and context ~= '' then
    local clean_context = context:gsub('\n', ' '):gsub('%s+', ' ')
    marker_content = marker .. ' ' .. scope_hint .. clean_context .. ' <- '
  else
    marker_content = marker .. ' ' .. scope_hint
  end

  local marker_text
  if prefix ~= '' then
    marker_text = suffix ~= '' and (prefix .. ' ' .. marker_content .. ' ' .. suffix)
      or (prefix .. ' ' .. marker_content)
  else
    marker_text = marker_content
  end

  vim.api.nvim_buf_set_lines(bufnr, start_line - 1, start_line - 1, false, { marker_text })
  vim.api.nvim_win_set_cursor(0, { start_line, #marker_text })
  vim.cmd('startinsert!')
end

-- Store marker type for operatorfunc callback
M._marker_type = 'command'

---@param _motion_type string 'line', 'char', or 'block' (unused - can't detect text object type)
function M.operatorfunc(_motion_type)
  M.insert_marker(vim.fn.line("'["), nil, nil, M._marker_type)
end

---@param marker_type string
---@return string
local function make_operator(marker_type)
  M._marker_type = marker_type
  vim.o.operatorfunc = "v:lua.require'pairup.operator'.operatorfunc"
  return 'g@'
end

-- Common text objects with their scope names
local text_objects = {
  { obj = 'iw', scope = 'word' },
  { obj = 'aw', scope = 'word' },
  { obj = 'iW', scope = 'WORD' },
  { obj = 'aW', scope = 'WORD' },
  { obj = 'is', scope = 'sentence' },
  { obj = 'as', scope = 'sentence' },
  { obj = 'ip', scope = 'paragraph' },
  { obj = 'ap', scope = 'paragraph' },
  { obj = 'if', scope = 'function' },
  { obj = 'af', scope = 'function' },
  { obj = 'ic', scope = 'codeblock' },
  { obj = 'ac', scope = 'codeblock' },
}

---@param key string
---@param marker_type string
local function create_operator(key, marker_type)
  local desc = 'Pairup: ' .. get_marker(marker_type):gsub(':', '') .. ' marker'

  -- Fallback operator for motions not in text_objects list
  vim.keymap.set('n', key, function()
    return make_operator(marker_type)
  end, { expr = true, desc = desc })

  -- Explicit text object mappings with scope hints
  for _, to in ipairs(text_objects) do
    vim.keymap.set('n', key .. to.obj, function()
      local start_line = vim.fn.line('.')
      -- Custom text objects (ic/ac) handled specially - they enter visual mode directly
      if to.obj == 'ic' or to.obj == 'ac' then
        -- Get codeblock boundaries to insert marker at opening ``` line
        local bounds = text_objects_mod.find_codeblock('a')
        if bounds then
          M.insert_marker(bounds.start_line, nil, to.scope, marker_type)
        end
      elseif to.obj == 'ip' or to.obj == 'ap' then
        -- Use vim's actual text object to get paragraph start
        local save_pos = vim.fn.getpos('.')
        vim.cmd('normal! v' .. to.obj .. vim.api.nvim_replace_termcodes('<Esc>', true, false, true))
        local para_start = vim.fn.line("'<")
        vim.fn.setpos('.', save_pos)
        M.insert_marker(para_start, nil, to.scope, marker_type)
      else
        -- Built-in text objects: select and escape
        vim.cmd('normal! v' .. to.obj .. vim.api.nvim_replace_termcodes('<Esc>', true, false, true))
        M.insert_marker(start_line, nil, to.scope, marker_type)
      end
    end, { desc = desc .. ' on ' .. to.scope })
  end

  -- Line-wise: double-tap (e.g., gCC, g!!, g??)
  vim.keymap.set('n', key .. key:sub(-1), function()
    M.insert_marker(vim.fn.line('.'), nil, 'line', marker_type)
  end, { desc = desc .. ' on line' })

  -- Visual mode
  vim.keymap.set('x', key, function()
    local start_pos, end_pos = vim.fn.getpos('v'), vim.fn.getpos('.')
    local start_line, start_col = start_pos[2], start_pos[3] - 1
    local end_line, end_col = end_pos[2], end_pos[3] - 1
    if start_line > end_line or (start_line == end_line and start_col > end_col) then
      start_line, end_line, start_col, end_col = end_line, start_line, end_col, start_col
    end
    local context = get_text(start_line, start_col, end_line, end_col)
    vim.cmd('normal! ' .. vim.api.nvim_replace_termcodes('<Esc>', true, false, true))
    M.insert_marker(start_line, context, 'selection', marker_type)
  end, { desc = desc .. ' on selection' })
end

---@param opts table|nil
function M.setup(opts)
  opts = opts or {}
  create_operator(opts.command_key or 'gC', 'command')
  create_operator(opts.constitution_key or 'g!', 'constitution')
  create_operator(opts.plan_key or 'g?', 'plan')
end

return M
