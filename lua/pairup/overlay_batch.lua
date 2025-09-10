-- Batch overlay operations for Claude to handle complex suggestions
local M = {}

-- Current batch being built
local current_batch = {
  overlays = {},
  metadata = {},
}

-- Add a single-line overlay to the batch
function M.add_single(line, old_text, new_text, reasoning)
  table.insert(current_batch.overlays, {
    type = 'single',
    line = line,
    old_text = old_text,
    new_text = new_text,
    reasoning = reasoning,
  })
  return #current_batch.overlays
end

-- Add a multiline overlay to the batch
function M.add_multiline(start_line, end_line, old_lines, new_lines, reasoning)
  table.insert(current_batch.overlays, {
    type = 'multiline',
    start_line = start_line,
    end_line = end_line,
    old_lines = old_lines,
    new_lines = new_lines,
    reasoning = reasoning,
  })
  return #current_batch.overlays
end

-- Add a deletion overlay to the batch
function M.add_deletion(line, old_text, reasoning)
  table.insert(current_batch.overlays, {
    type = 'deletion',
    line = line,
    old_text = old_text,
    reasoning = reasoning,
  })
  return #current_batch.overlays
end

-- Clear the current batch
function M.clear_batch()
  current_batch = {
    overlays = {},
    metadata = {},
  }
  return true
end

-- Get current batch status
function M.get_batch_status()
  return {
    count = #current_batch.overlays,
    overlays = current_batch.overlays,
  }
end

-- Apply all overlays in the batch
function M.apply_batch()
  local overlay = require('pairup.overlay')
  local rpc = require('pairup.rpc')

  -- Get main buffer from RPC state
  local state = rpc.get_state and rpc.get_state() or {}
  local bufnr = state.main_buffer

  if not bufnr then
    return { error = 'No main buffer found', applied = 0 }
  end

  local applied = 0
  local errors = {}

  overlay.setup()

  for i, item in ipairs(current_batch.overlays) do
    local success = false

    if item.type == 'single' then
      overlay.show_suggestion(bufnr, item.line, item.old_text, item.new_text, item.reasoning)
      success = true
    elseif item.type == 'multiline' then
      overlay.show_multiline_suggestion(
        bufnr,
        item.start_line,
        item.end_line,
        item.old_lines,
        item.new_lines,
        item.reasoning
      )
      success = true
    elseif item.type == 'deletion' then
      overlay.show_suggestion(bufnr, item.line, item.old_text, nil, item.reasoning)
      success = true
    end

    if success then
      applied = applied + 1
    else
      table.insert(errors, 'Failed to apply overlay ' .. i)
    end
  end

  -- Clear batch after applying
  M.clear_batch()

  return {
    success = true,
    applied = applied,
    total = #current_batch.overlays,
    errors = errors,
  }
end

-- Build batch from structured data (for complex operations)
function M.build_from_data(data)
  -- Clear existing batch
  M.clear_batch()

  -- Handle different data formats
  if data.overlays then
    -- Direct overlay list
    for _, overlay in ipairs(data.overlays) do
      if overlay.type == 'single' then
        M.add_single(overlay.line, overlay.old_text, overlay.new_text, overlay.reasoning)
      elseif overlay.type == 'multiline' then
        M.add_multiline(overlay.start_line, overlay.end_line, overlay.old_lines, overlay.new_lines, overlay.reasoning)
      elseif overlay.type == 'deletion' then
        M.add_deletion(overlay.line, overlay.old_text, overlay.reasoning)
      end
    end
  elseif data.changes then
    -- Diff-style changes
    for _, change in ipairs(data.changes) do
      if change.action == 'replace' then
        if change.lines and #change.lines > 1 then
          M.add_multiline(
            change.start,
            change.start + #change.old_lines - 1,
            change.old_lines,
            change.new_lines,
            change.reasoning
          )
        else
          M.add_single(change.line, change.old, change.new, change.reasoning)
        end
      elseif change.action == 'delete' then
        M.add_deletion(change.line, change.text, change.reasoning)
      elseif change.action == 'insert' then
        M.add_single(change.line, '', change.text, change.reasoning)
      end
    end
  end

  return M.get_batch_status()
end

-- Helper to create a refactoring batch
function M.create_refactor_batch(pattern, replacement, reasoning)
  local rpc = require('pairup.rpc')
  local state = rpc.get_state and rpc.get_state() or {}
  local bufnr = state.main_buffer

  if not bufnr then
    return { error = 'No main buffer found' }
  end

  -- Get buffer lines
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  M.clear_batch()

  for i, line in ipairs(lines) do
    if line:find(pattern) then
      local new_line = line:gsub(pattern, replacement)
      M.add_single(i, line, new_line, reasoning)
    end
  end

  return M.get_batch_status()
end

return M
