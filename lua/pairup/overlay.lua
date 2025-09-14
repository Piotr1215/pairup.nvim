-- Virtual overlay for showing Claude's suggestions
local M = {}

local ns_id = vim.api.nvim_create_namespace('pairup_overlay')
local active_overlays = {}

-- Store suggestions for applying - indexed by extmark ID for stability
-- Format: suggestions[bufnr][extmark_id] = suggestion_data
local suggestions = {}
local hidden_overlays = {} -- Store overlays when toggled off
local follow_mode = false -- Auto-jump to new suggestions
local suggestion_only_mode = false -- Hide buffer, show only suggestions
local original_conceallevel = {}

-- Overlay states for staging
local OVERLAY_STATE = {
  PENDING = 'pending',
  ACCEPTED = 'accepted',
  REJECTED = 'rejected',
  EDITED = 'edited',
}

-- State emoji indicators
local STATE_EMOJI = {
  [OVERLAY_STATE.PENDING] = '⏳',
  [OVERLAY_STATE.ACCEPTED] = '✅',
  [OVERLAY_STATE.REJECTED] = '❌',
  [OVERLAY_STATE.EDITED] = '✏️',
}

-- Helper to find suggestion at current cursor position by checking extmarks
local function find_suggestion_at_cursor(bufnr)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line_num = cursor[1]

  -- First check for extmarks at current line
  local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, { line_num - 1, 0 }, { line_num, 0 }, {})

  if #marks > 0 then
    -- We have extmarks here - direct lookup by extmark ID
    local extmark_id = marks[1][1] -- Get the first extmark's ID
    local suggestion = suggestions[bufnr] and suggestions[bufnr][extmark_id]
    if suggestion then
      return suggestion, extmark_id
    end
  end

  -- If no direct extmark, check if we're within any multiline range
  for extmark_id, suggestion in pairs(suggestions[bufnr] or {}) do
    if suggestion.is_multiline then
      -- Get the current position of this extmark
      local extmark_pos = vim.api.nvim_buf_get_extmark_by_id(bufnr, ns_id, extmark_id, {})
      if #extmark_pos > 0 then
        local mark_line = extmark_pos[1] + 1
        local range_size = suggestion.end_line - suggestion.start_line
        if line_num >= mark_line and line_num <= mark_line + range_size then
          return suggestion, extmark_id
        end
      end
    end
  end

  return nil, nil
end

-- Helper to generate header with state emoji
local function generate_header(text, state)
  state = state or OVERLAY_STATE.PENDING
  local emoji = STATE_EMOJI[state]
  -- Put emoji at the end to avoid moving the border
  return text .. ' ' .. emoji
end

-- Store a suggestion for later application
local function store_suggestion(bufnr, line_num, old_text, new_text, reasoning, extmark_id)
  if not suggestions[bufnr] then
    suggestions[bufnr] = {}
  end
  suggestions[bufnr][extmark_id] = {
    old_text = old_text,
    new_text = new_text,
    line_num = line_num,
    reasoning = reasoning, -- Store reasoning for the suggestion
    extmark_id = extmark_id, -- Store extmark ID for tracking position
    state = OVERLAY_STATE.PENDING, -- Default state for staging
    edited_text = nil, -- Will store edited version if user edits
  }
end

-- Get all suggestions for a buffer
function M.get_suggestions(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  -- Transform suggestions from extmark_id keys to line number keys
  -- This maintains backward compatibility with code expecting line numbers
  local result = {}
  for extmark_id, suggestion in pairs(suggestions[bufnr] or {}) do
    -- Get current line position of the extmark
    local extmark_pos = vim.api.nvim_buf_get_extmark_by_id(bufnr, ns_id, extmark_id, {})
    if #extmark_pos > 0 then
      local line = extmark_pos[1] + 1 -- Convert 0-based to 1-based
      result[line] = suggestion
    end
  end

  return result
end

-- Get status indicator for statusline
function M.get_status()
  local bufnr = vim.api.nvim_get_current_buf()
  local count = 0

  for _, _ in pairs(suggestions[bufnr] or {}) do
    count = count + 1
  end

  if count > 0 then
    return string.format('󰄬 %d', count) -- Overlay icon + count
  end
  return ''
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

  -- Special handling for insertions - allow line_num to be line_count + 1
  -- This represents inserting after the last line
  local is_insertion = (old_text == nil)
  if is_insertion then
    if line_num < 1 or line_num > line_count + 1 then
      return false
    end
  else
    if line_num < 1 or line_num > line_count then
      return false
    end
  end

  -- If old_text not provided and not an insertion, get it from buffer
  if not is_insertion and (not old_text or old_text == '') then
    old_text = vim.api.nvim_buf_get_lines(bufnr, line_num - 1, line_num, false)[1] or ''
  end

  -- Clear any existing overlay on this line
  vim.api.nvim_buf_clear_namespace(bufnr, ns_id, line_num - 1, line_num)

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
      { { generate_header('╭─ Claude suggests removing:', OVERLAY_STATE.PENDING), 'PairupHeader' } },
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

    local extmark_id = vim.api.nvim_buf_set_extmark(bufnr, ns_id, line_num - 1, 0, {
      virt_lines = virt_lines,
      priority = 100,
    })

    -- Store the suggestion with the extmark ID
    store_suggestion(bufnr, line_num, old_text, new_text, reasoning, extmark_id)

  -- If it's an addition, show as virtual lines
  elseif old_text == nil or old_text == '' then
    local virt_lines = {
      { { generate_header('╭─ Claude suggests adding:', OVERLAY_STATE.PENDING), 'PairupHeader' } },
    }
    -- Add the new text line with border
    table.insert(virt_lines, vim.list_extend({ { '│ ', 'PairupBorder' } }, text_to_virt_line(new_text, 'PairupAdd')))

    if reasoning then
      table.insert(
        virt_lines,
        vim.list_extend({ { '│ ', 'PairupBorder' } }, text_to_virt_line('Reason: ' .. reasoning, 'PairupHint'))
      )
    end

    -- For insertions after the last line, place extmark at the last line with virt_lines_above = false
    local extmark_line = math.min(line_num - 1, line_count - 1)
    local extmark_opts = {
      virt_lines = virt_lines,
      priority = 100,
    }

    -- If inserting after the last line, show the virtual lines below the last line
    if line_num > line_count then
      extmark_opts.virt_lines_above = false
    end

    local extmark_id = vim.api.nvim_buf_set_extmark(bufnr, ns_id, extmark_line, 0, extmark_opts)

    -- Store the suggestion with the extmark ID
    store_suggestion(bufnr, line_num, old_text, new_text, reasoning, extmark_id)

  -- If it's a modification, show both old and new in a clear way
  else
    -- Build virtual lines with reasoning
    local virt_lines = {
      { { generate_header('╭─ Claude suggests changing:', OVERLAY_STATE.PENDING), 'PairupHeader' } },
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

    local extmark_id = vim.api.nvim_buf_set_extmark(bufnr, ns_id, line_num - 1, 0, {
      virt_lines = virt_lines,
      virt_lines_above = false,
      priority = 100,
    })

    -- Store the suggestion with the extmark ID
    store_suggestion(bufnr, line_num, old_text, new_text, reasoning, extmark_id)
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
    {
      {
        generate_header(
          '╭─ Claude suggests removing lines ' .. start_line .. '-' .. end_line .. ':',
          OVERLAY_STATE.PENDING
        ),
        'PairupHeader',
      },
    },
  }

  for _, line in ipairs(old_lines) do
    table.insert(virt_lines, { { '│ ', 'PairupBorder' }, { '- ', 'PairupDelete' }, { line, 'PairupDelete' } })
  end

  if reasoning then
    table.insert(virt_lines, { { '│ ', 'PairupBorder' }, { 'Reason: ' .. reasoning, 'PairupHint' } })
  end

  table.insert(virt_lines, { { '╰─', 'PairupBorder' } })

  -- Set the extmark
  local extmark_id = vim.api.nvim_buf_set_extmark(bufnr, ns_id, start_line - 1, 0, {
    virt_lines = virt_lines,
    virt_lines_above = false,
    priority = 100,
  })

  -- Track this as a deletion suggestion
  if not suggestions[bufnr] then
    suggestions[bufnr] = {}
  end

  suggestions[bufnr][extmark_id] = {
    line_num = start_line,
    start_line = start_line,
    end_line = end_line,
    old_lines = old_lines,
    new_lines = {}, -- Empty for deletion
    is_deletion = true,
    is_multiline = true,
    reasoning = reasoning,
    extmark_id = extmark_id,
    state = OVERLAY_STATE.PENDING, -- Default state for staging
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

  -- Special case: if trying to append at EOF or beyond
  -- and old_lines is empty/nil, this is an append operation
  local is_eof_append = (
    start_line >= line_count
    and end_line >= line_count
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
      { generate_header('╭─ Claude suggests adding at end of file:', OVERLAY_STATE.PENDING), 'PairupHeader' },
    })
  else
    -- Normal replacement header
    table.insert(virt_lines, {
      { generate_header('╭─ Claude suggests replacing lines ', OVERLAY_STATE.PENDING), 'PairupHeader' },
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

  -- Set the extmark at the start line (cap at last line for insertions beyond EOF)
  local extmark_line = math.min(start_line - 1, line_count - 1)
  local extmark_id = vim.api.nvim_buf_set_extmark(bufnr, ns_id, extmark_line, 0, {
    virt_lines = virt_lines,
    virt_lines_above = false,
    priority = 100,
  })

  -- Store multiline suggestion
  if not suggestions[bufnr] then
    suggestions[bufnr] = {}
  end
  suggestions[bufnr][extmark_id] = {
    is_multiline = true,
    start_line = start_line,
    end_line = end_line,
    old_lines = old_lines or {}, -- Ensure old_lines is never nil
    new_lines = new_lines or {}, -- Ensure new_lines is never nil
    reasoning = reasoning,
    extmark_id = extmark_id,
    state = OVERLAY_STATE.PENDING, -- Default state for staging
    edited_lines = nil, -- Will store edited version if user edits
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
  -- Default to current buffer if not specified
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  -- Check if buffer is valid before clearing
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  -- Clear all extmarks in the namespace
  vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)

  -- Clear suggestions for this buffer
  if suggestions[bufnr] then
    suggestions[bufnr] = {}
  end

  -- Also clear all tracked overlays if no specific buffer was passed
  if not bufnr then
    for _, overlay in ipairs(active_overlays) do
      if vim.api.nvim_buf_is_valid(overlay.bufnr) then
        vim.api.nvim_buf_clear_namespace(overlay.bufnr, ns_id, 0, -1)
      end
    end
  end

  -- Store current overlays for toggle
  hidden_overlays = vim.deepcopy(active_overlays)
  active_overlays = {}
end

-- Apply overlay at specific line
function M.apply_at_line(bufnr, line_num)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  -- SAFEGUARD: Validate buffer and line
  if not vim.api.nvim_buf_is_valid(bufnr) then
    vim.notify('Cannot apply overlay: invalid buffer', vim.log.levels.ERROR)
    return false
  end

  local line_count = vim.api.nvim_buf_line_count(bufnr)
  if line_num < 1 or line_num > line_count then
    vim.notify(
      string.format('Cannot apply overlay: line %d out of bounds (buffer has %d lines)', line_num, line_count),
      vim.log.levels.ERROR
    )
    return false
  end

  -- Find suggestion at this line using extmarks
  local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, { line_num - 1, 0 }, { line_num, 0 }, {})
  if #marks == 0 then
    return false
  end

  local extmark_id = marks[1][1]
  local suggestion = suggestions[bufnr] and suggestions[bufnr][extmark_id]

  if not suggestion then
    return false
  end

  -- Get current line from extmark position (it may have moved)
  local extmark_pos = vim.api.nvim_buf_get_extmark_by_id(bufnr, ns_id, extmark_id, {})
  local current_line = extmark_pos[1] and (extmark_pos[1] + 1) or line_num

  if suggestion.is_multiline then
    -- Apply multiline change using current position
    local end_line = current_line + (suggestion.end_line - suggestion.start_line)

    -- SAFEGUARD: Validate multiline bounds
    local line_count = vim.api.nvim_buf_line_count(bufnr)
    if current_line < 1 or end_line > line_count then
      vim.notify(
        string.format(
          'Cannot apply multiline overlay: invalid range %d-%d (buffer has %d lines)',
          current_line,
          end_line,
          line_count
        ),
        vim.log.levels.ERROR
      )
      return false
    end

    vim.api.nvim_buf_set_lines(bufnr, current_line - 1, end_line, false, suggestion.new_lines or {})
  else
    -- Apply single line change, handling embedded newlines
    local lines = vim.split(suggestion.new_text or '', '\n', { plain = true })
    vim.api.nvim_buf_set_lines(bufnr, current_line - 1, current_line, false, lines)
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
-- Refresh overlay display to show updated state emoji
function M.refresh_overlay_display(bufnr, extmark_id)
  local suggestion = suggestions[bufnr] and suggestions[bufnr][extmark_id]
  if not suggestion then
    return
  end

  -- Get current extmark details to preserve its position
  local extmark = vim.api.nvim_buf_get_extmark_by_id(bufnr, ns_id, extmark_id, { details = true })
  if #extmark == 0 then
    return
  end

  local line = extmark[1]
  local opts = extmark[3]

  -- Update the header in virt_lines with new emoji
  if opts.virt_lines and #opts.virt_lines > 0 then
    local header_line = opts.virt_lines[1]
    if header_line and #header_line > 0 then
      local header_text = header_line[1][1]
      -- Remove old emoji if present (now at the end) and add new one
      header_text = header_text:gsub(' [⏳✅❌✏️]$', '') -- Remove any existing emoji at end
      header_text = header_text .. ' ' .. STATE_EMOJI[suggestion.state]
      header_line[1][1] = header_text
    end
  end

  -- Delete old extmark
  vim.api.nvim_buf_del_extmark(bufnr, ns_id, extmark_id)

  -- Clean opts to only include valid keys for set_extmark
  local clean_opts = {
    virt_lines = opts.virt_lines,
    virt_lines_above = opts.virt_lines_above,
    virt_text = opts.virt_text,
    virt_text_pos = opts.virt_text_pos,
    priority = opts.priority or 100,
    id = extmark_id, -- Preserve the ID
  }

  -- Recreate with same ID to maintain reference
  local new_id = vim.api.nvim_buf_set_extmark(bufnr, ns_id, line, 0, clean_opts)

  -- Update the suggestion's extmark_id if it changed
  if new_id ~= extmark_id and suggestions[bufnr] then
    suggestions[bufnr][new_id] = suggestions[bufnr][extmark_id]
    suggestions[bufnr][new_id].extmark_id = new_id
    suggestions[bufnr][extmark_id] = nil
  end
end

-- Mark overlay at cursor with a specific state (for staging)
function M.mark_at_cursor(state)
  local bufnr = vim.api.nvim_get_current_buf()
  local suggestion, extmark_id = find_suggestion_at_cursor(bufnr)

  if not suggestion then
    vim.notify('No overlay at cursor', vim.log.levels.WARN)
    return false
  end

  -- Update the state
  suggestion.state = state

  -- Update the visual display to show new emoji
  M.refresh_overlay_display(bufnr, extmark_id)

  local state_name = state:gsub('^%l', string.upper)
  vim.notify(string.format('Overlay marked as %s %s', STATE_EMOJI[state], state_name), vim.log.levels.INFO)
  return true
end

-- Mark overlay at cursor as accepted (for staging)
function M.accept_staged()
  return M.mark_at_cursor(OVERLAY_STATE.ACCEPTED)
end

-- Mark overlay at cursor as rejected (for staging)
function M.reject_staged()
  return M.mark_at_cursor(OVERLAY_STATE.REJECTED)
end

-- Toggle overlay state at cursor
function M.toggle_state()
  local bufnr = vim.api.nvim_get_current_buf()
  local suggestion, _ = find_suggestion_at_cursor(bufnr)

  if not suggestion then
    vim.notify('No overlay at cursor', vim.log.levels.WARN)
    return false
  end

  -- Cycle through states: pending -> accepted -> rejected -> pending
  local next_state = {
    [OVERLAY_STATE.PENDING] = OVERLAY_STATE.ACCEPTED,
    [OVERLAY_STATE.ACCEPTED] = OVERLAY_STATE.REJECTED,
    [OVERLAY_STATE.REJECTED] = OVERLAY_STATE.PENDING,
    [OVERLAY_STATE.EDITED] = OVERLAY_STATE.ACCEPTED,
  }

  local new_state = next_state[suggestion.state] or OVERLAY_STATE.PENDING
  return M.mark_at_cursor(new_state)
end

function M.apply_at_cursor()
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local current_line = cursor[1]

  -- Use the helper to find suggestion at current position
  local suggestion, stored_line = find_suggestion_at_cursor(bufnr)

  -- Check if we have a stored suggestion for this line
  if suggestion then
    -- Get the current variant if variants exist
    local new_text = suggestion.new_text
    local new_lines = suggestion.new_lines

    if suggestion.variants and suggestion.current_variant then
      local current_variant = suggestion.variants[suggestion.current_variant]
      if suggestion.is_multiline then
        new_lines = current_variant.new_lines
      else
        new_text = current_variant.new_text
      end
    end

    if suggestion.is_multiline then
      -- For multiline, we need to find the current position of the extmark
      local extmark_pos = vim.api.nvim_buf_get_extmark_by_id(bufnr, ns_id, suggestion.extmark_id, {})
      if #extmark_pos > 0 then
        local start_line = extmark_pos[1] + 1

        -- CRITICAL FIX: Calculate number of lines to delete based on old_lines
        -- not on the original line range which might be wrong
        local lines_to_delete = suggestion.old_lines and #suggestion.old_lines or 0

        -- If no old_lines, this is an insertion, not a replacement
        if lines_to_delete == 0 then
          -- Insert at start_line without deleting anything
          vim.api.nvim_buf_set_lines(bufnr, start_line - 1, start_line - 1, false, new_lines or {})

          -- Clear the extmark
          vim.api.nvim_buf_del_extmark(bufnr, ns_id, suggestion.extmark_id)

          -- Remove from suggestions
          suggestions[bufnr][suggestion.extmark_id] = nil

          vim.notify('Applied insertion', vim.log.levels.INFO)
          return true
        end

        local end_line = start_line + lines_to_delete - 1

        -- SAFEGUARD: Validate multiline bounds before applying
        local line_count = vim.api.nvim_buf_line_count(bufnr)
        if start_line < 1 or end_line > line_count then
          vim.notify(
            string.format(
              'Cannot apply multiline overlay: invalid range %d-%d (buffer has %d lines)',
              start_line,
              end_line,
              line_count
            ),
            vim.log.levels.ERROR
          )
          return false
        end

        -- Clear extmarks BEFORE applying changes
        vim.api.nvim_buf_clear_namespace(bufnr, ns_id, start_line - 1, end_line)

        -- Apply multiline change at current position
        -- This replaces lines [start_line, end_line] with new_lines
        vim.api.nvim_buf_set_lines(bufnr, start_line - 1, end_line, false, new_lines or {})
      end
      -- vim.notify('Applied multiline suggestion', vim.log.levels.INFO)
    else
      -- Clear extmarks BEFORE applying changes at current line
      vim.api.nvim_buf_clear_namespace(bufnr, ns_id, current_line - 1, current_line)

      -- Apply single line change at current cursor position
      if new_text == nil or new_text == '' then
        if suggestion.old_text == nil then
          -- This is actually an empty insertion - do nothing
        else
          -- Delete the line
          vim.api.nvim_buf_set_lines(bufnr, current_line - 1, current_line, false, {})
          -- vim.notify('Deleted line ' .. current_line, vim.log.levels.INFO)
        end
      else
        -- Check if this is an insertion (old_text is nil)
        if suggestion.old_text == nil then
          -- This is an insertion - insert without removing
          local lines = vim.split(new_text, '\n', { plain = true })
          -- For insertions, we need to handle the case where we're inserting after the last line
          local line_count = vim.api.nvim_buf_line_count(bufnr)
          local insert_pos = math.min(current_line - 1, line_count)
          vim.api.nvim_buf_set_lines(bufnr, insert_pos, insert_pos, false, lines)
          -- vim.notify('Inserted at line ' .. current_line, vim.log.levels.INFO)
        else
          -- Replace the line, handling embedded newlines
          local lines = vim.split(new_text, '\n', { plain = true })
          vim.api.nvim_buf_set_lines(bufnr, current_line - 1, current_line, false, lines)
          -- vim.notify('Applied suggestion at line ' .. current_line, vim.log.levels.INFO)
        end
      end
    end

    -- Remove the suggestion immediately (use stored_line as key)
    suggestions[bufnr][stored_line] = nil

    -- Remove from active overlays
    for i, overlay in ipairs(active_overlays) do
      if overlay.bufnr == bufnr and overlay.line == stored_line then
        table.remove(active_overlays, i)
        break
      end
    end

    return true
  else
    -- Provide helpful error message with available overlay locations
    local all_overlays = {}
    for line_num, _ in pairs(suggestions[bufnr] or {}) do
      table.insert(all_overlays, line_num)
    end
    table.sort(all_overlays)

    if #all_overlays > 0 then
      vim.notify(
        string.format(
          'No overlay at line %d. Available at lines: %s\nTip: Use :PairNext to jump to nearest',
          current_line or cursor[1],
          table.concat(all_overlays, ', ')
        ),
        vim.log.levels.WARN
      )
    else
      vim.notify('No overlays in current buffer', vim.log.levels.INFO)
    end
    return false
  end
end

-- Reject suggestion at cursor position (just clear it)
function M.reject_at_cursor()
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local current_line = cursor[1]

  -- Use the helper to find suggestion at current position
  local suggestion, stored_line = find_suggestion_at_cursor(bufnr)

  -- Check if we have a suggestion at this line
  if suggestion then
    if suggestion.is_multiline then
      -- For multiline, find current position
      local extmark_pos = vim.api.nvim_buf_get_extmark_by_id(bufnr, ns_id, suggestion.extmark_id, {})
      if #extmark_pos > 0 then
        local start_line = extmark_pos[1] + 1
        local end_line = start_line + (suggestion.end_line - suggestion.start_line)
        -- Clear multiline overlay at current position
        vim.api.nvim_buf_clear_namespace(bufnr, ns_id, start_line - 1, end_line)
      end
      -- vim.notify('Rejected multiline suggestion', vim.log.levels.INFO)
    else
      -- Clear single line overlay at current cursor position
      vim.api.nvim_buf_clear_namespace(bufnr, ns_id, current_line - 1, current_line)
      -- vim.notify('Rejected suggestion at line ' .. current_line, vim.log.levels.INFO)
    end

    -- Remove from stored suggestions (use stored_line as key)
    suggestions[bufnr][stored_line] = nil

    -- Remove from active overlays
    for i, overlay in ipairs(active_overlays) do
      if overlay.bufnr == bufnr and overlay.line == stored_line then
        table.remove(active_overlays, i)
        break
      end
    end

    return true
  else
    -- Provide helpful error message with available overlay locations
    local all_overlays = {}
    for line_num, _ in pairs(suggestions[bufnr] or {}) do
      table.insert(all_overlays, line_num)
    end
    table.sort(all_overlays)

    if #all_overlays > 0 then
      vim.notify(
        string.format(
          'No overlay at line %d. Available at lines: %s\nTip: Use :PairNext to jump to nearest',
          current_line or cursor[1],
          table.concat(all_overlays, ', ')
        ),
        vim.log.levels.WARN
      )
    else
      vim.notify('No overlays in current buffer', vim.log.levels.INFO)
    end
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

-- Accept all overlays in the buffer
function M.accept_all_overlays()
  local bufnr = vim.api.nvim_get_current_buf()
  local accepted_count = 0

  -- Get all extmarks with suggestions
  local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, 0, -1, {})

  -- Sort extmarks in reverse order (bottom to top) to avoid line number shifts
  table.sort(extmarks, function(a, b)
    return a[2] > b[2] -- Sort by line number (descending)
  end)

  -- Accept each overlay
  for _, mark in ipairs(extmarks) do
    local extmark_id = mark[1]
    local line_num = mark[2] + 1 -- Convert to 1-based

    -- Check if we have a suggestion for this extmark
    if suggestions[bufnr] and suggestions[bufnr][extmark_id] then
      -- In headless mode or if no window, accept directly without cursor movement
      local has_window = #vim.api.nvim_list_wins() > 0
      if has_window then
        -- Move cursor to the line
        vim.api.nvim_win_set_cursor(0, { line_num, 0 })
        -- Accept the overlay
        if M.apply_at_cursor() then
          accepted_count = accepted_count + 1
        end
      else
        -- Headless mode - apply directly
        local suggestion = suggestions[bufnr][extmark_id]
        if suggestion.multiline then
          -- Apply multiline suggestion
          vim.api.nvim_buf_set_lines(
            bufnr,
            suggestion.start_line - 1,
            suggestion.end_line,
            false,
            suggestion.replacement_lines[suggestion.current_variant]
          )
        else
          -- Apply single line suggestion
          vim.api.nvim_buf_set_lines(bufnr, line_num - 1, line_num, false, { suggestion.replacement })
        end

        -- Clean up the suggestion
        vim.api.nvim_buf_del_extmark(bufnr, ns_id, extmark_id)
        suggestions[bufnr][extmark_id] = nil
        accepted_count = accepted_count + 1
      end
    end
  end

  if accepted_count > 0 then
    vim.notify(string.format('Accepted %d overlays', accepted_count), vim.log.levels.INFO)
  else
    vim.notify('No overlays to accept', vim.log.levels.WARN)
  end

  return accepted_count
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

-- Process all staged overlays atomically
function M.process_overlays(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local buffer_suggestions = suggestions[bufnr]

  if not buffer_suggestions then
    vim.notify('No overlays to process', vim.log.levels.INFO)
    return
  end

  -- Check for unprocessed overlays
  local unprocessed = {}
  local to_apply = {}

  for extmark_id, suggestion in pairs(buffer_suggestions) do
    if suggestion.state == OVERLAY_STATE.PENDING then
      table.insert(unprocessed, suggestion)
    elseif suggestion.state ~= OVERLAY_STATE.REJECTED then
      -- Accepted or edited overlays will be applied
      table.insert(to_apply, suggestion)
    end
  end

  -- If there are unprocessed overlays, jump to the first one
  if #unprocessed > 0 then
    local first_unprocessed = unprocessed[1]
    local extmark = vim.api.nvim_buf_get_extmark_by_id(bufnr, ns_id, first_unprocessed.extmark_id, {})
    if #extmark > 0 then
      vim.api.nvim_win_set_cursor(0, { extmark[1] + 1, 0 })
    end
    vim.notify(
      string.format('Found %d unprocessed overlays. Please mark them first.', #unprocessed),
      vim.log.levels.WARN
    )
    return
  end

  -- Build a map of all changes to apply
  local changes = {} -- { line_num = { type = "insert/replace/delete", lines = {...} } }
  local applied_count = 0
  local rejected_count = 0

  -- Collect all changes
  for extmark_id, suggestion in pairs(buffer_suggestions) do
    if suggestion.state == OVERLAY_STATE.REJECTED then
      -- Just count rejected and remove extmark
      vim.api.nvim_buf_del_extmark(bufnr, ns_id, extmark_id)
      rejected_count = rejected_count + 1
    elseif suggestion.state ~= OVERLAY_STATE.PENDING then
      -- Get current position of extmark
      local extmark = vim.api.nvim_buf_get_extmark_by_id(bufnr, ns_id, suggestion.extmark_id, {})
      if #extmark > 0 then
        local line = extmark[1] + 1 -- Convert to 1-indexed

        -- For insertions, use the stored line number if it's beyond the buffer
        -- (insertions after the last line have extmark at last line but stored line is last+1)
        if suggestion.old_text == nil and suggestion.line_num and suggestion.line_num > line then
          line = suggestion.line_num
        end

        -- Determine what text to apply
        local text_to_apply = suggestion.new_text
        local lines_to_apply = suggestion.new_lines

        if suggestion.state == OVERLAY_STATE.EDITED then
          text_to_apply = suggestion.edited_text or text_to_apply
          lines_to_apply = suggestion.edited_lines or lines_to_apply
        end

        -- Store the change
        if suggestion.is_multiline then
          -- For multiline insertions beyond EOF, use stored start_line
          if
            (not suggestion.old_lines or #suggestion.old_lines == 0 or suggestion.old_lines[1] == '')
            and suggestion.start_line
            and suggestion.start_line > line
          then
            line = suggestion.start_line
          end
          changes[line] = {
            type = (suggestion.old_lines and #suggestion.old_lines > 0 and suggestion.old_lines[1] ~= '') and 'replace'
              or 'insert',
            lines = lines_to_apply,
            old_line_count = suggestion.old_lines and #suggestion.old_lines or 0,
            extmark_id = extmark_id,
          }
        else
          if suggestion.old_text == nil then
            -- Insertion
            changes[line] = {
              type = 'insert',
              lines = vim.split(text_to_apply, '\n', { plain = true }),
              extmark_id = extmark_id,
            }
          elseif text_to_apply == nil or text_to_apply == '' then
            -- Deletion
            changes[line] = {
              type = 'delete',
              lines = {},
              extmark_id = extmark_id,
            }
          else
            -- Replacement
            changes[line] = {
              type = 'replace',
              lines = vim.split(text_to_apply, '\n', { plain = true }),
              old_line_count = 1,
              extmark_id = extmark_id,
            }
          end
        end
        applied_count = applied_count + 1
      end
    end
  end

  -- Now build the new buffer content atomically
  local current_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local new_lines = {}

  -- Create a sorted list of all operations
  local operations = {}
  for line_num, change in pairs(changes) do
    table.insert(operations, { line = line_num, change = change })
  end
  -- Sort operations from bottom to top for easier processing
  table.sort(operations, function(a, b)
    return a.line > b.line
  end)

  -- Apply changes from bottom to top to avoid line shifting issues
  local result_lines = vim.list_extend({}, current_lines) -- Copy current lines

  for _, op in ipairs(operations) do
    local line = op.line
    local change = op.change

    if change.type == 'insert' then
      -- Insert new lines at the position
      -- For line > #result_lines, append at end
      local insert_pos = math.min(line, #result_lines + 1)
      for i = #change.lines, 1, -1 do
        table.insert(result_lines, insert_pos, change.lines[i])
      end
    elseif change.type == 'delete' then
      -- Delete the line if it exists
      if line <= #result_lines then
        table.remove(result_lines, line)
      end
    elseif change.type == 'replace' then
      -- Replace line(s) with new content
      local lines_to_remove = change.old_line_count or 1
      -- Remove old lines
      for _ = 1, lines_to_remove do
        if line <= #result_lines then
          table.remove(result_lines, line)
        end
      end
      -- Insert new lines
      for i = #change.lines, 1, -1 do
        table.insert(result_lines, line, change.lines[i])
      end
    end

    -- Remove the extmark
    vim.api.nvim_buf_del_extmark(bufnr, ns_id, change.extmark_id)
  end

  new_lines = result_lines

  -- Replace entire buffer content atomically
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, new_lines)

  -- Clear suggestions for this buffer
  suggestions[bufnr] = {}

  -- Save the buffer
  if vim.api.nvim_buf_get_name(bufnr) ~= '' then
    vim.bo[bufnr].modified = true
    vim.cmd('write')
  end

  vim.notify(
    string.format('Processed overlays: %d applied, %d rejected', applied_count, rejected_count),
    vim.log.levels.INFO
  )
end

-- Find next unprocessed overlay
function M.next_unprocessed(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local buffer_suggestions = suggestions[bufnr]

  if not buffer_suggestions then
    vim.notify('No overlays to navigate', vim.log.levels.INFO)
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local current_line = cursor[1]

  -- Find all unprocessed overlays and their positions
  local unprocessed_marks = {}
  for extmark_id, suggestion in pairs(buffer_suggestions) do
    if suggestion.state == OVERLAY_STATE.PENDING then
      local extmark = vim.api.nvim_buf_get_extmark_by_id(bufnr, ns_id, extmark_id, {})
      if #extmark > 0 then
        table.insert(unprocessed_marks, { line = extmark[1] + 1, id = extmark_id })
      end
    end
  end

  if #unprocessed_marks == 0 then
    vim.notify('No unprocessed overlays found', vim.log.levels.INFO)
    return
  end

  -- Sort by line number
  table.sort(unprocessed_marks, function(a, b)
    return a.line < b.line
  end)

  -- Find next one after current position
  for _, mark in ipairs(unprocessed_marks) do
    if mark.line > current_line then
      vim.api.nvim_win_set_cursor(0, { mark.line, 0 })
      vim.notify(string.format('Jumped to unprocessed overlay at line %d', mark.line), vim.log.levels.INFO)
      return
    end
  end

  -- Wrap around to first unprocessed
  vim.api.nvim_win_set_cursor(0, { unprocessed_marks[1].line, 0 })
  vim.notify(
    string.format('Wrapped to first unprocessed overlay at line %d', unprocessed_marks[1].line),
    vim.log.levels.INFO
  )
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

  -- Setup autocmd to handle undo - restore suggestion if it was applied
  vim.api.nvim_create_autocmd('TextChanged', {
    group = vim.api.nvim_create_augroup('PairupOverlayUndo', { clear = true }),
    callback = function()
      local bufnr = vim.api.nvim_get_current_buf()
      if suggestions[bufnr] then
        for extmark_id, suggestion in pairs(suggestions[bufnr]) do
          if suggestion.applied then
            -- Check if this specific extmark still exists
            local extmark_pos = vim.api.nvim_buf_get_extmark_by_id(bufnr, ns_id, extmark_id, {})
            if #extmark_pos > 0 then
              -- Undo detected - mark as not applied
              suggestion.applied = false
            end
          end
        end
      end
    end,
  })
end

-- Clear overlay at a specific line
function M.clear_overlay_at_line(bufnr, line_num)
  -- Find suggestion at this line using extmarks
  local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, { line_num - 1, 0 }, { line_num, 0 }, {})
  if #marks == 0 then
    return false
  end

  local extmark_id = marks[1][1]
  if not suggestions[bufnr] or not suggestions[bufnr][extmark_id] then
    return false
  end

  -- Remove from suggestions
  suggestions[bufnr][extmark_id] = nil

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

-- =============================================================================
-- VARIANT SUPPORT FUNCTIONS
-- =============================================================================

-- Store a suggestion with multiple variants
local function store_suggestion_variants(bufnr, line_num, old_text, variants, extmark_id)
  if not suggestions[bufnr] then
    suggestions[bufnr] = {}
  end

  -- Convert variants to internal format
  local formatted_variants = {}
  for i, variant in ipairs(variants) do
    table.insert(formatted_variants, {
      old_text = old_text,
      new_text = variant.new_text,
      reasoning = variant.reasoning,
      is_active = i == 1,
    })
  end

  suggestions[bufnr][extmark_id] = {
    variants = formatted_variants,
    current_variant = 1,
    line_num = line_num,
    -- Keep backward compat fields pointing to first variant
    old_text = old_text,
    new_text = variants[1].new_text,
    reasoning = variants[1].reasoning,
    extmark_id = extmark_id,
  }
end

-- Show suggestion with multiple variants
function M.show_suggestion_variants(bufnr, line_num, old_text, variants)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  -- Validate inputs
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end

  local line_count = vim.api.nvim_buf_line_count(bufnr)
  if line_num < 1 or line_num > line_count then
    return false
  end

  if not variants or #variants == 0 then
    return false
  end

  -- Create an initial extmark to get the ID
  local extmark_id = vim.api.nvim_buf_set_extmark(bufnr, ns_id, line_num - 1, 0, {
    virt_text = { { '', '' } }, -- Empty placeholder
    priority = 100,
  })

  -- Store the variants with the extmark ID
  store_suggestion_variants(bufnr, line_num, old_text, variants, extmark_id)

  -- Display the first variant (which will update the extmark)
  M.display_variant(bufnr, line_num, 1)

  return true
end

-- Display a specific variant
function M.display_variant(bufnr, line_num, variant_index)
  -- Find suggestion at this line using extmarks
  local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, { line_num - 1, 0 }, { line_num, 0 }, {})
  if #marks == 0 then
    return false
  end

  local extmark_id = marks[1][1]
  local suggestion = suggestions[bufnr] and suggestions[bufnr][extmark_id]
  if not suggestion or not suggestion.variants then
    return false
  end

  local variant = suggestion.variants[variant_index]
  if not variant then
    return false
  end

  -- Clear existing overlay
  vim.api.nvim_buf_clear_namespace(bufnr, ns_id, line_num - 1, line_num)

  -- Helper function to create virt_line from text
  local function text_to_virt_line(text, highlight)
    local text_str = tostring(text or '')
    local clean_text = text_str:gsub('\n', '↵')
    return { { clean_text, highlight } }
  end

  -- Build virtual lines with variant indicator
  local total_variants = #suggestion.variants
  local variant_indicator = total_variants > 1 and string.format(' [%d/%d]', variant_index, total_variants) or ''

  local virt_lines = {
    {
      { '╭─ Claude suggests changing', 'PairupHeader' },
      { variant_indicator, 'PairupLineNum' },
      { ':', 'PairupHeader' },
    },
  }

  -- Add old text with delete marker
  table.insert(
    virt_lines,
    vim.list_extend(
      { { '│ ', 'PairupBorder' }, { '- ', 'PairupDelete' } },
      text_to_virt_line(variant.old_text, 'PairupDelete')
    )
  )

  -- Add new text with add marker
  table.insert(
    virt_lines,
    vim.list_extend(
      { { '│ ', 'PairupBorder' }, { '+ ', 'PairupAdd' } },
      text_to_virt_line(variant.new_text, 'PairupAdd')
    )
  )

  if variant.reasoning then
    table.insert(virt_lines, { { '│ ', 'PairupBorder' }, { 'Reason: ' .. variant.reasoning, 'PairupHint' } })
  end

  table.insert(virt_lines, { { '╰─', 'PairupBorder' } })

  local extmark_id = vim.api.nvim_buf_set_extmark(bufnr, ns_id, line_num - 1, 0, {
    virt_lines = virt_lines,
    virt_lines_above = false,
    priority = 100,
  })

  -- Update the stored suggestion - need to move it from old extmark_id key to new one
  if suggestions[bufnr] then
    -- Find the suggestion at this line (it may have a different extmark_id)
    for stored_id, suggestion in pairs(suggestions[bufnr]) do
      if suggestion.line_num == line_num and suggestion.variants then
        -- Move suggestion to new extmark_id key if needed
        if stored_id ~= extmark_id then
          suggestions[bufnr][extmark_id] = suggestion
          suggestions[bufnr][stored_id] = nil
        end
        suggestion.extmark_id = extmark_id
        suggestion.current_variant = variant_index
        break
      end
    end
  end

  -- Track this overlay
  local exists = false
  for _, overlay in ipairs(active_overlays) do
    if overlay.bufnr == bufnr and overlay.line == line_num then
      exists = true
      break
    end
  end
  if not exists then
    table.insert(active_overlays, { bufnr = bufnr, line = line_num })
  end

  return true
end

-- Cycle through variants (direction: 1 for forward, -1 for backward)
function M.cycle_variant(bufnr, line_num, direction)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  direction = direction or 1

  -- Find suggestion at this line using extmarks
  local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, { line_num - 1, 0 }, { line_num, 0 }, {})
  if #marks == 0 then
    return false
  end

  local extmark_id = marks[1][1]
  local suggestion = suggestions[bufnr] and suggestions[bufnr][extmark_id]
  if not suggestion or not suggestion.variants then
    return false
  end

  local total_variants = #suggestion.variants
  if total_variants <= 1 then
    return false -- No cycling needed
  end

  -- Calculate new index with wrapping
  local new_index = suggestion.current_variant + direction
  if new_index > total_variants then
    new_index = 1
  elseif new_index < 1 then
    new_index = total_variants
  end

  -- Update current variant
  suggestion.current_variant = new_index

  -- Update backward compat fields
  local current = suggestion.variants[new_index]
  if suggestion.is_multiline then
    suggestion.new_lines = current.new_lines
    suggestion.reasoning = current.reasoning
  else
    suggestion.new_text = current.new_text
    suggestion.reasoning = current.reasoning
  end

  -- Update display
  if suggestion.is_multiline then
    M.display_multiline_variant(bufnr, line_num, new_index)
  else
    M.display_variant(bufnr, line_num, new_index)
  end

  -- Call update function if it exists
  if M.update_variant_display then
    M.update_variant_display(bufnr, line_num, new_index)
  end

  return true
end

-- Show multiline suggestion with variants
function M.show_multiline_suggestion_variants(bufnr, start_line, end_line, old_lines, variants)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  -- Validate inputs
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end

  local line_count = vim.api.nvim_buf_line_count(bufnr)
  if start_line < 1 or start_line > line_count or end_line < start_line or end_line > line_count then
    return false
  end

  if not variants or #variants == 0 then
    return false
  end

  -- Store multiline variants
  if not suggestions[bufnr] then
    suggestions[bufnr] = {}
  end

  -- If old_lines not provided, fetch from buffer
  if not old_lines then
    old_lines = vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false)
  end

  -- Convert variants to internal format
  local formatted_variants = {}
  for i, variant in ipairs(variants) do
    table.insert(formatted_variants, {
      old_lines = old_lines,
      new_lines = variant.new_lines or {}, -- Default to empty array if nil
      reasoning = variant.reasoning,
      is_active = i == 1,
    })
  end

  -- We need to create an extmark first to get the ID
  -- Create a temporary extmark that will be updated by display_multiline_variant
  local extmark_id = vim.api.nvim_buf_set_extmark(bufnr, ns_id, start_line - 1, 0, {
    virt_text = { { '', '' } }, -- Empty placeholder
    priority = 100,
  })

  suggestions[bufnr][extmark_id] = {
    is_multiline = true,
    start_line = start_line,
    end_line = end_line,
    variants = formatted_variants,
    current_variant = 1,
    -- Backward compat
    old_lines = old_lines,
    new_lines = variants[1].new_lines,
    reasoning = variants[1].reasoning,
    extmark_id = extmark_id,
  }

  -- Display first variant (which will update the extmark)
  M.display_multiline_variant(bufnr, start_line, 1)

  return true
end

-- Display a specific multiline variant
function M.display_multiline_variant(bufnr, start_line, variant_index)
  -- Find suggestion at this line using extmarks
  local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, { start_line - 1, 0 }, { start_line, 0 }, {})
  if #marks == 0 then
    return false
  end

  local extmark_id = marks[1][1]
  local suggestion = suggestions[bufnr] and suggestions[bufnr][extmark_id]
  if not suggestion or not suggestion.is_multiline or not suggestion.variants then
    return false
  end

  local variant = suggestion.variants[variant_index]
  if not variant then
    return false
  end

  -- Clear existing overlay
  vim.api.nvim_buf_clear_namespace(bufnr, ns_id, start_line - 1, suggestion.end_line)

  -- Build virtual lines with variant indicator
  local total_variants = #suggestion.variants
  local variant_indicator = total_variants > 1 and string.format(' [%d/%d]', variant_index, total_variants) or ''

  local virt_lines = {
    {
      { generate_header('╭─ Claude suggests replacing lines ', OVERLAY_STATE.PENDING), 'PairupHeader' },
      { tostring(start_line) .. '-' .. tostring(suggestion.end_line), 'PairupLineNum' },
      { variant_indicator, 'PairupLineNum' },
      { ':', 'PairupHeader' },
    },
  }

  -- Show old lines
  table.insert(virt_lines, { { '│ ', 'PairupBorder' }, { '── Original ──', 'PairupSubHeader' } })
  for _, line in ipairs(variant.old_lines) do
    table.insert(virt_lines, { { '│ ', 'PairupBorder' }, { line, 'PairupDelete' } })
  end

  -- Show new lines
  table.insert(virt_lines, { { '│ ', 'PairupBorder' }, { '── Suggestion ──', 'PairupSubHeader' } })
  if variant.new_lines then
    for _, line in ipairs(variant.new_lines) do
      table.insert(virt_lines, { { '│ ', 'PairupBorder' }, { line, 'PairupAdd' } })
    end
  else
    table.insert(virt_lines, { { '│ ', 'PairupBorder' }, { '[No replacement lines]', 'PairupHint' } })
  end

  if variant.reasoning then
    table.insert(virt_lines, { { '│ ', 'PairupBorder' } })
    table.insert(virt_lines, { { '│ ', 'PairupBorder' }, { 'Reason: ' .. variant.reasoning, 'PairupHint' } })
  end

  table.insert(virt_lines, { { '╰─', 'PairupBorder' } })

  local extmark_id = vim.api.nvim_buf_set_extmark(bufnr, ns_id, start_line - 1, 0, {
    virt_lines = virt_lines,
    virt_lines_above = false,
    priority = 100,
  })

  -- Update stored suggestion - need to move it from old extmark_id key to new one
  if suggestions[bufnr] then
    -- Find the suggestion with the old extmark_id (passed in via marks lookup)
    local old_extmark_id = extmark_id
    for stored_id, suggestion in pairs(suggestions[bufnr]) do
      if suggestion.start_line == start_line and suggestion.is_multiline then
        -- Move suggestion to new extmark_id key
        if stored_id ~= extmark_id then
          suggestions[bufnr][extmark_id] = suggestion
          suggestions[bufnr][stored_id] = nil
        end
        suggestion.extmark_id = extmark_id
        break
      end
    end
  end

  return true
end

-- Get all suggestions from all buffers (for export)
function M.get_all_suggestions()
  return suggestions
end

-- Check if buffer has any pending overlays
function M.has_pending_overlays(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local buffer_suggestions = suggestions[bufnr]

  if not buffer_suggestions then
    return false
  end

  for _, suggestion in pairs(buffer_suggestions) do
    if suggestion.state == OVERLAY_STATE.PENDING then
      return true
    end
  end

  return false
end

return M
