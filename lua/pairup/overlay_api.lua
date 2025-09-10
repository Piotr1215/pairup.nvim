-- Simplified overlay API with just two robust functions
local M = {}

local overlay = require('pairup.overlay')
local state_module = require('pairup.utils.state')

-- Single function for single-line overlays
-- Uses JSON to handle all escaping issues robustly
function M.single(line, new_text, reasoning)
  local state = state_module.get_state()
  if not state.main_buffer then
    return vim.json.encode({ error = 'No main buffer found' })
  end

  -- Validate line number
  local line_count = vim.api.nvim_buf_line_count(state.main_buffer)
  if line < 1 or line > line_count then
    return vim.json.encode({
      error = string.format('Line %d out of bounds (file has %d lines)', line, line_count),
      success = false,
    })
  end

  -- Get the old text for the line
  local old_text = vim.api.nvim_buf_get_lines(state.main_buffer, line - 1, line, false)[1]

  -- Create the overlay
  overlay.show_suggestion(state.main_buffer, line, old_text, new_text, reasoning or '')

  return vim.json.encode({
    success = true,
    line = line,
    message = 'Overlay created',
  })
end

-- Single function for multi-line overlays
-- Uses JSON internally to handle all escaping
function M.multiline(start_line, end_line, new_lines, reasoning)
  local state = state_module.get_state()
  if not state.main_buffer then
    return vim.json.encode({ error = 'No main buffer found' })
  end

  -- Validate line numbers
  local line_count = vim.api.nvim_buf_line_count(state.main_buffer)
  if start_line < 1 or start_line > line_count then
    return vim.json.encode({
      error = string.format('Start line %d out of bounds (file has %d lines)', start_line, line_count),
      success = false,
    })
  end
  if end_line < start_line or end_line > line_count then
    return vim.json.encode({
      error = string.format('End line %d out of bounds (file has %d lines)', end_line, line_count),
      success = false,
    })
  end

  -- Get the old lines
  local old_lines = vim.api.nvim_buf_get_lines(state.main_buffer, start_line - 1, end_line, false)

  -- Ensure new_lines is a table
  if type(new_lines) == 'string' then
    new_lines = vim.split(new_lines, '\n', { plain = true })
  end

  -- Create the multiline overlay
  overlay.show_multiline_suggestion(state.main_buffer, start_line, end_line, old_lines, new_lines, reasoning or '')

  return vim.json.encode({
    success = true,
    start_line = start_line,
    end_line = end_line,
    message = 'Multiline overlay created',
  })
end

-- Clear all overlays
function M.clear()
  local state = state_module.get_state()
  if not state.main_buffer then
    return vim.json.encode({ error = 'No main buffer found' })
  end

  overlay.clear_overlays(state.main_buffer)
  return vim.json.encode({ success = true, message = 'All overlays cleared' })
end

-- Accept overlay at specific line
function M.accept(line)
  local state = state_module.get_state()
  if not state.main_buffer then
    return vim.json.encode({ error = 'No main buffer found' })
  end

  overlay.apply_at_line(state.main_buffer, line)
  return vim.json.encode({ success = true, line = line, message = 'Overlay accepted' })
end

-- Reject overlay at specific line
function M.reject(line)
  local state = state_module.get_state()
  if not state.main_buffer then
    return vim.json.encode({ error = 'No main buffer found' })
  end

  overlay.reject_at_line(state.main_buffer, line)
  return vim.json.encode({ success = true, line = line, message = 'Overlay rejected' })
end

-- Get all current overlays
function M.list()
  local state = state_module.get_state()
  if not state.main_buffer then
    return vim.json.encode({ error = 'No main buffer found' })
  end

  local suggestions = overlay.get_suggestions(state.main_buffer)
  local list = {}

  for line_num, suggestion in pairs(suggestions) do
    table.insert(list, {
      line = line_num,
      old_text = suggestion.old_text,
      new_text = suggestion.new_text,
      reasoning = suggestion.reasoning,
    })
  end

  -- Sort by line number
  table.sort(list, function(a, b)
    return a.line < b.line
  end)

  return vim.json.encode({
    success = true,
    overlays = list,
    count = #list,
  })
end

return M
