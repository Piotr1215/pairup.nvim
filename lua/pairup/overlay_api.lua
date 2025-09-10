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

  -- Get the extmark ID for debugging
  local extmark_id = nil
  local suggestions = overlay.get_suggestions(main_buffer)
  if suggestions[line] then
    extmark_id = suggestions[line].extmark_id
  end

  return vim.json.encode({
    success = true,
    line = line,
    extmark_id = extmark_id,
    message = 'Overlay created',
    debug = {
      buffer = main_buffer,
      old_text = old_text,
      new_text = new_text,
    },
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

  -- Special handling for EOF append: when start_line == end_line == line_count
  -- and we're adding new content (not replacing), allow it
  local is_eof_append = false
  if start_line == line_count and end_line == line_count then
    -- Check if this looks like an append (will verify with old_lines later)
    is_eof_append = true
  end

  if not is_eof_append then
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
  end

  -- Get the old lines
  local old_lines = vim.api.nvim_buf_get_lines(main_buffer, start_line - 1, end_line, false)

  -- For EOF append, we pass empty old_lines to signal it's an append
  if is_eof_append and (#old_lines == 0 or old_lines[1] == '') then
    old_lines = {}
  end

  -- Ensure new_lines is a table
  if type(new_lines) == 'string' then
    new_lines = vim.split(new_lines, '\n', { plain = true })
  end

  -- Create the multiline overlay
  overlay.show_multiline_suggestion(main_buffer, start_line, end_line, old_lines, new_lines, reasoning or '')

  -- Get extmark info for debugging
  local suggestions = overlay.get_suggestions(main_buffer)
  local extmark_id = nil
  if suggestions[start_line] then
    extmark_id = suggestions[start_line].extmark_id
  end

  return vim.json.encode({
    success = true,
    start_line = start_line,
    end_line = end_line,
    extmark_id = extmark_id,
    message = 'Multiline overlay created',
    debug = {
      buffer = main_buffer,
      old_lines_count = #old_lines,
      new_lines_count = #new_lines,
      is_eof_append = is_eof_append,
    },
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
    local entry = {
      line = line_num,
      reasoning = suggestion.reasoning,
    }

    -- Include variant information if present
    if suggestion.variants then
      entry.has_variants = true
      entry.variant_count = #suggestion.variants
      entry.current_variant = suggestion.current_variant
    end

    -- Handle both single-line and multiline overlays
    if suggestion.is_multiline then
      entry.is_multiline = true
      entry.start_line = suggestion.start_line
      entry.end_line = suggestion.end_line
      entry.old_lines = suggestion.old_lines
      entry.new_lines = suggestion.new_lines
    else
      entry.old_text = suggestion.old_text
      entry.new_text = suggestion.new_text
    end

    table.insert(list, entry)
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

-- Create suggestion with multiple variants
function M.single_variants(line, variants)
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

  -- Ensure variants is a table
  if type(variants) == 'string' then
    variants = vim.json.decode(variants)
  end

  -- Create the overlay with variants
  overlay.show_suggestion_variants(main_buffer, line, old_text, variants)

  return vim.json.encode({
    success = true,
    line = line,
    variant_count = #variants,
    message = 'Overlay with variants created',
  })
end

-- Create multiline suggestion with multiple variants
function M.multiline_variants(start_line, end_line, variants)
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

  -- Ensure variants is a table
  if type(variants) == 'string' then
    variants = vim.json.decode(variants)
  end

  -- Create the multiline overlay with variants
  overlay.show_multiline_suggestion_variants(main_buffer, start_line, end_line, old_lines, variants)

  return vim.json.encode({
    success = true,
    start_line = start_line,
    end_line = end_line,
    variant_count = #variants,
    message = 'Multiline overlay with variants created',
  })
end

return M
