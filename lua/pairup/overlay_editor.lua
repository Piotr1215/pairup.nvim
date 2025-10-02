-- Overlay editor module - allows editing suggestions before applying (v3.0 simplified)
local M = {}

local overlay = require('pairup.overlay')

-- State for the editor
local editor_state = {
  source_buf = nil,
  editor_buf = nil,
  editor_win = nil,
  overlay_id = nil, -- Store overlay ID
}

-- Find overlay at current cursor position
local function find_overlay_at_cursor()
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = cursor[1]

  local buffer_overlays = overlay.get_overlays(bufnr)
  for _, ovl in ipairs(buffer_overlays) do
    if line >= ovl.start_line and line <= ovl.end_line then
      return ovl
    end
  end
  return nil
end

-- Create an editable buffer for a suggestion
function M.edit_at_cursor()
  local current_overlay = find_overlay_at_cursor()
  if not current_overlay then
    vim.notify('No overlay at current position', vim.log.levels.WARN)
    return false
  end

  -- Store state
  editor_state.source_buf = current_overlay.buf
  editor_state.overlay_id = current_overlay.id

  -- Create unique buffer name
  local buffer_name = 'overlay-editor://id_' .. current_overlay.id
  local existing_buf = nil

  -- Search for existing buffer
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(b) then
      local name = vim.api.nvim_buf_get_name(b)
      if name == buffer_name then
        existing_buf = b
        vim.api.nvim_buf_set_lines(b, 0, -1, false, {})
        break
      end
    end
  end

  -- Create editor buffer
  local buf = existing_buf or vim.api.nvim_create_buf(false, true)
  editor_state.editor_buf = buf

  -- Prepare content for editing
  local lines = {}
  table.insert(lines, '# Edit Overlay Suggestion')
  table.insert(lines, '# Lines: ' .. current_overlay.start_line .. '-' .. current_overlay.end_line)
  table.insert(lines, '# Save (:w) to apply, close without saving to cancel')
  table.insert(lines, '')

  if current_overlay.reasoning and current_overlay.reasoning ~= '' then
    table.insert(lines, '## Reasoning:')
    table.insert(lines, current_overlay.reasoning)
    table.insert(lines, '')
  end

  table.insert(lines, '## Original Text:')
  table.insert(lines, '```')
  for _, old_line in ipairs(current_overlay.old_lines) do
    table.insert(lines, old_line)
  end
  table.insert(lines, '```')
  table.insert(lines, '')

  table.insert(lines, "## Claude's Suggestion:")
  table.insert(lines, '```')
  for _, new_line in ipairs(current_overlay.new_lines) do
    table.insert(lines, new_line)
  end
  table.insert(lines, '```')
  table.insert(lines, '')

  table.insert(lines, '## Your Edit (modify below):')
  table.insert(lines, '```')
  for _, new_line in ipairs(current_overlay.new_lines) do
    table.insert(lines, new_line)
  end
  table.insert(lines, '```')

  -- Set buffer content
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(buf, 'filetype', 'markdown')
  vim.api.nvim_buf_set_option(buf, 'buftype', 'acwrite')

  if not existing_buf then
    vim.api.nvim_buf_set_name(buf, buffer_name)
  end

  -- Create split
  vim.cmd('new')
  local win = vim.api.nvim_get_current_win()
  editor_state.editor_win = win
  vim.api.nvim_win_set_buf(win, buf)

  -- Set up save autocmd
  vim.api.nvim_create_autocmd('BufWriteCmd', {
    buffer = buf,
    callback = function()
      M.apply_edited_overlay()
      vim.api.nvim_buf_set_option(buf, 'modified', false)
    end,
  })

  -- Cleanup on close
  vim.api.nvim_create_autocmd({ 'BufWipeout', 'BufDelete', 'BufUnload' }, {
    buffer = buf,
    callback = function()
      editor_state = {
        source_buf = nil,
        editor_buf = nil,
        editor_win = nil,
        overlay_id = nil,
      }
    end,
  })

  -- Move cursor to edit section
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

  return true
end

-- Apply the edited overlay
function M.apply_edited_overlay()
  if not editor_state.editor_buf or not vim.api.nvim_buf_is_valid(editor_state.editor_buf) then
    vim.notify('Invalid editor buffer', vim.log.levels.ERROR)
    return false
  end

  if not editor_state.overlay_id then
    vim.notify('Lost track of overlay', vim.log.levels.ERROR)
    return false
  end

  -- Find the overlay by ID
  local target_overlay = nil
  local buffer_overlays = overlay.get_overlays(editor_state.source_buf)
  for _, ovl in ipairs(buffer_overlays) do
    if ovl.id == editor_state.overlay_id then
      target_overlay = ovl
      break
    end
  end

  if not target_overlay then
    vim.notify('Overlay no longer exists', vim.log.levels.WARN)
    return false
  end

  -- Parse edited content
  local lines = vim.api.nvim_buf_get_lines(editor_state.editor_buf, 0, -1, false)
  local in_edit_section = false
  local edited_lines = {}
  local skip_next = false

  for _, line in ipairs(lines) do
    if line == '## Your Edit (modify below):' then
      in_edit_section = true
      skip_next = true
    elseif in_edit_section and not skip_next then
      if line ~= '```' then
        table.insert(edited_lines, line)
      else
        break
      end
    elseif skip_next then
      skip_next = false
    end
  end

  if #edited_lines == 0 then
    vim.notify('No edited content found', vim.log.levels.WARN)
    return false
  end

  -- Apply the edit: first reject the old overlay, then apply new lines
  -- This is cleaner than directly manipulating buffer lines
  local start_line = target_overlay.start_line
  local end_line = target_overlay.end_line

  -- Remove the overlay (this will clear visual display)
  overlay.reject_at_cursor()

  -- Apply the edited lines to the buffer
  vim.api.nvim_buf_set_lines(editor_state.source_buf, start_line - 1, end_line, false, edited_lines)

  -- Close editor window
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
    overlay_id = nil,
  }

  vim.notify('Applied edited overlay', vim.log.levels.INFO)
  return true
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
