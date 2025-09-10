-- Simplified overlay API with just two robust functions
local M = {}

local overlay = require('pairup.overlay')

-- Single function for single-line overlays
-- Uses JSON to handle all escaping issues robustly
function M.single(line, new_text, reasoning)
  -- Get the main buffer from RPC state
  local rpc = require('pairup.rpc')
  local state = rpc.get_state and rpc.get_state() or {}
  local main_buffer = state.main_buffer

  if not main_buffer then
    return vim.json.encode({ error = 'No main buffer found' })
  end

  -- Validate line number
  local line_count = vim.api.nvim_buf_line_count(main_buffer)
  if line < 1 or line > line_count then
    return vim.json.encode({
      error = string.format('Line %d out of bounds (file has %d lines)', line, line_count),
      success = false,
    })
  end

  -- Get the old text for the line
  local old_text = vim.api.nvim_buf_get_lines(main_buffer, line - 1, line, false)[1]

  -- Create the overlay
  overlay.show_suggestion(main_buffer, line, old_text, new_text, reasoning or '')

  return vim.json.encode({
    success = true,
    line = line,
    message = 'Overlay created',
  })
end

-- Single function for multi-line overlays
-- Uses JSON internally to handle all escaping
function M.multiline(start_line, end_line, new_lines, reasoning)
  -- Get the main buffer from RPC state
  local rpc = require('pairup.rpc')
  local state = rpc.get_state and rpc.get_state() or {}
  local main_buffer = state.main_buffer

  if not main_buffer then
    return vim.json.encode({ error = 'No main buffer found' })
  end

  -- Validate line numbers
  local line_count = vim.api.nvim_buf_line_count(main_buffer)
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
  local old_lines = vim.api.nvim_buf_get_lines(main_buffer, start_line - 1, end_line, false)

  -- Ensure new_lines is a table
  if type(new_lines) == 'string' then
    new_lines = vim.split(new_lines, '\n', { plain = true })
  end

  -- Create the multiline overlay
  overlay.show_multiline_suggestion(main_buffer, start_line, end_line, old_lines, new_lines, reasoning or '')

  return vim.json.encode({
    success = true,
    start_line = start_line,
    end_line = end_line,
    message = 'Multiline overlay created',
  })
end

-- Clear all overlays - REMOVED FROM CLAUDE ACCESS
-- This function is kept for user commands only
-- function M.clear()
--   local state = state_module.get_state()
--   if not main_buffer then
--     return vim.json.encode({ error = 'No main buffer found' })
--   end
--
--   overlay.clear_overlays(main_buffer)
--   return vim.json.encode({ success = true, message = 'All overlays cleared' })
-- end

-- Accept overlay at specific line
function M.accept(line)
  local rpc = require('pairup.rpc')
  local state = rpc.get_state and rpc.get_state() or {}
  local main_buffer = state.main_buffer
  if not main_buffer then
    return vim.json.encode({ error = 'No main buffer found' })
  end

  overlay.apply_at_line(main_buffer, line)
  return vim.json.encode({ success = true, line = line, message = 'Overlay accepted' })
end

-- Reject overlay at specific line
function M.reject(line)
  local rpc = require('pairup.rpc')
  local state = rpc.get_state and rpc.get_state() or {}
  local main_buffer = state.main_buffer
  if not main_buffer then
    return vim.json.encode({ error = 'No main buffer found' })
  end

  overlay.reject_at_line(main_buffer, line)
  return vim.json.encode({ success = true, line = line, message = 'Overlay rejected' })
end

-- Get all current overlays
function M.list()
  local rpc = require('pairup.rpc')
  local state = rpc.get_state and rpc.get_state() or {}
  local main_buffer = state.main_buffer
  if not main_buffer then
    return vim.json.encode({ error = 'No main buffer found' })
  end

  local suggestions = overlay.get_suggestions(main_buffer)
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
