-- Overlay editor module - allows editing suggestions before applying
local M = {}

local overlay = require('pairup.overlay')

-- State for the editor
local editor_state = {
  source_buf = nil,
  editor_buf = nil,
  editor_win = nil,
  current_suggestion = nil,
  extmark_id = nil, -- Store extmark ID instead of line number
}

-- Helper to get extmark ID at current position
local function get_extmark_at_line(bufnr, line)
  local ns_id = vim.api.nvim_create_namespace('pairup_overlay')
  local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, { line - 1, 0 }, { line, 0 }, {})
  if #marks > 0 then
    return marks[1][1]
  end
  return nil
end

-- Helper to get current line from extmark
local function get_line_from_extmark(bufnr, extmark_id)
  if not extmark_id then
    return nil
  end
  local ns_id = vim.api.nvim_create_namespace('pairup_overlay')
  local extmark_pos = vim.api.nvim_buf_get_extmark_by_id(bufnr, ns_id, extmark_id, {})
  if #extmark_pos > 0 then
    return extmark_pos[1] + 1 -- Convert to 1-based
  end
  return nil
end

-- Create an editable buffer for a suggestion
function M.edit_overlay_at_cursor()
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = cursor[1]

  -- Get extmark ID at current position
  local extmark_id = get_extmark_at_line(bufnr, line)
  if not extmark_id then
    vim.notify('No overlay at current position', vim.log.levels.WARN)
    return false
  end

  -- Get suggestions using the raw storage
  local raw_suggestions = overlay.get_all_suggestions()[bufnr]
  if not raw_suggestions or not raw_suggestions[extmark_id] then
    vim.notify('No overlay at current position', vim.log.levels.WARN)
    return false
  end

  local suggestion = raw_suggestions[extmark_id]

  -- Store state with extmark ID
  editor_state.source_buf = bufnr
  editor_state.current_suggestion = suggestion
  editor_state.extmark_id = extmark_id

  -- Check if we already have an editor buffer for this extmark and reuse it
  local buffer_name = 'overlay-editor://extmark_' .. extmark_id
  local existing_buf = nil

  -- Search for existing buffer with this name
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(b) then
      local name = vim.api.nvim_buf_get_name(b)
      if name == buffer_name then
        existing_buf = b
        -- Clear the buffer content to prepare for new content
        vim.api.nvim_buf_set_lines(b, 0, -1, false, {})
        break
      end
    end
  end

  -- Create editor buffer (reuse existing or create new)
  local buf = existing_buf or vim.api.nvim_create_buf(false, true)
  editor_state.editor_buf = buf

  -- Get current line position for display
  local current_line = get_line_from_extmark(bufnr, extmark_id) or line

  -- Prepare content for editing
  local lines = {}
  table.insert(lines, '# Edit Overlay Suggestion')
  table.insert(lines, '# Line: ' .. current_line)
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

  -- Handle variants if present
  local suggestion_text
  if suggestion.variants and suggestion.current_variant then
    local variant = suggestion.variants[suggestion.current_variant]
    if variant then
      if suggestion.is_multiline then
        suggestion_text = variant.new_lines
      else
        suggestion_text = variant.new_text
      end
    end
  else
    -- Regular suggestion
    if suggestion.is_multiline then
      suggestion_text = suggestion.new_lines
    else
      suggestion_text = suggestion.new_text
    end
  end

  -- Display Claude's suggestion
  if type(suggestion_text) == 'table' then
    for _, line in ipairs(suggestion_text) do
      table.insert(lines, line)
    end
  else
    local text_lines = vim.split(suggestion_text or '', '\n', { plain = true })
    for _, text_line in ipairs(text_lines) do
      table.insert(lines, text_line)
    end
  end

  table.insert(lines, '```')
  table.insert(lines, '')
  table.insert(lines, '## Your Edit (modify below):')
  table.insert(lines, '```')

  -- Add the suggestion text as starting point for editing (same as above)
  if type(suggestion_text) == 'table' then
    for _, line in ipairs(suggestion_text) do
      table.insert(lines, line)
    end
  else
    local text_lines = vim.split(suggestion_text or '', '\n', { plain = true })
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

  -- Set buffer name only if it's a new buffer
  if not existing_buf then
    vim.api.nvim_buf_set_name(buf, buffer_name)
  end

  -- Store the original window and buffer before splitting
  local original_win = vim.api.nvim_get_current_win()
  local original_buf = vim.api.nvim_get_current_buf()

  -- Create a split for the editor
  vim.cmd('new')
  local win = vim.api.nvim_get_current_win()
  editor_state.editor_win = win

  -- Set the buffer in the new window
  vim.api.nvim_win_set_buf(win, buf)

  -- Set up autocommands for saving
  vim.api.nvim_create_autocmd('BufWriteCmd', {
    buffer = buf,
    callback = function()
      M.apply_edited_overlay()
      -- Mark buffer as saved
      vim.api.nvim_buf_set_option(buf, 'modified', false)
    end,
  })

  -- Also set up autocmd to clean up state when window is closed
  vim.api.nvim_create_autocmd({ 'BufWipeout', 'BufDelete', 'BufUnload' }, {
    buffer = buf,
    callback = function()
      editor_state = {
        source_buf = nil,
        editor_buf = nil,
        editor_win = nil,
        current_suggestion = nil,
        extmark_id = nil,
      }
    end,
  })

  -- Move cursor to the edit section for convenience
  local edit_start = 0
  for i, line in ipairs(lines) do
    if line == '## Your Edit (modify below):' then
      edit_start = i + 2 -- Skip to first line after ```
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

  if not editor_state.extmark_id then
    vim.notify('Lost track of overlay position', vim.log.levels.ERROR)
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

  -- Get current position of the overlay using extmark
  local current_line = get_line_from_extmark(editor_state.source_buf, editor_state.extmark_id)
  if not current_line then
    vim.notify('Cannot find overlay position - it may have been removed', vim.log.levels.ERROR)
    return false
  end

  -- Prepare the edited text
  local edited_text = table.concat(edited_lines, '\n')
  local notes = #notes_lines > 0 and table.concat(notes_lines, '\n') or nil

  -- CRITICAL: First clear the overlay to remove the visual suggestion
  -- This must happen BEFORE applying the edit to prevent confusion
  local ns_id = vim.api.nvim_create_namespace('pairup_overlay')

  -- Remove from suggestions storage
  local raw_suggestions = overlay.get_all_suggestions()
  if raw_suggestions[editor_state.source_buf] then
    raw_suggestions[editor_state.source_buf][editor_state.extmark_id] = nil
  end

  -- Delete the extmark
  vim.api.nvim_buf_del_extmark(editor_state.source_buf, ns_id, editor_state.extmark_id)

  -- Now apply the edit to the source buffer
  if editor_state.current_suggestion.is_multiline then
    -- Calculate the range based on current position
    local start_line = current_line
    local line_count = #(editor_state.current_suggestion.old_lines or {})
    local end_line = start_line + line_count - 1

    -- Replace the lines
    vim.api.nvim_buf_set_lines(editor_state.source_buf, start_line - 1, end_line, false, edited_lines)
  else
    -- Single line replacement
    vim.api.nvim_buf_set_lines(editor_state.source_buf, current_line - 1, current_line, false, edited_lines)
  end

  -- Force a redraw to ensure the overlay disappears immediately
  vim.cmd('redraw!')

  -- Send feedback to Claude if we have RPC enabled
  local ok, rpc = pcall(require, 'pairup.rpc')
  if ok and rpc.is_enabled() then
    M.send_edited_feedback(edited_text, notes)
  end

  -- Close the editor window after a small delay to ensure the save completes
  if editor_state.editor_win and vim.api.nvim_win_is_valid(editor_state.editor_win) then
    local win_to_close = editor_state.editor_win
    vim.defer_fn(function()
      if vim.api.nvim_win_is_valid(win_to_close) then
        vim.api.nvim_win_close(win_to_close, true)
      end
    end, 10)
  end

  -- Reset state
  editor_state = {
    source_buf = nil,
    editor_buf = nil,
    editor_win = nil,
    current_suggestion = nil,
    extmark_id = nil,
  }

  vim.notify('Applied edited overlay', vim.log.levels.INFO)
  return true
end

-- Send feedback to Claude about the edit
function M.send_edited_feedback(edited_text, notes)
  local providers = require('pairup.providers')

  -- Build feedback message
  local feedback = 'I edited your suggestion.'
  if notes then
    feedback = feedback .. '\nNotes: ' .. notes
  end

  feedback = feedback .. '\nFinal version applied:\n```\n' .. edited_text .. '\n```'

  -- Send feedback to provider
  providers.send_to_provider(feedback)
end

-- Check if there's an active editor
function M.has_active_editor()
  return editor_state.editor_buf ~= nil and vim.api.nvim_buf_is_valid(editor_state.editor_buf)
end

-- Get the active editor buffer (for testing)
function M.get_editor_buffer()
  return editor_state.editor_buf
end

return M
