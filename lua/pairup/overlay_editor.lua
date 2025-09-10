-- Overlay editor module - allows editing suggestions before applying
local M = {}

local overlay = require('pairup.overlay')

-- State for the editor
local editor_state = {
  source_buf = nil,
  editor_buf = nil,
  editor_win = nil,
  current_suggestion = nil,
  line_num = nil,
}

-- Create an editable buffer for a suggestion
function M.edit_overlay_at_cursor()
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = cursor[1]

  -- Get suggestions for current buffer
  local suggestions = overlay.get_suggestions(bufnr)
  if not suggestions or not suggestions[line] then
    vim.notify('No overlay at current position', vim.log.levels.WARN)
    return false
  end

  local suggestion = suggestions[line]

  -- Store state
  editor_state.source_buf = bufnr
  editor_state.current_suggestion = suggestion
  editor_state.line_num = line

  -- Create editor buffer
  local buf = vim.api.nvim_create_buf(false, true)
  editor_state.editor_buf = buf

  -- Prepare content for editing
  local lines = {}
  table.insert(lines, '# Edit Overlay Suggestion')
  table.insert(lines, '# Line: ' .. line)
  table.insert(lines, '# Save (:w) to apply your edited version')
  table.insert(lines, '# Close without saving to cancel')
  table.insert(lines, '')
  table.insert(lines, '## Original Text:')
  table.insert(lines, '```')

  if suggestion.is_multiline and suggestion.old_lines then
    for _, old_line in ipairs(suggestion.old_lines) do
      table.insert(lines, old_line)
    end
  else
    -- Split on newlines in case text contains embedded newlines
    local text_lines = vim.split(suggestion.old_text or '', '\n', { plain = true })
    for _, text_line in ipairs(text_lines) do
      table.insert(lines, text_line)
    end
  end

  table.insert(lines, '```')
  table.insert(lines, '')
  table.insert(lines, "## Claude's Suggestion:")
  table.insert(lines, '```')

  if suggestion.is_multiline and suggestion.new_lines then
    for _, new_line in ipairs(suggestion.new_lines) do
      table.insert(lines, new_line)
    end
  else
    -- Split on newlines in case text contains embedded newlines
    local text_lines = vim.split(suggestion.new_text or '', '\n', { plain = true })
    for _, text_line in ipairs(text_lines) do
      table.insert(lines, text_line)
    end
  end

  table.insert(lines, '```')
  table.insert(lines, '')
  table.insert(lines, '## Your Edit (modify below):')
  table.insert(lines, '```')

  -- Add the suggestion text as starting point for editing
  if suggestion.is_multiline and suggestion.new_lines then
    for _, new_line in ipairs(suggestion.new_lines) do
      table.insert(lines, new_line)
    end
  else
    -- Split on newlines in case text contains embedded newlines
    local text_lines = vim.split(suggestion.new_text or '', '\n', { plain = true })
    for _, text_line in ipairs(text_lines) do
      table.insert(lines, text_line)
    end
  end

  table.insert(lines, '```')
  table.insert(lines, '')
  table.insert(lines, '## Your Notes for Claude (optional):')
  table.insert(lines, '')

  -- Set buffer content
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  -- Set buffer options
  vim.api.nvim_buf_set_option(buf, 'filetype', 'markdown')
  vim.api.nvim_buf_set_option(buf, 'buftype', 'acwrite')
  vim.api.nvim_buf_set_name(buf, 'overlay-editor://' .. line)

  -- Store the original window and buffer before splitting
  local original_win = vim.api.nvim_get_current_win()
  local original_buf = vim.api.nvim_get_current_buf()

  -- Open in split
  vim.cmd('split')
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)
  editor_state.editor_win = win
  editor_state.original_win = original_win
  editor_state.original_buf = original_buf

  -- Set up autocmd for saving
  vim.api.nvim_create_autocmd('BufWriteCmd', {
    buffer = buf,
    callback = function()
      M.apply_edited_overlay()
      -- Mark buffer as saved
      vim.api.nvim_buf_set_option(buf, 'modified', false)
      return true
    end,
  })

  -- Handle :wq and :q properly - only close the editor window
  vim.api.nvim_create_autocmd('WinClosed', {
    pattern = tostring(win),
    once = true,
    callback = function()
      -- Ensure we go back to the original window after closing editor
      if editor_state.original_win and vim.api.nvim_win_is_valid(editor_state.original_win) then
        vim.api.nvim_set_current_win(editor_state.original_win)
      end
      -- Clean up state
      editor_state.editor_buf = nil
      editor_state.editor_win = nil
      editor_state.original_win = nil
      editor_state.original_buf = nil
    end,
  })

  -- Note: We can't override :wq or :x commands as they're built-in
  -- The WinClosed autocmd above handles proper cleanup when the window is closed

  -- Position cursor at the editable section
  local edit_start = 0
  for i, l in ipairs(lines) do
    if l == '## Your Edit (modify below):' then
      edit_start = i + 2 -- Skip header and ``` line
      break
    end
  end

  if edit_start > 0 then
    vim.api.nvim_win_set_cursor(win, { edit_start, 0 })
  end

  -- vim.notify('Edit the suggestion and save to apply, or close to cancel', vim.log.levels.INFO)
  return true
end

-- Apply the edited overlay
function M.apply_edited_overlay()
  if not editor_state.editor_buf or not vim.api.nvim_buf_is_valid(editor_state.editor_buf) then
    return false
  end

  local lines = vim.api.nvim_buf_get_lines(editor_state.editor_buf, 0, -1, false)

  -- Parse the edited content
  local in_edit_section = false
  local in_notes_section = false
  local edited_lines = {}
  local notes_lines = {}
  local skip_next = false

  for _, line in ipairs(lines) do
    if line == '## Your Edit (modify below):' then
      in_edit_section = true
      in_notes_section = false
      skip_next = true -- Skip the ``` line
    elseif line == '## Your Notes for Claude (optional):' then
      in_edit_section = false
      in_notes_section = true
    elseif in_edit_section and not skip_next then
      if line ~= '```' then
        table.insert(edited_lines, line)
      else
        in_edit_section = false
      end
    elseif in_notes_section and line ~= '' then
      table.insert(notes_lines, line)
    elseif skip_next then
      skip_next = false
    end
  end

  -- Prepare the edited text
  local edited_text = table.concat(edited_lines, '\n')
  local notes = #notes_lines > 0 and table.concat(notes_lines, '\n') or nil

  -- Apply the edit to the source buffer
  if editor_state.current_suggestion.is_multiline then
    local start_line = editor_state.line_num
    local end_line = editor_state.current_suggestion.end_line
      or (start_line + #editor_state.current_suggestion.old_lines - 1)

    -- Replace the lines
    vim.api.nvim_buf_set_lines(editor_state.source_buf, start_line - 1, end_line, false, edited_lines)
  else
    -- Single line replacement
    vim.api.nvim_buf_set_lines(
      editor_state.source_buf,
      editor_state.line_num - 1,
      editor_state.line_num,
      false,
      edited_lines
    )
  end

  -- Clear the overlay
  overlay.clear_overlay_at_line(editor_state.source_buf, editor_state.line_num)

  -- Send feedback to Claude if we have RPC enabled
  local ok, rpc = pcall(require, 'pairup.rpc')
  if ok and rpc.is_enabled() then
    M.send_edited_feedback(edited_text, notes)
  end

  -- Close the editor
  if editor_state.editor_win and vim.api.nvim_win_is_valid(editor_state.editor_win) then
    vim.api.nvim_win_close(editor_state.editor_win, true)
  end

  -- Reset state
  editor_state = {
    source_buf = nil,
    editor_buf = nil,
    editor_win = nil,
    current_suggestion = nil,
    line_num = nil,
  }

  -- vim.notify('Applied edited overlay', vim.log.levels.INFO)
  return true
end

-- Send feedback about the edit to Claude
function M.send_edited_feedback(edited_text, notes)
  local providers = require('pairup.providers')
  local active_provider = providers.get_current()

  if not active_provider then
    return
  end

  -- Construct feedback message
  local feedback = {
    'USER EDITED YOUR SUGGESTION:',
    '',
    'Line: ' .. editor_state.line_num,
    '',
    'Original text:',
    editor_state.current_suggestion.old_text or table.concat(editor_state.current_suggestion.old_lines or {}, '\n'),
    '',
    'Your suggestion was:',
    editor_state.current_suggestion.new_text or table.concat(editor_state.current_suggestion.new_lines or {}, '\n'),
    '',
    'User edited it to:',
    edited_text,
  }

  if notes then
    table.insert(feedback, '')
    table.insert(feedback, 'User notes:')
    table.insert(feedback, notes)
  end

  table.insert(feedback, '')
  table.insert(feedback, 'Please learn from this edit for future suggestions.')

  -- Send to Claude
  active_provider.send_message(table.concat(feedback, '\n'))
end

-- Edit overlay from quickfix
function M.edit_from_quickfix()
  -- Get current quickfix item
  local qf_idx = vim.fn.line('.')
  local qf_list = vim.fn.getqflist()

  if qf_idx < 1 or qf_idx > #qf_list then
    vim.notify('Invalid quickfix entry', vim.log.levels.WARN)
    return false
  end

  local qf_item = qf_list[qf_idx]

  -- Jump to the location
  vim.cmd('cc ' .. qf_idx)

  -- Edit the overlay at that position
  return M.edit_overlay_at_cursor()
end

-- Clear an overlay at a specific line
function M.clear_overlay_at_line(bufnr, line_num)
  overlay.clear_overlay_at_line(bufnr, line_num)
end

return M
