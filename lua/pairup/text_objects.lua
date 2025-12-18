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
end

return M
