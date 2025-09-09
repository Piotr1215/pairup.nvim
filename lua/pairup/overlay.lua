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
local function store_suggestion(bufnr, line_num, old_text, new_text)
  if not suggestions[bufnr] then
    suggestions[bufnr] = {}
  end
  suggestions[bufnr][line_num] = {
    old_text = old_text,
    new_text = new_text,
  }
end

-- Show a suggestion as virtual text
function M.show_suggestion(bufnr, line_num, old_text, new_text)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  -- Clear any existing overlay on this line
  vim.api.nvim_buf_clear_namespace(bufnr, ns_id, line_num - 1, line_num)

  -- Store the suggestion for later application
  store_suggestion(bufnr, line_num, old_text, new_text)

  -- If it's a deletion, show strikethrough
  if new_text == nil or new_text == '' then
    -- Show deletion with strikethrough
    vim.api.nvim_buf_set_extmark(bufnr, ns_id, line_num - 1, 0, {
      virt_lines = {
        { { '╭─ Claude suggests removing:', 'PairupHeader' } },
        { { '│ ', 'PairupBorder' }, { old_text, 'PairupDelete' } },
      },
      priority = 100,
    })
  -- If it's an addition, show as virtual lines
  elseif old_text == nil or old_text == '' then
    vim.api.nvim_buf_set_extmark(bufnr, ns_id, line_num - 1, 0, {
      virt_lines = {
        { { '╭─ Claude suggests adding:', 'PairupHeader' } },
        { { '│ ', 'PairupBorder' }, { new_text, 'PairupAdd' } },
      },
      priority = 100,
    })
  -- If it's a modification, show both old and new in a clear way
  else
    -- Show both original and suggestion as virtual lines below the current line
    vim.api.nvim_buf_set_extmark(bufnr, ns_id, line_num - 1, 0, {
      virt_lines = {
        { { '╭─ Claude suggests changing:', 'PairupHeader' } },
        { { '│ ', 'PairupBorder' }, { '- ', 'PairupDelete' }, { old_text, 'PairupDelete' } },
        { { '│ ', 'PairupBorder' }, { '+ ', 'PairupAdd' }, { new_text, 'PairupAdd' } },
        { { '╰─', 'PairupBorder' } },
      },
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
end

-- Show multiline suggestion
function M.show_multiline_suggestion(bufnr, start_line, end_line, old_lines, new_lines)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  -- Clear any existing overlays in the range
  vim.api.nvim_buf_clear_namespace(bufnr, ns_id, start_line - 1, end_line)

  -- Build virtual lines for the suggestion
  local virt_lines = {
    {
      { '╭─ Claude suggests replacing lines ', 'PairupHeader' },
      { tostring(start_line) .. '-' .. tostring(end_line), 'PairupLineNum' },
      { ':', 'PairupHeader' },
    },
  }

  -- Show old lines
  if old_lines and #old_lines > 0 then
    table.insert(virt_lines, { { '│ ', 'PairupBorder' }, { '── Original ──', 'PairupSubHeader' } })
    for _, line in ipairs(old_lines) do
      table.insert(virt_lines, { { '│ ', 'PairupBorder' }, { '  ', '' }, { line, 'PairupDelete' } })
    end
  end

  -- Show new lines
  if new_lines and #new_lines > 0 then
    table.insert(virt_lines, { { '│ ', 'PairupBorder' }, { '── Suggestion ──', 'PairupSubHeader' } })
    for _, line in ipairs(new_lines) do
      table.insert(virt_lines, { { '│ ', 'PairupBorder' }, { '  ', '' }, { line, 'PairupAdd' } })
    end
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
  }

  -- Track this overlay
  table.insert(active_overlays, { bufnr = bufnr, line = start_line, is_multiline = true, end_line = end_line })

  -- Auto-jump if follow mode is enabled (find the main window)
  if follow_mode then
    vim.schedule(function()
      -- Find window containing the target buffer
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_get_buf(win) == bufnr then
          vim.api.nvim_set_current_win(win)
          pcall(vim.api.nvim_win_set_cursor, win, { start_line, 0 })
          break
        end
      end
    end)
  end
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
    vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
    -- Don't clear suggestions, keep them for toggle
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
      local marks = vim.api.nvim_buf_get_extmarks(
        bufnr,
        ns_id,
        { suggestion.start_line - 1, 0 },
        { suggestion.end_line, 0 },
        {}
      )
      for _, mark in ipairs(marks) do
        if mark[2] >= suggestion.start_line - 1 and mark[2] < suggestion.end_line then
          vim.api.nvim_buf_del_extmark(bufnr, ns_id, mark[1])
        end
      end
      vim.notify('Applied multiline suggestion', vim.log.levels.INFO)
    else
      -- Apply single line change
      local new_text = suggestion.new_text
      if new_text == nil or new_text == '' then
        -- Delete the line
        vim.api.nvim_buf_set_lines(bufnr, line_num - 1, line_num, false, {})
        vim.notify('Deleted line ' .. line_num, vim.log.levels.INFO)
      else
        -- Replace the line
        vim.api.nvim_buf_set_lines(bufnr, line_num - 1, line_num, false, { new_text })
        vim.notify('Applied suggestion at line ' .. line_num, vim.log.levels.INFO)
      end
      -- Clear this overlay completely
      -- Get all extmarks on this line and a few lines around it (for virtual text)
      local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, { line_num - 1, 0 }, { line_num + 3, 0 }, {})
      for _, mark in ipairs(marks) do
        -- Only delete marks that start at our line
        if mark[2] == line_num - 1 then
          vim.api.nvim_buf_del_extmark(bufnr, ns_id, mark[1])
        end
      end
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
      vim.notify('Rejected multiline suggestion', vim.log.levels.INFO)
    else
      -- Clear single line overlay
      vim.api.nvim_buf_clear_namespace(bufnr, ns_id, line_num - 1, line_num)
      vim.notify('Rejected suggestion at line ' .. line_num, vim.log.levels.INFO)
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
    vim.notify('No overlays found', vim.log.levels.WARN)
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
    vim.notify('Moved to next suggestion', vim.log.levels.INFO)
  else
    vim.notify('No more suggestions', vim.log.levels.INFO)
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
    vim.notify('Moved to previous suggestion', vim.log.levels.INFO)
  else
    vim.notify('No previous suggestions', vim.log.levels.INFO)
  end
end

-- Toggle overlays on/off
function M.toggle()
  local bufnr = vim.api.nvim_get_current_buf()
  local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, 0, -1, {})

  if #marks > 0 then
    -- Hide overlays
    M.clear_overlays(bufnr)
    vim.notify('Pairup overlay hidden', vim.log.levels.INFO)
  else
    -- Restore hidden overlays
    if #hidden_overlays > 0 then
      for _, overlay in ipairs(hidden_overlays) do
        if overlay.bufnr == bufnr and suggestions[bufnr] and suggestions[bufnr][overlay.line] then
          local s = suggestions[bufnr][overlay.line]
          if s.is_multiline then
            M.show_multiline_suggestion(bufnr, s.start_line, s.end_line, s.old_lines, s.new_lines)
          else
            M.show_suggestion(bufnr, overlay.line, s.old_text, s.new_text)
          end
        end
      end
      vim.notify('Pairup overlay restored', vim.log.levels.INFO)
    else
      vim.notify('No overlay to show', vim.log.levels.INFO)
    end
  end
end

-- Toggle follow mode
function M.toggle_follow_mode()
  follow_mode = not follow_mode
  if follow_mode then
    vim.notify('Overlay follow mode enabled - will jump to new suggestions', vim.log.levels.INFO)
  else
    vim.notify('Overlay follow mode disabled', vim.log.levels.INFO)
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

    vim.notify('Suggestion-only mode ON - showing only lines with suggestions', vim.log.levels.INFO)
  else
    -- Clear concealment
    local conceal_ns = vim.api.nvim_create_namespace('pairup_conceal')
    vim.api.nvim_buf_clear_namespace(bufnr, conceal_ns, 0, -1)

    vim.notify('Suggestion-only mode OFF - all content visible', vim.log.levels.INFO)
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

return M
