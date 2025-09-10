-- Virtual overlay for showing Claude's suggestions
local M = {}

local ns_id = vim.api.nvim_create_namespace('pairup_overlay')
local active_overlays = {}

-- Store suggestions for applying
local suggestions = {}
local hidden_overlays = {} -- Store overlays when toggled off
local follow_mode = false -- Auto-jump to new suggestions
local suggestion_only_mode = false -- Hide buffer, show only suggestions
local original_conceallevel = {}

-- Store a suggestion for later application
local function store_suggestion(bufnr, line_num, old_text, new_text, reasoning)
  if not suggestions[bufnr] then
    suggestions[bufnr] = {}
  end
  suggestions[bufnr][line_num] = {
    old_text = old_text,
    new_text = new_text,
    line_num = line_num,
    reasoning = reasoning, -- Store reasoning for the suggestion
  }
end

-- Get all suggestions for a buffer
function M.get_suggestions(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  return suggestions[bufnr] or {}
end

-- Show a suggestion as virtual text - ROBUST VERSION
function M.show_suggestion(bufnr, line_num, old_text, new_text, reasoning)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  -- Validate buffer
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end

  -- Validate line number
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  if line_num < 1 or line_num > line_count then
    return false
  end

  -- If old_text not provided, get it from buffer
  if not old_text or old_text == '' then
    old_text = vim.api.nvim_buf_get_lines(bufnr, line_num - 1, line_num, false)[1] or ''
  end

  -- Clear any existing overlay on this line
  vim.api.nvim_buf_clear_namespace(bufnr, ns_id, line_num - 1, line_num)

  -- Store the suggestion for later application
  store_suggestion(bufnr, line_num, old_text, new_text, reasoning)

  -- Helper function to create virt_line from text
  local function text_to_virt_line(text, highlight)
    local text_str = tostring(text or '')
    -- Show newlines visually if they exist
    local clean_text = text_str:gsub('\n', '↵')
    return { { clean_text, highlight } }
  end

  -- If it's a deletion, show strikethrough
  if new_text == nil or new_text == '' then
    -- Build virtual lines with reasoning if provided
    local virt_lines = {
      { { '╭─ Claude suggests removing:', 'PairupHeader' } },
    }
    -- Add the old text line with border
    table.insert(
      virt_lines,
      vim.list_extend({ { '│ ', 'PairupBorder' } }, text_to_virt_line(old_text, 'PairupDelete'))
    )

    if reasoning then
      table.insert(
        virt_lines,
        vim.list_extend({ { '│ ', 'PairupBorder' } }, text_to_virt_line('Reason: ' .. reasoning, 'PairupHint'))
      )
    end

    vim.api.nvim_buf_set_extmark(bufnr, ns_id, line_num - 1, 0, {
      virt_lines = virt_lines,
      priority = 100,
    })
  -- If it's an addition, show as virtual lines
  elseif old_text == nil or old_text == '' then
    local virt_lines = {
      { { '╭─ Claude suggests adding:', 'PairupHeader' } },
    }
    -- Add the new text line with border
    table.insert(virt_lines, vim.list_extend({ { '│ ', 'PairupBorder' } }, text_to_virt_line(new_text, 'PairupAdd')))

    if reasoning then
      table.insert(
        virt_lines,
        vim.list_extend({ { '│ ', 'PairupBorder' } }, text_to_virt_line('Reason: ' .. reasoning, 'PairupHint'))
      )
    end

    vim.api.nvim_buf_set_extmark(bufnr, ns_id, line_num - 1, 0, {
      virt_lines = virt_lines,
      priority = 100,
    })
  -- If it's a modification, show both old and new in a clear way
  else
    -- Build virtual lines with reasoning
    local virt_lines = {
      { { '╭─ Claude suggests changing:', 'PairupHeader' } },
    }
    -- Add old text with delete marker
    table.insert(
      virt_lines,
      vim.list_extend(
        { { '│ ', 'PairupBorder' }, { '- ', 'PairupDelete' } },
        text_to_virt_line(old_text, 'PairupDelete')
      )
    )
    -- Add new text with add marker
    table.insert(
      virt_lines,
      vim.list_extend({ { '│ ', 'PairupBorder' }, { '+ ', 'PairupAdd' } }, text_to_virt_line(new_text, 'PairupAdd'))
    )
    if reasoning then
      table.insert(virt_lines, { { '│ ', 'PairupBorder' }, { 'Reason: ' .. reasoning, 'PairupHint' } })
    end
    table.insert(virt_lines, { { '╰─', 'PairupBorder' } })

    vim.api.nvim_buf_set_extmark(bufnr, ns_id, line_num - 1, 0, {
      virt_lines = virt_lines,
      virt_lines_above = false,
      priority = 100,
    })
  end

  -- Track this overlay
  table.insert(active_overlays, { bufnr = bufnr, line = line_num })

  -- Auto-jump if follow mode is enabled (find the main window)
  if follow_mode then
    vim.schedule(function()
      -- Find window containing the target buffer
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_get_buf(win) == bufnr then
          vim.api.nvim_set_current_win(win)
          pcall(vim.api.nvim_win_set_cursor, win, { line_num, 0 })
          break
        end
      end
    end)
  end

  return true
end

-- Show deletion suggestion (for removing lines)
function M.show_deletion_suggestion(bufnr, start_line, end_line, reasoning)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  -- Get the lines to be deleted
  local old_lines = vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false)

  -- Build virtual lines showing deletion
  local virt_lines = {
    { { '╭─ Claude suggests removing lines ' .. start_line .. '-' .. end_line .. ':', 'PairupHeader' } },
  }

  for _, line in ipairs(old_lines) do
    table.insert(virt_lines, { { '│ ', 'PairupBorder' }, { '- ', 'PairupDelete' }, { line, 'PairupDelete' } })
  end

  if reasoning then
    table.insert(virt_lines, { { '│ ', 'PairupBorder' }, { 'Reason: ' .. reasoning, 'PairupHint' } })
  end

  table.insert(virt_lines, { { '╰─', 'PairupBorder' } })

  -- Set the extmark
  vim.api.nvim_buf_set_extmark(bufnr, ns_id, start_line - 1, 0, {
    virt_lines = virt_lines,
    virt_lines_above = false,
    priority = 100,
  })

  -- Track this as a deletion suggestion
  if not suggestions[bufnr] then
    suggestions[bufnr] = {}
  end

  suggestions[bufnr][start_line] = {
    line_num = start_line,
    start_line = start_line,
    end_line = end_line,
    old_lines = old_lines,
    new_lines = {}, -- Empty for deletion
    is_deletion = true,
    is_multiline = true,
    reasoning = reasoning,
  }
end

-- Show multiline suggestion - ROBUST VERSION
function M.show_multiline_suggestion(bufnr, start_line, end_line, old_lines, new_lines, reasoning)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  -- Validate buffer
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end

  -- Validate line numbers
  local line_count = vim.api.nvim_buf_line_count(bufnr)

  -- Special case: if trying to append at EOF (start_line == line_count and end_line == line_count)
  -- and old_lines is empty/nil, this is an append operation
  local is_eof_append = (
    start_line == line_count
    and end_line == line_count
    and (not old_lines or #old_lines == 0 or (old_lines[1] == ''))
  )

  if not is_eof_append then
    if start_line < 1 or start_line > line_count or end_line < start_line or end_line > line_count then
      return false
    end
  end

  -- If old_lines not provided, get them from buffer
  if not old_lines or #old_lines == 0 then
    old_lines = vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false)
  end

  -- Ensure new_lines is a table
  if type(new_lines) == 'string' then
    new_lines = vim.split(new_lines, '\n', { plain = true })
  elseif not new_lines then
    new_lines = {}
  end

  -- Clear any existing overlays in the range
  vim.api.nvim_buf_clear_namespace(bufnr, ns_id, start_line - 1, end_line)

  -- Build virtual lines for the suggestion
  local virt_lines = {}

  -- Check if this is an EOF append operation
  if is_eof_append then
    -- Special header for EOF append
    table.insert(virt_lines, {
      { '╭─ Claude suggests adding at end of file:', 'PairupHeader' },
    })
  else
    -- Normal replacement header
    table.insert(virt_lines, {
      { '╭─ Claude suggests replacing lines ', 'PairupHeader' },
      { tostring(start_line) .. '-' .. tostring(end_line), 'PairupLineNum' },
      { ':', 'PairupHeader' },
    })
  end

  -- Show old lines (unless EOF append)
  if not is_eof_append then
    table.insert(virt_lines, { { '│ ', 'PairupBorder' }, { '── Original ──', 'PairupSubHeader' } })
    for _, line in ipairs(old_lines) do
      table.insert(virt_lines, { { '│ ', 'PairupBorder' }, { line, 'PairupDelete' } })
    end
    table.insert(virt_lines, { { '│ ', 'PairupBorder' }, { '── Suggestion ──', 'PairupSubHeader' } })
  end

  -- Show new lines
  if #new_lines > 0 then
    for _, line in ipairs(new_lines) do
      table.insert(virt_lines, { { '│ ', 'PairupBorder' }, { line, 'PairupAdd' } })
    end
  else
    if not is_eof_append then
      table.insert(virt_lines, { { '│ ', 'PairupBorder' }, { '(delete these lines)', 'PairupHint' } })
    end
  end

  -- Add reasoning if provided
  if reasoning and reasoning ~= '' then
    table.insert(virt_lines, { { '│ ', 'PairupBorder' } })
    table.insert(virt_lines, { { '│ ', 'PairupBorder' }, { 'Reason: ' .. reasoning, 'PairupHint' } })
  end

  table.insert(virt_lines, { { '╰─', 'PairupBorder' } })

  -- Set the extmark at the start line
  vim.api.nvim_buf_set_extmark(bufnr, ns_id, start_line - 1, 0, {
    virt_lines = virt_lines,
    virt_lines_above = false,
    priority = 100,
  })

  -- Store multiline suggestion
  if not suggestions[bufnr] then
    suggestions[bufnr] = {}
  end
  suggestions[bufnr][start_line] = {
    is_multiline = true,
    start_line = start_line,
    end_line = end_line,
    old_lines = old_lines,
    new_lines = new_lines,
    reasoning = reasoning,
  }

  -- Track this overlay
  table.insert(active_overlays, { bufnr = bufnr, line = start_line, is_multiline = true, end_line = end_line })

  -- Auto-jump if follow mode is enabled
  if follow_mode then
    vim.schedule(function()
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_get_buf(win) == bufnr then
          vim.api.nvim_set_current_win(win)
          pcall(vim.api.nvim_win_set_cursor, win, { start_line, 0 })
          break
        end
      end
    end)
  end

  return true
end

-- Parse a diff and show all suggestions
function M.show_diff_overlay(bufnr, diff_text)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  -- Clear previous overlays
  M.clear_overlays(bufnr)

  -- Parse the diff
  local in_hunk = false
  local old_line_num = 0
  local new_line_num = 0
  local old_lines = {}
  local new_lines = {}

  for line in diff_text:gmatch('[^\n]+') do
    -- Check for hunk header like @@ -17,3 +17,5 @@
    local old_start, old_count, new_start, new_count = line:match('^@@%s+%-(%d+),(%d+)%s+%+(%d+),(%d+)%s+@@')
    if not old_start then
      old_start, new_start = line:match('^@@%s+%-(%d+)%s+%+(%d+)%s+@@')
      old_count, new_count = '1', '1'
    end

    if old_start then
      -- Process previous hunk if any
      if in_hunk then
        M.process_hunk(bufnr, old_line_num, old_lines, new_lines)
      end

      old_line_num = tonumber(old_start)
      new_line_num = tonumber(new_start)
      old_lines = {}
      new_lines = {}
      in_hunk = true
    elseif in_hunk then
      if line:sub(1, 1) == '-' then
        table.insert(old_lines, line:sub(2))
      elseif line:sub(1, 1) == '+' then
        table.insert(new_lines, line:sub(2))
      elseif line:sub(1, 1) == ' ' then
        -- Context line, skip
        old_line_num = old_line_num + 1
        new_line_num = new_line_num + 1
      end
    end
  end

  -- Process final hunk
  if in_hunk then
    M.process_hunk(bufnr, old_line_num, old_lines, new_lines)
  end
end

-- Process a single hunk
function M.process_hunk(bufnr, start_line, old_lines, new_lines)
  -- For multiline changes
  if #old_lines > 1 or #new_lines > 1 then
    local end_line = start_line + math.max(#old_lines, 1) - 1
    M.show_multiline_suggestion(bufnr, start_line, end_line, old_lines, new_lines)
  -- Single line changes
  elseif #old_lines == 1 and #new_lines == 1 then
    M.show_suggestion(bufnr, start_line, old_lines[1], new_lines[1])
  -- Single line addition
  elseif #old_lines == 0 and #new_lines == 1 then
    M.show_suggestion(bufnr, start_line, nil, new_lines[1])
  -- Single line deletion
  elseif #old_lines == 1 and #new_lines == 0 then
    M.show_suggestion(bufnr, start_line, old_lines[1], nil)
  end
end

-- Clear all overlays
function M.clear_overlays(bufnr)
  if bufnr then
    -- Check if buffer is valid before clearing
    if not vim.api.nvim_buf_is_valid(bufnr) then
      return
    end
    vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
    -- Clear suggestions for this buffer
    if suggestions[bufnr] then
      suggestions[bufnr] = {}
    end
  else
    -- Clear all tracked overlays
    for _, overlay in ipairs(active_overlays) do
      vim.api.nvim_buf_clear_namespace(overlay.bufnr, ns_id, 0, -1)
    end
  end
  -- Store current overlays for toggle
  hidden_overlays = vim.deepcopy(active_overlays)
  active_overlays = {}
end

-- Apply overlay at specific line
function M.apply_at_line(bufnr, line_num)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  if not suggestions[bufnr] or not suggestions[bufnr][line_num] then
    return false
  end

  local suggestion = suggestions[bufnr][line_num]

  if suggestion.is_multiline then
    -- Apply multiline change
    vim.api.nvim_buf_set_lines(bufnr, suggestion.start_line - 1, suggestion.end_line, false, suggestion.new_lines or {})
  else
    -- Apply single line change, handling embedded newlines
    local lines = vim.split(suggestion.new_text or '', '\n', { plain = true })
    vim.api.nvim_buf_set_lines(bufnr, line_num - 1, line_num, false, lines)
  end

  -- Clear the overlay after applying
  M.clear_overlay_at_line(bufnr, line_num)

  -- Save buffer
  if vim.api.nvim_buf_get_option(bufnr, 'modified') then
    vim.cmd('write')
  end

  return true
end

-- Reject overlay at specific line
function M.reject_at_line(bufnr, line_num)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  -- Simply clear the overlay without applying
  return M.clear_overlay_at_line(bufnr, line_num)
end

-- Apply suggestion at cursor position
function M.apply_at_cursor()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line_num = cursor[1]
  local bufnr = vim.api.nvim_get_current_buf()

  -- Check if we have a stored suggestion for this line
  if suggestions[bufnr] and suggestions[bufnr][line_num] then
    local suggestion = suggestions[bufnr][line_num]

    if suggestion.is_multiline then
      -- Apply multiline change
      vim.api.nvim_buf_set_lines(
        bufnr,
        suggestion.start_line - 1,
        suggestion.end_line,
        false,
        suggestion.new_lines or {}
      )
      -- Clear extmarks for this multiline suggestion
      vim.api.nvim_buf_clear_namespace(bufnr, ns_id, suggestion.start_line - 1, suggestion.end_line)
      -- vim.notify('Applied multiline suggestion', vim.log.levels.INFO)
    else
      -- Apply single line change
      local new_text = suggestion.new_text
      if new_text == nil or new_text == '' then
        -- Delete the line
        vim.api.nvim_buf_set_lines(bufnr, line_num - 1, line_num, false, {})
        -- vim.notify('Deleted line ' .. line_num, vim.log.levels.INFO)
      else
        -- Replace the line, handling embedded newlines
        local lines = vim.split(new_text, '\n', { plain = true })
        vim.api.nvim_buf_set_lines(bufnr, line_num - 1, line_num, false, lines)
        -- vim.notify('Applied suggestion at line ' .. line_num, vim.log.levels.INFO)
      end
      -- Clear this overlay completely
      -- Clear a wider range to include virtual text that may extend below
      vim.api.nvim_buf_clear_namespace(bufnr, ns_id, line_num - 1, line_num + 5)
    end

    -- Remove from stored suggestions
    suggestions[bufnr][line_num] = nil

    -- Remove from active overlays
    for i, overlay in ipairs(active_overlays) do
      if overlay.bufnr == bufnr and overlay.line == line_num then
        table.remove(active_overlays, i)
        break
      end
    end

    return true
  else
    vim.notify('No suggestion at current line', vim.log.levels.WARN)
    return false
  end
end

-- Reject suggestion at cursor position (just clear it)
function M.reject_at_cursor()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line_num = cursor[1]
  local bufnr = vim.api.nvim_get_current_buf()

  -- Check if we have a suggestion at this line
  if suggestions[bufnr] and suggestions[bufnr][line_num] then
    local suggestion = suggestions[bufnr][line_num]

    if suggestion.is_multiline then
      -- Clear multiline overlay
      vim.api.nvim_buf_clear_namespace(bufnr, ns_id, suggestion.start_line - 1, suggestion.end_line)
      -- vim.notify('Rejected multiline suggestion', vim.log.levels.INFO)
    else
      -- Clear single line overlay (with extra range for virtual text)
      vim.api.nvim_buf_clear_namespace(bufnr, ns_id, line_num - 1, line_num + 5)
      -- vim.notify('Rejected suggestion at line ' .. line_num, vim.log.levels.INFO)
    end

    -- Remove from stored suggestions
    suggestions[bufnr][line_num] = nil

    -- Remove from active overlays
    for i, overlay in ipairs(active_overlays) do
      if overlay.bufnr == bufnr and overlay.line == line_num then
        table.remove(active_overlays, i)
        break
      end
    end

    return true
  else
    vim.notify('No suggestion at current line', vim.log.levels.WARN)
    return false
  end
end

-- Find nearest overlay (helper function)
local function find_nearest_overlay(bufnr, from_line)
  local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, 0, -1, {})
  local nearest = nil
  local nearest_distance = math.huge

  for _, mark in ipairs(marks) do
    local line = mark[2] + 1
    local distance = math.abs(line - from_line)
    if distance < nearest_distance and distance > 0 then
      nearest = line
      nearest_distance = distance
    end
  end

  return nearest
end

-- Accept nearest overlay
function M.accept_next_overlay()
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local current_line = cursor[1]

  -- Find nearest overlay
  local nearest_line = find_nearest_overlay(bufnr, current_line)

  if nearest_line then
    -- Jump to it
    vim.api.nvim_win_set_cursor(0, { nearest_line, 0 })
    -- Accept it
    return M.apply_at_cursor()
  else
    -- vim.notify('No overlays found', vim.log.levels.WARN)
    return false
  end
end

-- Navigate to next overlay
function M.next_overlay()
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local current_line = cursor[1]

  -- Get all extmarks
  local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, { current_line, 0 }, -1, {})

  if #marks > 0 then
    local next_line = marks[1][2] + 1
    vim.api.nvim_win_set_cursor(0, { next_line, 0 })
    -- vim.notify('Moved to next suggestion', vim.log.levels.INFO)
  else
    -- vim.notify('No more suggestions', vim.log.levels.INFO)
  end
end

-- Navigate to previous overlay
function M.prev_overlay()
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local current_line = cursor[1]

  -- Get all extmarks before current position
  local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, 0, { current_line - 2, 0 }, {})

  if #marks > 0 then
    local prev_line = marks[#marks][2] + 1
    vim.api.nvim_win_set_cursor(0, { prev_line, 0 })
    -- vim.notify('Moved to previous suggestion', vim.log.levels.INFO)
  else
    -- vim.notify('No previous suggestions', vim.log.levels.INFO)
  end
end

-- Toggle overlays on/off
function M.toggle()
  local bufnr = vim.api.nvim_get_current_buf()
  local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, 0, -1, {})

  if #marks > 0 then
    -- Hide overlays by clearing namespace but keep suggestions
    vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
    -- Store current overlays for this buffer
    hidden_overlays = {}
    for _, overlay in ipairs(active_overlays) do
      if overlay.bufnr == bufnr then
        table.insert(hidden_overlays, overlay)
      end
    end
    -- vim.notify('Pairup overlay hidden', vim.log.levels.INFO)
  else
    -- Restore hidden overlays using suggestions data
    if suggestions[bufnr] then
      for line_num, s in pairs(suggestions[bufnr]) do
        if s.is_multiline then
          M.show_multiline_suggestion(bufnr, s.start_line, s.end_line, s.old_lines, s.new_lines, s.reasoning)
        else
          M.show_suggestion(bufnr, line_num, s.old_text, s.new_text, s.reasoning)
        end
      end
      -- vim.notify('Pairup overlay restored', vim.log.levels.INFO)
    else
      -- vim.notify('No overlay to show', vim.log.levels.INFO)
    end
  end
end

-- Toggle follow mode
function M.toggle_follow_mode()
  follow_mode = not follow_mode
  if follow_mode then
    -- vim.notify('Overlay follow mode enabled - will jump to new suggestions', vim.log.levels.INFO)
  else
    -- vim.notify('Overlay follow mode disabled', vim.log.levels.INFO)
  end
  return follow_mode
end

-- Toggle suggestion-only mode (hide buffer content, show only overlays)
function M.toggle_suggestion_only()
  local bufnr = vim.api.nvim_get_current_buf()
  suggestion_only_mode = not suggestion_only_mode

  if suggestion_only_mode then
    -- Create a namespace for concealing
    local conceal_ns = vim.api.nvim_create_namespace('pairup_conceal')

    -- Get all lines in buffer
    local line_count = vim.api.nvim_buf_line_count(bufnr)

    -- Hide all lines without suggestions
    for line = 1, line_count do
      local has_suggestion = suggestions[bufnr] and suggestions[bufnr][line]

      if not has_suggestion then
        -- Hide the line by overlaying with empty text
        vim.api.nvim_buf_set_extmark(bufnr, conceal_ns, line - 1, 0, {
          virt_text = { { string.rep(' ', 80), 'PairupHiddenMarker' } }, -- Blank space to cover the line
          virt_text_pos = 'overlay',
          priority = 50,
        })
      end
    end

    -- vim.notify('Suggestion-only mode ON - showing only lines with suggestions', vim.log.levels.INFO)
  else
    -- Clear concealment
    local conceal_ns = vim.api.nvim_create_namespace('pairup_conceal')
    vim.api.nvim_buf_clear_namespace(bufnr, conceal_ns, 0, -1)

    -- vim.notify('Suggestion-only mode OFF - all content visible', vim.log.levels.INFO)
  end

  return suggestion_only_mode
end

-- Get follow mode status
function M.is_follow_mode()
  return follow_mode
end

-- Setup highlight groups with better visual distinction
function M.setup()
  -- Headers and UI elements
  vim.api.nvim_set_hl(0, 'PairupHeader', { fg = '#7c7c7c', bg = '#2a2a2a', bold = true })
  vim.api.nvim_set_hl(0, 'PairupSubHeader', { fg = '#6c6c6c', italic = true })
  vim.api.nvim_set_hl(0, 'PairupBorder', { fg = '#4a4a4a' })
  vim.api.nvim_set_hl(0, 'PairupHint', { fg = '#5c5c5c', italic = true })
  vim.api.nvim_set_hl(0, 'PairupLineNum', { fg = '#8a8a8a', bold = true })

  -- Suggestion content with clear visual distinction
  vim.api.nvim_set_hl(0, 'PairupAdd', { fg = '#98c379', bg = '#1e2a1e', italic = true })
  vim.api.nvim_set_hl(0, 'PairupDelete', { fg = '#e06c75', bg = '#2a1e1e', strikethrough = true })
  vim.api.nvim_set_hl(0, 'PairupChange', { fg = '#61afef', bg = '#1e1e2a', underline = true })

  -- Hidden line markers in suggestion-only mode
  vim.api.nvim_set_hl(0, 'PairupHiddenMarker', { fg = '#4a4a4a', italic = true })
end

-- Clear overlay at a specific line
function M.clear_overlay_at_line(bufnr, line_num)
  if not suggestions[bufnr] or not suggestions[bufnr][line_num] then
    return false
  end

  -- Remove from suggestions
  suggestions[bufnr][line_num] = nil

  -- Clear extmarks at this line
  local ns_id = vim.api.nvim_create_namespace('pairup_overlay')
  local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, { line_num - 1, 0 }, { line_num, 0 }, {})

  for _, mark in ipairs(marks) do
    vim.api.nvim_buf_del_extmark(bufnr, ns_id, mark[1])
  end

  return true
end

-- Get all suggestions from all buffers (for export)
function M.get_all_suggestions()
  return suggestions
end

return M
