-- Beam-style scope buffer for showing only overlays
local M = {}

local overlay = require('pairup.overlay')

-- State for the scope buffer
M.scope_state = {
  buffer = nil,
  window = nil,
  source_buffer = nil,
  source_window = nil,
  line_to_extmark = {}, -- Maps scope buffer line to extmark_id instead of suggestion
}

-- Helper to get current suggestion from extmark
local function get_suggestion_from_extmark(bufnr, extmark_id)
  local suggestions = overlay.get_all_suggestions()
  if suggestions and suggestions[bufnr] then
    return suggestions[bufnr][extmark_id]
  end
  return nil
end

-- Create a scope buffer showing only lines with suggestions
function M.create_scope_buffer(source_buf)
  source_buf = source_buf or vim.api.nvim_get_current_buf()

  -- Get all suggestions for this buffer with current line positions
  local suggestions = overlay.get_suggestions(source_buf)
  if not suggestions or vim.tbl_count(suggestions) == 0 then
    -- Return nil explicitly to indicate no buffer was created
    return nil
  end

  -- Get the raw suggestions indexed by extmark_id
  local raw_suggestions = overlay.get_all_suggestions()[source_buf] or {}

  -- Create mapping from line to extmark_id
  local line_to_extmark = {}
  for extmark_id, suggestion in pairs(raw_suggestions) do
    local ns_id = vim.api.nvim_create_namespace('pairup_overlay')
    local extmark_pos = vim.api.nvim_buf_get_extmark_by_id(source_buf, ns_id, extmark_id, {})
    if #extmark_pos > 0 then
      local line = extmark_pos[1] + 1
      line_to_extmark[line] = extmark_id
    end
  end

  -- Create a new buffer
  local buf = vim.api.nvim_create_buf(false, true)

  -- Collect lines with suggestions
  local scope_lines = {}
  local scope_line_to_extmark = {}
  local scope_line = 1

  -- Get source buffer lines
  local source_lines = vim.api.nvim_buf_get_lines(source_buf, 0, -1, false)

  -- Sort suggestion line numbers
  local line_nums = {}
  for line_num, _ in pairs(suggestions) do
    table.insert(line_nums, line_num)
  end
  table.sort(line_nums)

  -- Build the scope buffer content
  for _, line_num in ipairs(line_nums) do
    local suggestion = suggestions[line_num]
    local extmark_id = line_to_extmark[line_num]
    if suggestion and extmark_id then
      -- Add separator
      table.insert(scope_lines, string.rep('─', 60))
      scope_line_to_extmark[scope_line] = nil
      scope_line = scope_line + 1

      -- Add separator line
      table.insert(scope_lines, string.rep('-', 60))
      scope_line_to_extmark[scope_line] = nil
      scope_line = scope_line + 1

      -- Add line number header
      local header = string.format('Line %d:', line_num)
      table.insert(scope_lines, header)
      scope_line_to_extmark[scope_line] = extmark_id
      scope_line = scope_line + 1

      -- Show original text
      if suggestion.is_multiline then
        -- For multiline, show all original lines
        if suggestion.old_lines then
          for _, old_line in ipairs(suggestion.old_lines) do
            table.insert(scope_lines, '  - ' .. old_line)
            scope_line_to_extmark[scope_line] = extmark_id
            scope_line = scope_line + 1
          end
        end
      else
        -- Single line original
        if line_num <= #source_lines then
          table.insert(scope_lines, '  - ' .. source_lines[line_num])
          scope_line_to_extmark[scope_line] = extmark_id
          scope_line = scope_line + 1
        end
      end

      -- Show suggested replacement
      if suggestion.is_multiline then
        -- Multiline suggestion
        if suggestion.new_lines then
          for _, new_line in ipairs(suggestion.new_lines) do
            -- Split by newlines in case the line contains them
            local lines = vim.split(new_line, '\n', { plain = true })
            for _, line in ipairs(lines) do
              table.insert(scope_lines, '  + ' .. line)
              scope_line_to_extmark[scope_line] = extmark_id
              scope_line = scope_line + 1
            end
          end
        end
      else
        -- Single line suggestion
        if suggestion.new_text then
          -- Split by newlines in case the text contains them
          local lines = vim.split(suggestion.new_text, '\n', { plain = true })
          for _, line in ipairs(lines) do
            table.insert(scope_lines, '  + ' .. line)
            scope_line_to_extmark[scope_line] = extmark_id
            scope_line = scope_line + 1
          end
        else
          -- Deletion
          table.insert(scope_lines, '  + (delete line)')
          scope_line_to_extmark[scope_line] = extmark_id
          scope_line = scope_line + 1
        end
      end
    end
  end

  -- Add help header at the top
  local help_header = { '═══ Overlay Scope │ g? help │ <CR> apply │ d reject │ q close ═══', '' }
  table.insert(scope_lines, 1, help_header[1])
  table.insert(scope_lines, 2, help_header[2])

  -- Set buffer content
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, scope_lines)

  -- Make buffer non-modifiable
  vim.api.nvim_buf_set_option(buf, 'modifiable', false)
  vim.api.nvim_buf_set_option(buf, 'buftype', 'nofile')
  vim.api.nvim_buf_set_option(buf, 'swapfile', false)
  vim.api.nvim_buf_set_option(buf, 'bufhidden', 'wipe')

  -- Set buffer name with unique identifier
  local source_name = vim.api.nvim_buf_get_name(source_buf)
  local base_name = vim.fn.fnamemodify(source_name, ':t')
  -- Use buffer number to ensure uniqueness
  local unique_name = string.format('PairupScope[%d]: %s', buf, base_name)
  pcall(vim.api.nvim_buf_set_name, buf, unique_name)

  -- Set filetype to match source for syntax highlighting
  local source_ft = vim.api.nvim_buf_get_option(source_buf, 'filetype')
  if source_ft and source_ft ~= '' then
    vim.api.nvim_buf_set_option(buf, 'filetype', source_ft)
  end

  -- Store state
  M.scope_state.buffer = buf
  M.scope_state.source_buffer = source_buf
  M.scope_state.line_to_extmark = scope_line_to_extmark

  -- Setup keymaps for the scope buffer
  M.setup_scope_keymaps(buf)

  return buf
end

-- Open scope in a split window
function M.open_scope()
  local source_buf = vim.api.nvim_get_current_buf()
  local source_win = vim.api.nvim_get_current_win()

  -- Create the scope buffer
  local scope_buf = M.create_scope_buffer(source_buf)
  if not scope_buf then
    return
  end

  -- Create a vertical split
  vim.cmd('vsplit')
  local scope_win = vim.api.nvim_get_current_win()

  -- Set the buffer in the new window
  vim.api.nvim_win_set_buf(scope_win, scope_buf)

  -- Store window references
  M.scope_state.source_window = source_win
  M.scope_state.window = scope_win

  -- Set window options
  vim.api.nvim_win_set_option(scope_win, 'wrap', false)
  vim.api.nvim_win_set_option(scope_win, 'number', false)
  vim.api.nvim_win_set_option(scope_win, 'relativenumber', false)
  vim.api.nvim_win_set_option(scope_win, 'signcolumn', 'no')

  -- vim.notify('Opened PairupScope - press <CR> to apply, d to delete, q to close', vim.log.levels.INFO)
end

-- Setup keymaps for the scope buffer
function M.setup_scope_keymaps(buf)
  local opts = { noremap = true, silent = true, buffer = buf }

  -- Apply suggestion on Enter
  vim.keymap.set('n', '<CR>', function()
    M.apply_suggestion_at_cursor()
  end, opts)

  -- Delete/reject suggestion
  vim.keymap.set('n', 'd', function()
    M.reject_suggestion_at_cursor()
  end, opts)

  -- Edit suggestion
  vim.keymap.set('n', 'e', function()
    -- Jump to source and open editor
    M.jump_to_source()
    vim.schedule(function()
      require('pairup.overlay_editor').edit_overlay_at_cursor()
    end)
  end, opts)

  -- Close scope
  vim.keymap.set('n', 'q', function()
    M.close_scope()
  end, opts)

  -- Jump to source location
  vim.keymap.set('n', 'gd', function()
    M.jump_to_source()
  end, opts)

  -- Navigate to next/previous overlay (not line by line)
  vim.keymap.set('n', '<C-n>', function()
    M.next_overlay()
  end, opts)

  vim.keymap.set('n', '<C-p>', function()
    M.prev_overlay()
  end, opts)

  -- Show help
  vim.keymap.set('n', 'g?', function()
    M.show_help()
  end, opts)

  -- Auto-jump to source on cursor move (like beam.nvim)
  vim.api.nvim_create_autocmd('CursorMoved', {
    buffer = buf,
    callback = function()
      M.highlight_source_location()
    end,
  })
end

-- Get current position from extmark
local function get_extmark_position(bufnr, extmark_id)
  local ns_id = vim.api.nvim_create_namespace('pairup_overlay')
  local extmark_pos = vim.api.nvim_buf_get_extmark_by_id(bufnr, ns_id, extmark_id, {})
  if #extmark_pos > 0 then
    return extmark_pos[1] + 1 -- Convert to 1-based
  end
  return nil
end

-- Apply the suggestion at cursor in scope buffer
function M.apply_suggestion_at_cursor()
  local line = vim.api.nvim_win_get_cursor(0)[1]
  local extmark_id = M.scope_state.line_to_extmark[line]

  if not extmark_id then
    -- vim.notify('No suggestion at this line', vim.log.levels.WARN)
    return
  end

  -- Switch to source buffer
  local source_buf = M.scope_state.source_buffer
  local source_win = M.scope_state.source_window

  if source_win and vim.api.nvim_win_is_valid(source_win) then
    vim.api.nvim_set_current_win(source_win)
  end

  if source_buf and vim.api.nvim_buf_is_valid(source_buf) then
    vim.api.nvim_set_current_buf(source_buf)
  end

  -- Get current line position from extmark
  local line_num = get_extmark_position(source_buf, extmark_id)
  if line_num then
    vim.api.nvim_win_set_cursor(0, { line_num, 0 })
    overlay.apply_at_cursor()

    -- Refresh the scope buffer
    M.refresh_scope()
  end
end

-- Reject the suggestion at cursor in scope buffer
function M.reject_suggestion_at_cursor()
  local line = vim.api.nvim_win_get_cursor(0)[1]
  local extmark_id = M.scope_state.line_to_extmark[line]

  if not extmark_id then
    -- vim.notify('No suggestion at this line', vim.log.levels.WARN)
    return
  end

  -- Switch to source buffer
  local source_buf = M.scope_state.source_buffer
  local source_win = M.scope_state.source_window

  if source_win and vim.api.nvim_win_is_valid(source_win) then
    vim.api.nvim_set_current_win(source_win)
  end

  if source_buf and vim.api.nvim_buf_is_valid(source_buf) then
    vim.api.nvim_set_current_buf(source_buf)
  end

  -- Get current line position from extmark
  local line_num = get_extmark_position(source_buf, extmark_id)
  if line_num then
    vim.api.nvim_win_set_cursor(0, { line_num, 0 })
    overlay.reject_at_cursor()

    -- Refresh the scope buffer
    M.refresh_scope()
  end
end

-- Highlight source location without switching windows
function M.highlight_source_location()
  local line = vim.api.nvim_win_get_cursor(0)[1]
  local extmark_id = M.scope_state.line_to_extmark[line]

  if not extmark_id then
    return
  end

  local source_win = M.scope_state.source_window
  local source_buf = M.scope_state.source_buffer

  if source_win and vim.api.nvim_win_is_valid(source_win) and source_buf then
    -- Get current line position from extmark
    local line_num = get_extmark_position(source_buf, extmark_id)
    if line_num then
      -- Move cursor in source window without switching to it
      vim.api.nvim_win_set_cursor(source_win, { line_num, 0 })

      -- Clear previous highlights
      if M.scope_state.highlight_ns then
        vim.api.nvim_buf_clear_namespace(source_buf, M.scope_state.highlight_ns, 0, -1)
      else
        M.scope_state.highlight_ns = vim.api.nvim_create_namespace('pairup_scope_highlight')
      end

      -- Get suggestion to check if multiline
      local suggestion = get_suggestion_from_extmark(source_buf, extmark_id)

      -- Highlight the current line(s)
      if suggestion and suggestion.is_multiline and suggestion.end_line then
        -- For multiline, recalculate end position based on current start
        local line_count = suggestion.end_line - suggestion.start_line
        for l = line_num, line_num + line_count do
          vim.api.nvim_buf_add_highlight(source_buf, M.scope_state.highlight_ns, 'Visual', l - 1, 0, -1)
        end
      else
        vim.api.nvim_buf_add_highlight(source_buf, M.scope_state.highlight_ns, 'Visual', line_num - 1, 0, -1)
      end
    end
  end
end

-- Navigate to next overlay (jumps between different overlays, not every line)
function M.next_overlay()
  local current_line = vim.api.nvim_win_get_cursor(0)[1]
  local buf_lines = vim.api.nvim_buf_line_count(0)

  -- Get current extmark
  local current_extmark = M.scope_state.line_to_extmark[current_line]

  -- Find next different extmark
  for line = current_line + 1, buf_lines do
    local extmark = M.scope_state.line_to_extmark[line]
    if extmark and extmark ~= current_extmark then
      -- Find the header line for this extmark (Line X:)
      while line > 1 and M.scope_state.line_to_extmark[line - 1] == extmark do
        line = line - 1
      end
      vim.api.nvim_win_set_cursor(0, { line, 0 })
      return
    end
  end

  -- Wrap around to beginning
  for line = 1, current_line - 1 do
    local extmark = M.scope_state.line_to_extmark[line]
    if extmark and extmark ~= current_extmark then
      -- Find the header line for this extmark
      while line > 1 and M.scope_state.line_to_extmark[line - 1] == extmark do
        line = line - 1
      end
      vim.api.nvim_win_set_cursor(0, { line, 0 })
      return
    end
  end
end

-- Navigate to previous overlay
function M.prev_overlay()
  local current_line = vim.api.nvim_win_get_cursor(0)[1]

  -- Get current extmark
  local current_extmark = M.scope_state.line_to_extmark[current_line]
  local last_different = nil
  local last_different_line = nil

  -- Find previous different extmark
  for line = current_line - 1, 1, -1 do
    local extmark = M.scope_state.line_to_extmark[line]
    if extmark and extmark ~= current_extmark and extmark ~= last_different then
      last_different = extmark
      last_different_line = line
    end
  end

  if last_different_line then
    -- Find the header line for this extmark
    while last_different_line > 1 and M.scope_state.line_to_extmark[last_different_line - 1] == last_different do
      last_different_line = last_different_line - 1
    end
    vim.api.nvim_win_set_cursor(0, { last_different_line, 0 })
    return
  end

  -- Wrap around to end
  local buf_lines = vim.api.nvim_buf_line_count(0)
  for line = buf_lines, current_line + 1, -1 do
    local extmark = M.scope_state.line_to_extmark[line]
    if extmark and extmark ~= current_extmark then
      -- Find the header line for this extmark
      while line > 1 and M.scope_state.line_to_extmark[line - 1] == extmark do
        line = line - 1
      end
      vim.api.nvim_win_set_cursor(0, { line, 0 })
      return
    end
  end
end

-- Show help window
function M.show_help()
  local help_text = [[
Overlay Scope Navigation:

  <CR>    Apply overlay at cursor
  d       Reject/delete overlay at cursor  
  e       Edit overlay before accepting
  q       Close overlay scope
  <C-n>   Next overlay (jumps between overlays)
  <C-p>   Previous overlay (jumps between overlays)
  gd      Jump to source location
  g?      Show this help

Press any key to close help...]]

  vim.notify(help_text, vim.log.levels.INFO)
end

-- Jump to source location
function M.jump_to_source()
  local line = vim.api.nvim_win_get_cursor(0)[1]
  local extmark_id = M.scope_state.line_to_extmark[line]

  if not extmark_id then
    return
  end

  local source_win = M.scope_state.source_window
  local source_buf = M.scope_state.source_buffer

  if source_win and vim.api.nvim_win_is_valid(source_win) then
    vim.api.nvim_set_current_win(source_win)

    -- Get current line position from extmark
    local line_num = get_extmark_position(source_buf, extmark_id)
    if line_num then
      vim.api.nvim_win_set_cursor(source_win, { line_num, 0 })
      vim.cmd('normal! zz') -- Center the view
    end
  end
end

-- Refresh the scope buffer
function M.refresh_scope()
  -- Check if we have a scope open
  if not M.scope_state.window or not vim.api.nvim_win_is_valid(M.scope_state.window) then
    return
  end

  local scope_win = M.scope_state.window
  local source_buf = M.scope_state.source_buffer

  -- Save cursor position
  local cursor_pos = nil
  if scope_win and vim.api.nvim_win_is_valid(scope_win) then
    cursor_pos = vim.api.nvim_win_get_cursor(scope_win)
  end

  -- Recreate the buffer content
  local new_buf = M.create_scope_buffer(source_buf)
  if not new_buf then
    -- No more suggestions, close the scope
    -- vim.notify('No suggestions remaining, closing scope', vim.log.levels.DEBUG)
    M.close_scope()
    return
  end

  -- Replace buffer in window
  if scope_win and vim.api.nvim_win_is_valid(scope_win) then
    vim.api.nvim_win_set_buf(scope_win, new_buf)

    -- Restore cursor position if possible
    if cursor_pos then
      pcall(vim.api.nvim_win_set_cursor, scope_win, cursor_pos)
    end
  end

  -- Clean up old buffer
  if M.scope_state.buffer ~= new_buf then
    pcall(vim.api.nvim_buf_delete, M.scope_state.buffer, { force = true })
  end

  M.scope_state.buffer = new_buf
end

-- Close the scope window
function M.close_scope()
  local win = M.scope_state.window

  -- Reset state first
  M.scope_state = {
    buffer = nil,
    window = nil,
    source_buffer = nil,
    source_window = nil,
    line_to_extmark = {},
  }

  -- Then close the window if it exists
  if win and vim.api.nvim_win_is_valid(win) then
    pcall(vim.api.nvim_win_close, win, true)
  end

  -- vim.notify('PairupScope closed', vim.log.levels.INFO)
end

-- Create quickfix list from suggestions
function M.create_quickfix_list()
  local source_buf = vim.api.nvim_get_current_buf()
  local suggestions = overlay.get_suggestions(source_buf)

  if not suggestions or vim.tbl_count(suggestions) == 0 then
    -- vim.notify('No suggestions for quickfix list', vim.log.levels.INFO)
    return
  end

  local qf_items = {}
  local filename = vim.api.nvim_buf_get_name(source_buf)

  -- Sort line numbers
  local line_nums = {}
  for line_num, _ in pairs(suggestions) do
    table.insert(line_nums, line_num)
  end
  table.sort(line_nums)

  -- Build quickfix items
  for _, line_num in ipairs(line_nums) do
    local suggestion = suggestions[line_num]
    local text = 'Suggestion: '

    if suggestion.is_multiline then
      text = text .. string.format('Replace lines %d-%d', suggestion.start_line, suggestion.end_line)
    elseif suggestion.new_text then
      text = text .. 'Change to: ' .. suggestion.new_text
    else
      text = text .. 'Delete line'
    end

    table.insert(qf_items, {
      filename = filename,
      lnum = line_num,
      col = 1,
      text = text,
      type = 'I', -- Information
    })
  end

  -- Set quickfix list
  vim.fn.setqflist(qf_items, 'r')
  vim.fn.setqflist({}, 'a', { title = 'Pairup Suggestions' })

  -- Open quickfix window
  vim.cmd('copen')
  -- vim.notify(string.format('Added %d suggestions to quickfix list', #qf_items), vim.log.levels.INFO)
end

return M
