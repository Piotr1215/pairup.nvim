-- Direct marker application (no overlays, just apply changes)
local M = {}

-- Parse markers and apply them directly
function M.parse_and_apply(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  -- Find marker section at bottom of file
  local marker_start_idx = nil
  for i = #lines, 1, -1 do
    if lines[i]:match('^%-%- CLAUDE:MARKERS:START %-%-$') then
      marker_start_idx = i
      break
    end
  end

  if not marker_start_idx then
    vim.notify('No Claude markers found', vim.log.levels.WARN)
    return 0
  end

  -- Parse all markers
  local markers = {}
  local i = marker_start_idx + 1

  while i <= #lines do
    local line = lines[i]

    -- Check for end of marker section
    if line:match('^%-%- CLAUDE:MARKERS:END %-%-$') then
      break
    end

    -- Check for marker header (allow negative count for deletions)
    local target_line, count, reasoning = line:match('^CLAUDE:MARKER%-(%d+),(%-?%d+)%s*|%s*(.+)$')

    if target_line and count and reasoning then
      target_line = tonumber(target_line)
      count = tonumber(count)

      -- Collect replacement lines (skip for deletions)
      local replacement_lines = {}
      local j = i + 1

      if count >= 0 then
        -- Only collect replacement lines for insertions and replacements
        while j <= #lines do
          local next_line = lines[j]

          -- Stop at next marker or end delimiter
          if next_line:match('^CLAUDE:MARKER%-') or next_line:match('^%-%- CLAUDE:MARKERS:END %-%-$') then
            break
          end

          -- Include all lines (including empty ones) as part of the replacement
          table.insert(replacement_lines, next_line)

          j = j + 1
        end
      end

      -- Store marker info (no trimming - preserve content exactly as provided)
      table.insert(markers, {
        target_line = target_line,
        count = count,
        replacement_lines = replacement_lines,
        reasoning = reasoning,
      })

      i = j
    else
      i = i + 1
    end
  end

  if #markers == 0 then
    vim.notify('No Claude markers found in marker section', vim.log.levels.WARN)
    return 0
  end

  -- Get clean content (everything before marker section)
  local clean_lines = {}
  for idx = 1, marker_start_idx - 1 do
    table.insert(clean_lines, lines[idx])
  end

  -- Remove trailing empty lines
  while #clean_lines > 0 and clean_lines[#clean_lines] == '' do
    table.remove(clean_lines)
  end

  -- Apply markers to create the new content
  local new_lines = {}
  local line_idx = 1
  local applied_count = 0

  -- Sort markers by target line, with insertions before replacements for the same line
  table.sort(markers, function(a, b)
    if a.target_line == b.target_line then
      -- For same line, insertions (count=0) come first
      return a.count == 0 and b.count > 0
    end
    return a.target_line < b.target_line
  end)

  -- Apply each marker
  for _, marker in ipairs(markers) do
    -- Copy lines before this marker's target
    while line_idx < marker.target_line do
      if line_idx <= #clean_lines then
        table.insert(new_lines, clean_lines[line_idx])
      end
      line_idx = line_idx + 1
    end

    -- Apply the marker
    if marker.count == 0 then
      -- Insertion: insert AFTER the target line
      -- First, copy the target line itself
      if line_idx <= #clean_lines then
        table.insert(new_lines, clean_lines[line_idx])
      end
      line_idx = line_idx + 1
      -- Then add the new lines
      for _, repl in ipairs(marker.replacement_lines) do
        table.insert(new_lines, repl)
      end
    elseif marker.count < 0 then
      -- Deletion: remove lines without replacement
      -- Skip the lines to delete (absolute value of count)
      line_idx = line_idx + math.abs(marker.count)
    else
      -- Replacement: add replacement lines and skip original lines
      for _, repl in ipairs(marker.replacement_lines) do
        table.insert(new_lines, repl)
      end
      -- Skip the original lines that were replaced
      line_idx = line_idx + marker.count
    end

    applied_count = applied_count + 1
  end

  -- Copy any remaining lines
  while line_idx <= #clean_lines do
    table.insert(new_lines, clean_lines[line_idx])
    line_idx = line_idx + 1
  end

  -- Replace buffer with new content
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, new_lines)

  vim.notify(string.format('Applied %d markers directly', applied_count), vim.log.levels.INFO)
  return applied_count
end

-- Setup commands
function M.setup()
  vim.api.nvim_create_user_command('PairApplyMarkers', function()
    M.parse_and_apply()
  end, { desc = 'Apply Claude markers directly' })
end

return M
