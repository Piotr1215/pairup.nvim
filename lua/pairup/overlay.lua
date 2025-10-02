-- Simple overlay system inspired by sidekick.nvim
-- Focus: Marker -> Overlay -> Accept/Reject workflow

local M = {}

-- Namespace for extmarks
local ns_id = vim.api.nvim_create_namespace('pairup_overlay')

-- Simple overlay storage: array of overlays
-- Each overlay is self-contained with all data needed for rendering
---@class Overlay
---@field id number Unique overlay ID
---@field buf number Buffer number
---@field start_line number Start line (1-indexed)
---@field end_line number End line (1-indexed, inclusive)
---@field old_lines string[] Original lines
---@field new_lines string[] Replacement lines
---@field reasoning string Why this change
---@field is_deletion boolean True if removing lines with no replacement
---@field is_insertion boolean True if adding lines without replacing

local overlays = {} ---@type Overlay[]
local next_id = 1

-- Track which buffers have overlays rendered
local rendered_buffers = {} ---@type table<number, boolean>

---Helper to safely set extmark with error handling
---@param buf number
---@param row number 0-indexed
---@param col number
---@param opts table
---@return number? extmark_id
local function set_extmark(buf, row, col, opts)
  opts = opts or {}
  local ok, result = pcall(vim.api.nvim_buf_set_extmark, buf, ns_id, row, col, opts)
  if not ok then
    vim.notify(string.format('Failed to set extmark at %d:%d: %s', row, col, tostring(result)), vim.log.levels.WARN)
    return nil
  end
  return result
end

---Clear all extmarks in a buffer
---@param buf number
local function clear_buffer(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  vim.api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)
  rendered_buffers[buf] = nil
end

---Build virtual lines for an overlay
---@param overlay Overlay
---@return table[] virt_lines
local function build_virt_lines(overlay)
  local virt_lines = {}

  -- Header
  if overlay.is_deletion then
    table.insert(virt_lines, {
      { '╭─ Claude suggests removing lines ', 'PairupHeader' },
      { tostring(overlay.start_line) .. '-' .. tostring(overlay.end_line), 'PairupLineNum' },
      { ':', 'PairupHeader' },
    })
  elseif overlay.is_insertion then
    table.insert(virt_lines, {
      { '╭─ Claude suggests inserting after line ', 'PairupHeader' },
      { tostring(overlay.start_line), 'PairupLineNum' },
      { ':', 'PairupHeader' },
    })
  else
    table.insert(virt_lines, {
      { '╭─ Claude suggests replacing lines ', 'PairupHeader' },
      { tostring(overlay.start_line) .. '-' .. tostring(overlay.end_line), 'PairupLineNum' },
      { ':', 'PairupHeader' },
    })
  end

  -- Show old lines if not an insertion
  if not overlay.is_insertion and overlay.old_lines and #overlay.old_lines > 0 then
    table.insert(virt_lines, { { '│ ', 'PairupBorder' }, { '── Original ──', 'PairupSubHeader' } })
    for _, line in ipairs(overlay.old_lines) do
      table.insert(virt_lines, { { '│ ', 'PairupBorder' }, { line, 'PairupDelete' } })
    end
  end

  -- Show new lines if not a deletion
  if not overlay.is_deletion then
    if not overlay.is_insertion then
      table.insert(virt_lines, { { '│ ', 'PairupBorder' }, { '── Suggestion ──', 'PairupSubHeader' } })
    end
    if overlay.new_lines and #overlay.new_lines > 0 then
      for _, line in ipairs(overlay.new_lines) do
        table.insert(virt_lines, { { '│ ', 'PairupBorder' }, { line, 'PairupAdd' } })
      end
    end
  end

  -- Reasoning
  if overlay.reasoning and overlay.reasoning ~= '' then
    table.insert(virt_lines, { { '│ ', 'PairupBorder' } })
    table.insert(virt_lines, { { '│ ', 'PairupBorder' }, { 'Reason: ' .. overlay.reasoning, 'PairupHint' } })
  end

  -- Footer
  table.insert(virt_lines, { { '╰─', 'PairupBorder' } })

  return virt_lines
end

---Render a single overlay as extmarks
---@param overlay Overlay
local function render_overlay(overlay)
  if not vim.api.nvim_buf_is_valid(overlay.buf) then
    return
  end

  local line_count = vim.api.nvim_buf_line_count(overlay.buf)

  -- Validate line numbers
  if overlay.start_line < 1 or overlay.start_line > line_count then
    vim.notify(
      string.format('Invalid overlay start_line %d (buffer has %d lines)', overlay.start_line, line_count),
      vim.log.levels.WARN
    )
    return
  end

  -- Build virtual lines
  local virt_lines = build_virt_lines(overlay)

  -- Place extmark at start_line (convert to 0-indexed)
  local row = overlay.start_line - 1
  set_extmark(overlay.buf, row, 0, {
    virt_lines = virt_lines,
    virt_lines_above = false,
    priority = 100,
  })

  rendered_buffers[overlay.buf] = true
end

---Clear all overlays from all buffers
function M.clear_all()
  for buf, _ in pairs(rendered_buffers) do
    clear_buffer(buf)
  end
  overlays = {}
  next_id = 1
end

---Clear overlays for a specific buffer
---@param buf number
function M.clear_buffer(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  clear_buffer(buf)

  -- Remove overlays for this buffer from storage
  local new_overlays = {}
  for _, overlay in ipairs(overlays) do
    if overlay.buf ~= buf then
      table.insert(new_overlays, overlay)
    end
  end
  overlays = new_overlays
end

---Re-render all overlays (clear and rebuild pattern)
function M.render_all()
  -- Clear all rendered buffers
  for buf, _ in pairs(rendered_buffers) do
    clear_buffer(buf)
  end

  -- Render each overlay
  for _, overlay in ipairs(overlays) do
    render_overlay(overlay)
  end
end

---Add a new overlay
---@param buf number
---@param start_line number 1-indexed
---@param end_line number 1-indexed
---@param old_lines string[]
---@param new_lines string[]
---@param reasoning string
---@return number overlay_id
function M.add_overlay(buf, start_line, end_line, old_lines, new_lines, reasoning)
  -- Validate inputs
  if not vim.api.nvim_buf_is_valid(buf) then
    error('Invalid buffer')
  end

  -- Determine overlay type
  local is_deletion = (not new_lines or #new_lines == 0)
  local is_insertion = (not old_lines or #old_lines == 0 or (old_lines[1] == ''))

  ---@type Overlay
  local overlay = {
    id = next_id,
    buf = buf,
    start_line = start_line,
    end_line = end_line,
    old_lines = old_lines or {},
    new_lines = new_lines or {},
    reasoning = reasoning, -- Keep nil if not provided
    is_deletion = is_deletion,
    is_insertion = is_insertion,
  }

  next_id = next_id + 1
  table.insert(overlays, overlay)

  -- Render this overlay
  render_overlay(overlay)

  return overlay.id
end

---Find overlay at cursor position
---@param buf number
---@param line number 1-indexed
---@return Overlay?
local function find_overlay_at_line(buf, line)
  for _, overlay in ipairs(overlays) do
    if overlay.buf == buf then
      -- Check if line is within overlay range
      if line >= overlay.start_line and line <= overlay.end_line then
        return overlay
      end
    end
  end
  return nil
end

---Apply overlay at cursor
---@return boolean success
function M.apply_at_cursor()
  local buf = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = cursor[1]

  local overlay = find_overlay_at_line(buf, line)
  if not overlay then
    vim.notify('No overlay at cursor', vim.log.levels.WARN)
    return false
  end

  -- Validate buffer state
  if not vim.api.nvim_buf_is_valid(overlay.buf) then
    return false
  end

  local line_count = vim.api.nvim_buf_line_count(overlay.buf)

  -- Apply the change
  if overlay.is_insertion then
    -- Insert new lines after start_line
    local insert_pos = math.min(overlay.start_line, line_count)
    vim.api.nvim_buf_set_lines(overlay.buf, insert_pos, insert_pos, false, overlay.new_lines)
  elseif overlay.is_deletion then
    -- Delete lines
    if overlay.start_line <= line_count then
      local delete_end = math.min(overlay.end_line, line_count)
      vim.api.nvim_buf_set_lines(overlay.buf, overlay.start_line - 1, delete_end, false, {})
    end
  else
    -- Replace lines
    if overlay.start_line <= line_count then
      local replace_end = math.min(overlay.end_line, line_count)
      vim.api.nvim_buf_set_lines(overlay.buf, overlay.start_line - 1, replace_end, false, overlay.new_lines)
    end
  end

  -- Remove this overlay from storage
  local new_overlays = {}
  for _, o in ipairs(overlays) do
    if o.id ~= overlay.id then
      table.insert(new_overlays, o)
    end
  end
  overlays = new_overlays

  -- Re-render to update display
  M.render_all()

  vim.notify('Applied overlay', vim.log.levels.INFO)
  return true
end

---Remove overlay by ID
---@param overlay_id number
---@return boolean success
function M.remove_by_id(overlay_id)
  local found = false
  local new_overlays = {}
  for _, o in ipairs(overlays) do
    if o.id ~= overlay_id then
      table.insert(new_overlays, o)
    else
      found = true
    end
  end

  if not found then
    return false
  end

  overlays = new_overlays
  M.render_all()
  return true
end

---Reject overlay at cursor (just remove it)
---@return boolean success
function M.reject_at_cursor()
  local buf = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = cursor[1]

  local overlay = find_overlay_at_line(buf, line)
  if not overlay then
    vim.notify('No overlay at cursor', vim.log.levels.WARN)
    return false
  end

  -- Remove using the new function
  M.remove_by_id(overlay.id)

  vim.notify('Rejected overlay', vim.log.levels.INFO)
  return true
end

---Navigate to next overlay
function M.next_overlay()
  local buf = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local current_line = cursor[1]

  -- Find next overlay after current position
  local next_overlay = nil
  local min_distance = math.huge

  for _, overlay in ipairs(overlays) do
    if overlay.buf == buf and overlay.start_line > current_line then
      local distance = overlay.start_line - current_line
      if distance < min_distance then
        min_distance = distance
        next_overlay = overlay
      end
    end
  end

  if next_overlay then
    vim.api.nvim_win_set_cursor(0, { next_overlay.start_line, 0 })
  else
    vim.notify('No more overlays', vim.log.levels.INFO)
  end
end

---Navigate to previous overlay
function M.prev_overlay()
  local buf = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local current_line = cursor[1]

  -- Find previous overlay before current position
  local prev_overlay = nil
  local min_distance = math.huge

  for _, overlay in ipairs(overlays) do
    if overlay.buf == buf and overlay.start_line < current_line then
      local distance = current_line - overlay.start_line
      if distance < min_distance then
        min_distance = distance
        prev_overlay = overlay
      end
    end
  end

  if prev_overlay then
    vim.api.nvim_win_set_cursor(0, { prev_overlay.start_line, 0 })
  else
    vim.notify('No previous overlays', vim.log.levels.INFO)
  end
end

---Accept all overlays in buffer
---@param buf? number
---@return number count
function M.accept_all_overlays(buf)
  buf = buf or vim.api.nvim_get_current_buf()

  -- Get all overlays for this buffer, sorted bottom-to-top
  local buffer_overlays = {}
  for _, overlay in ipairs(overlays) do
    if overlay.buf == buf then
      table.insert(buffer_overlays, overlay)
    end
  end

  -- Sort by start_line descending (bottom to top)
  table.sort(buffer_overlays, function(a, b)
    return a.start_line > b.start_line
  end)

  local count = 0
  for _, overlay in ipairs(buffer_overlays) do
    -- Apply each overlay
    if overlay.is_insertion then
      local line_count = vim.api.nvim_buf_line_count(overlay.buf)
      local insert_pos = math.min(overlay.start_line, line_count)
      vim.api.nvim_buf_set_lines(overlay.buf, insert_pos, insert_pos, false, overlay.new_lines)
    elseif overlay.is_deletion then
      local line_count = vim.api.nvim_buf_line_count(overlay.buf)
      if overlay.start_line <= line_count then
        local delete_end = math.min(overlay.end_line, line_count)
        vim.api.nvim_buf_set_lines(overlay.buf, overlay.start_line - 1, delete_end, false, {})
      end
    else
      local line_count = vim.api.nvim_buf_line_count(overlay.buf)
      if overlay.start_line <= line_count then
        local replace_end = math.min(overlay.end_line, line_count)
        vim.api.nvim_buf_set_lines(overlay.buf, overlay.start_line - 1, replace_end, false, overlay.new_lines)
      end
    end
    count = count + 1
  end

  -- Remove all overlays for this buffer
  local new_overlays = {}
  for _, o in ipairs(overlays) do
    if o.buf ~= buf then
      table.insert(new_overlays, o)
    end
  end
  overlays = new_overlays

  -- Clear and re-render
  M.render_all()

  if count > 0 then
    vim.notify(string.format('Accepted %d overlays', count), vim.log.levels.INFO)
  end

  return count
end

---Get status for statusline
---@param buf? number
---@return string
function M.get_status(buf)
  buf = buf or vim.api.nvim_get_current_buf()

  local count = 0
  for _, overlay in ipairs(overlays) do
    if overlay.buf == buf then
      count = count + 1
    end
  end

  if count > 0 then
    return string.format('󰄬 %d', count)
  end
  return ''
end

---Get all overlays for a buffer
---@param buf? number
---@return Overlay[]
function M.get_overlays(buf)
  buf = buf or vim.api.nvim_get_current_buf()

  local result = {}
  for _, overlay in ipairs(overlays) do
    if overlay.buf == buf then
      table.insert(result, overlay)
    end
  end
  return result
end

---Get suggestions in backward-compatible format (indexed by line number)
---@param buf? number
---@return table<number, table>
function M.get_suggestions(buf)
  buf = buf or vim.api.nvim_get_current_buf()

  local result = {}
  for _, overlay in ipairs(overlays) do
    if overlay.buf == buf then
      -- Store by start_line for backward compatibility
      result[overlay.start_line] = {
        line_num = overlay.start_line,
        start_line = overlay.start_line,
        end_line = overlay.end_line,
        old_text = overlay.old_lines[1],
        new_text = overlay.new_lines[1],
        old_lines = overlay.old_lines,
        new_lines = overlay.new_lines,
        reasoning = overlay.reasoning,
        is_multiline = (overlay.end_line > overlay.start_line),
        is_deletion = overlay.is_deletion,
      }
    end
  end
  return result
end

---Toggle overlays visibility
function M.toggle()
  local buf = vim.api.nvim_get_current_buf()

  -- Check if buffer has rendered overlays
  if rendered_buffers[buf] then
    -- Hide them
    clear_buffer(buf)
  else
    -- Show them
    M.render_all()
  end
end

---Parse and show diff as overlays (stub for compatibility)
---@param buf number
---@param diff_text string
function M.show_diff_overlay(buf, diff_text)
  -- For now, just notify - this is complex and can be added later
  vim.notify('show_diff_overlay not yet implemented in simplified version', vim.log.levels.WARN)
end

---Accept next overlay (jump to nearest and accept)
---@return boolean
function M.accept_next_overlay()
  local buf = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local current_line = cursor[1]

  -- Find nearest overlay
  local nearest_overlay = nil
  local min_distance = math.huge

  for _, overlay in ipairs(overlays) do
    if overlay.buf == buf then
      local distance = math.abs(overlay.start_line - current_line)
      if distance < min_distance then
        min_distance = distance
        nearest_overlay = overlay
      end
    end
  end

  if nearest_overlay then
    -- Jump to it
    vim.api.nvim_win_set_cursor(0, { nearest_overlay.start_line, 0 })
    -- Accept it
    return M.apply_at_cursor()
  end

  return false
end

---Toggle follow mode (stub for compatibility)
---@return boolean
function M.toggle_follow_mode()
  -- Simplified version doesn't have follow mode
  -- Return false to indicate it's disabled
  return false
end

---Check if follow mode is enabled (stub for compatibility)
---@return boolean
function M.is_follow_mode()
  return false
end

---Setup highlight groups
function M.setup()
  -- Headers and UI elements
  vim.api.nvim_set_hl(0, 'PairupHeader', { fg = '#7c7c7c', bg = '#2a2a2a', bold = true })
  vim.api.nvim_set_hl(0, 'PairupSubHeader', { fg = '#6c6c6c', italic = true })
  vim.api.nvim_set_hl(0, 'PairupBorder', { fg = '#4a4a4a' })
  vim.api.nvim_set_hl(0, 'PairupHint', { fg = '#5c5c5c', italic = true })
  vim.api.nvim_set_hl(0, 'PairupLineNum', { fg = '#8a8a8a', bold = true })

  -- Suggestion content
  vim.api.nvim_set_hl(0, 'PairupAdd', { fg = '#98c379', bg = '#1e2a1e', italic = true })
  vim.api.nvim_set_hl(0, 'PairupDelete', { fg = '#e06c75', bg = '#2a1e1e', strikethrough = true })
end

-- Backward compatibility aliases
M.clear_overlays = M.clear_buffer
M.show_suggestion = function(buf, line, old_text, new_text, reasoning)
  -- Convert single line to multiline format
  local old_lines = old_text and { old_text } or {}
  local new_lines = new_text and { new_text } or {}
  return M.add_overlay(buf, line, line, old_lines, new_lines, reasoning)
end

M.show_multiline_suggestion = function(buf, start_line, end_line, old_lines, new_lines, reasoning)
  return M.add_overlay(buf, start_line, end_line, old_lines, new_lines, reasoning)
end

M.show_deletion_suggestion = function(buf, start_line, end_line, reasoning)
  local old_lines = vim.api.nvim_buf_get_lines(buf, start_line - 1, end_line, false)
  return M.add_overlay(buf, start_line, end_line, old_lines, {}, reasoning)
end

return M
