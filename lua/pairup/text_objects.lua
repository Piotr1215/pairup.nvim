-- Custom text object implementations for pairup.nvim
-- Based on beam.nvim's implementation

local M = {}

--- Find the codeblock boundaries around the cursor
---@param variant string 'i' for inner, 'a' for around
---@return table|nil { start_line, end_line }
function M.find_codeblock(variant)
  local buf = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local cursor_line = vim.fn.line('.')

  local in_code_block = false
  local block_start = nil

  for i, line in ipairs(lines) do
    if line:match('^```') then
      if not in_code_block then
        in_code_block = true
        block_start = i
      else
        -- End of code block
        if block_start and cursor_line >= block_start and cursor_line <= i then
          -- Cursor is inside this block
          if variant == 'i' then
            -- Inner: content only (excluding backticks)
            return { start_line = block_start + 1, end_line = i - 1 }
          else
            -- Around: including backticks
            return { start_line = block_start, end_line = i }
          end
        end
        in_code_block = false
        block_start = nil
      end
    end
  end

  return nil
end

--- Find the markdown header section around the cursor
--- A header section extends from its # line to the line before the next same-or-higher-level header
---@param variant string 'i' for inner (content only), 'a' for around (including header line)
---@return table|nil { start_line, end_line, level }
function M.find_header(variant)
  local buf = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local cursor_line = vim.fn.line('.')

  -- Find the header that contains the cursor
  local header_start = nil
  local header_level = nil

  -- Search backwards from cursor to find the containing header
  for i = cursor_line, 1, -1 do
    local level = lines[i]:match('^(#+)%s')
    if level then
      header_start = i
      header_level = #level
      break
    end
  end

  if not header_start then
    return nil
  end

  -- Find the end: next header of same or higher level, or end of file
  local header_end = #lines
  for i = header_start + 1, #lines do
    local level = lines[i]:match('^(#+)%s')
    if level and #level <= header_level then
      header_end = i - 1
      break
    end
  end

  if variant == 'i' then
    -- Inner: content only (excluding header line)
    return { start_line = header_start + 1, end_line = header_end, level = header_level }
  else
    -- Around: including header line
    return { start_line = header_start, end_line = header_end, level = header_level }
  end
end

--- Select the header text object
---@param variant string 'i' for inner, 'a' for around
function M.select_header(variant)
  local bounds = M.find_header(variant)
  if not bounds then
    return
  end

  -- Handle empty inner section
  if variant == 'i' and bounds.start_line > bounds.end_line then
    return
  end

  -- Select the range in linewise visual mode
  vim.cmd('normal! ' .. bounds.start_line .. 'GV' .. bounds.end_line .. 'G')
end

--- Select the codeblock text object
---@param variant string 'i' for inner, 'a' for around
function M.select_codeblock(variant)
  local bounds = M.find_codeblock(variant)
  if not bounds then
    return
  end

  -- Handle empty inner block
  if variant == 'i' and bounds.start_line > bounds.end_line then
    return
  end

  -- Select the range in linewise visual mode
  vim.cmd('normal! ' .. bounds.start_line .. 'GV' .. bounds.end_line .. 'G')
end

--- Setup the ic/ac text objects
function M.setup()
  -- Inner codeblock
  vim.keymap.set('o', 'ic', function()
    M.select_codeblock('i')
  end, { desc = 'inner codeblock' })

  vim.keymap.set('x', 'ic', function()
    M.select_codeblock('i')
  end, { desc = 'inner codeblock' })

  -- Around codeblock
  vim.keymap.set('o', 'ac', function()
    M.select_codeblock('a')
  end, { desc = 'around codeblock' })

  vim.keymap.set('x', 'ac', function()
    M.select_codeblock('a')
  end, { desc = 'around codeblock' })

  -- Inner header
  vim.keymap.set('o', 'ih', function()
    M.select_header('i')
  end, { desc = 'inner header section' })

  vim.keymap.set('x', 'ih', function()
    M.select_header('i')
  end, { desc = 'inner header section' })

  -- Around header
  vim.keymap.set('o', 'ah', function()
    M.select_header('a')
  end, { desc = 'around header section' })

  vim.keymap.set('x', 'ah', function()
    M.select_header('a')
  end, { desc = 'around header section' })
end

return M
