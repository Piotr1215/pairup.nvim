-- Overlay persistence module for saving/restoring unresolved suggestions
local M = {}

-- Track if we're already saving to prevent multiple concurrent saves
local is_saving = false
local is_exiting = false

-- Get the storage directory for overlay sessions
local function get_storage_dir()
  local dir = vim.fn.stdpath('state') .. '/pairup/overlays/'
  vim.fn.mkdir(dir, 'p')
  return dir
end

-- Calculate file hash for staleness detection
local function get_file_hash(filepath)
  -- Use vim.loop (libuv) for non-blocking file stat
  -- Avoid io.popen which can hang during exit
  local stat = vim.loop.fs_stat(filepath)
  if stat then
    return string.format('%d_%d', stat.size, stat.mtime.sec)
  end
  return nil
end

-- Save overlays to a session file
function M.save_overlays(filepath)
  -- Don't save if we're already saving or exiting
  if is_saving or is_exiting then
    return false, 'Save already in progress or exiting'
  end

  is_saving = true

  local ok, result, path, count = pcall(function()
    local overlay = require('pairup.overlay')
    local bufnr = vim.api.nvim_get_current_buf()
    local suggestions = overlay.get_suggestions(bufnr)

    -- Get current file info
    local current_file = vim.api.nvim_buf_get_name(bufnr)
    if current_file == '' then
      return false, 'No file in current buffer'
    end

    -- Count overlays
    local overlay_count = 0
    for _, _ in pairs(suggestions) do
      overlay_count = overlay_count + 1
    end

    if overlay_count == 0 then
      return false, 'No overlays to save'
    end

    -- Build session data
    local session = {
      version = 1,
      timestamp = os.time(),
      file = current_file,
      file_hash = get_file_hash(current_file),
      overlay_count = overlay_count,
      overlays = {},
    }

    -- Convert suggestions to serializable format
    for line_num, suggestion in pairs(suggestions) do
      local overlay_data = {
        line = line_num,
        reasoning = suggestion.reasoning,
        is_multiline = suggestion.is_multiline,
        is_deletion = suggestion.is_deletion,
      }

      -- Handle variants
      if suggestion.variants then
        overlay_data.variants = {}
        for i, variant in ipairs(suggestion.variants) do
          local v = {
            reasoning = variant.reasoning,
          }
          if suggestion.is_multiline then
            v.new_lines = variant.new_lines
          else
            v.new_text = variant.new_text
          end
          table.insert(overlay_data.variants, v)
        end
        overlay_data.current_variant = suggestion.current_variant
      else
        -- Single suggestion
        if suggestion.is_multiline then
          overlay_data.start_line = suggestion.start_line
          overlay_data.end_line = suggestion.end_line
          overlay_data.old_lines = suggestion.old_lines
          overlay_data.new_lines = suggestion.new_lines
        else
          overlay_data.old_text = suggestion.old_text
          overlay_data.new_text = suggestion.new_text
        end
      end

      table.insert(session.overlays, overlay_data)
    end

    -- Sort by line number for consistent output
    table.sort(session.overlays, function(a, b)
      return a.line < b.line
    end)

    -- Determine save path
    local save_path
    if filepath then
      save_path = filepath
    else
      -- Auto-generate filename based on current file and timestamp
      local basename = vim.fn.fnamemodify(current_file, ':t:r')
      local timestamp = os.date('%Y%m%d_%H%M%S')
      save_path = get_storage_dir() .. string.format('%s_%s.json', basename, timestamp)
    end

    -- Encode JSON
    local json_ok, json = pcall(vim.json.encode, session)
    if not json_ok then
      return false, 'Failed to encode session'
    end

    -- Save to file
    local file = io.open(save_path, 'w')
    if not file then
      return false, 'Failed to open file for writing'
    end

    file:write(json)
    file:close()

    return true, save_path, overlay_count
  end)

  is_saving = false

  if ok then
    return result, path, count
  else
    return false, tostring(result)
  end
end

-- Restore overlays from a session file
function M.restore_overlays(filepath, options)
  options = options or {}
  local force = options.force or false
  local preview = options.preview or false

  -- Read session file
  local file = io.open(filepath, 'r')
  if not file then
    return false, 'Failed to open file: ' .. filepath
  end

  local content = file:read('*a')
  file:close()

  local ok, session = pcall(vim.json.decode, content)
  if not ok then
    return false, 'Failed to parse session file: ' .. tostring(session)
  end

  -- Validate session structure
  if not session.version or not session.overlays then
    return false, 'Invalid session file format'
  end

  -- Check if we're in the same file
  local current_file = vim.api.nvim_buf_get_name(0)
  if current_file ~= session.file then
    if not force then
      return false, string.format('Session is for different file: %s', session.file)
    end
  end

  -- Check file hash for staleness
  local current_hash = get_file_hash(current_file)
  if current_hash ~= session.file_hash then
    if not force and not preview then
      local msg = string.format(
        'File has changed since overlays were saved.\nSaved: %s\nCurrent: %s\nUse force=true to load anyway',
        session.file_hash or 'unknown',
        current_hash or 'unknown'
      )
      return false, msg
    end
  end

  -- If preview mode, just return the session data
  if preview then
    return true, session
  end

  -- Clear existing overlays
  local overlay = require('pairup.overlay')
  overlay.clear_overlays()

  -- Restore each overlay
  local restored = 0
  local failed = 0

  for _, overlay_data in ipairs(session.overlays) do
    local ok_restore = false

    if overlay_data.variants then
      -- Restore with variants
      if overlay_data.is_multiline then
        -- Multiline variants
        overlay.show_multiline_suggestion_variants(
          vim.api.nvim_get_current_buf(),
          overlay_data.line,
          overlay_data.end_line or overlay_data.line,
          nil, -- old_lines will be fetched from buffer
          overlay_data.variants
        )
      else
        -- Single line variants
        overlay.show_suggestion_variants(
          vim.api.nvim_get_current_buf(),
          overlay_data.line,
          nil, -- old_text will be fetched from buffer
          overlay_data.variants
        )
      end
      ok_restore = true
    elseif overlay_data.is_multiline then
      -- Multiline without variants
      overlay.show_multiline_suggestion(
        vim.api.nvim_get_current_buf(),
        overlay_data.start_line,
        overlay_data.end_line,
        overlay_data.old_lines,
        overlay_data.new_lines,
        overlay_data.reasoning
      )
      ok_restore = true
    else
      -- Single line without variants
      overlay.show_suggestion(
        vim.api.nvim_get_current_buf(),
        overlay_data.line,
        overlay_data.old_text,
        overlay_data.new_text,
        overlay_data.reasoning
      )
      ok_restore = true
    end

    if ok_restore then
      restored = restored + 1
    else
      failed = failed + 1
    end
  end

  return true, string.format('Restored %d overlays (%d failed)', restored, failed), restored
end

-- List available overlay sessions
function M.list_sessions()
  local dir = get_storage_dir()
  local files = vim.fn.glob(dir .. '*.json', false, true)

  local sessions = {}
  for _, filepath in ipairs(files) do
    local filename = vim.fn.fnamemodify(filepath, ':t')
    local file = io.open(filepath, 'r')
    if file then
      local content = file:read('*a')
      file:close()

      local ok, session = pcall(vim.json.decode, content)
      if ok and session then
        table.insert(sessions, {
          path = filepath,
          filename = filename,
          timestamp = session.timestamp,
          file = session.file,
          overlay_count = session.overlay_count or 0,
          date = os.date('%Y-%m-%d %H:%M:%S', session.timestamp),
        })
      end
    end
  end

  -- Sort by timestamp, newest first
  table.sort(sessions, function(a, b)
    return (a.timestamp or 0) > (b.timestamp or 0)
  end)

  return sessions
end

-- Auto-save function (can be called on buffer unload or vim exit)
function M.auto_save(silent)
  -- Don't save if already exiting
  if is_exiting then
    return false
  end

  -- Don't save if another save is in progress
  if is_saving then
    return false
  end

  local ok, path, count = M.save_overlays()

  -- Always log to a file for debugging
  local log_file = io.open(vim.fn.stdpath('state') .. '/pairup_save.log', 'a')
  if log_file then
    log_file:write(
      string.format(
        '[%s] auto_save: ok=%s, path=%s, count=%s\n',
        os.date('%Y-%m-%d %H:%M:%S'),
        tostring(ok),
        tostring(path),
        tostring(count)
      )
    )
    log_file:close()
  end

  if ok and not silent then
    -- Use print instead of vim.notify to avoid issues during exit
    print(string.format('Saved %d overlays to %s', count, vim.fn.fnamemodify(path, ':~')))
  end

  return ok, path, count
end

-- Auto-save for exit (completely silent, non-blocking)
function M.auto_save_on_exit()
  -- Mark that we're exiting to prevent other saves
  is_exiting = true

  -- Log the attempt
  local log_file = io.open(vim.fn.stdpath('state') .. '/pairup_save.log', 'a')
  if log_file then
    log_file:write(string.format('[%s] auto_save_on_exit: called\n', os.date('%Y-%m-%d %H:%M:%S')))
  end

  -- Don't try to save if already saving
  if is_saving then
    if log_file then
      log_file:write('  - skipped: already saving\n')
      log_file:close()
    end
    return
  end

  -- Quick check if there are any overlays to save
  local ok_check, has_overlays = pcall(function()
    local overlay = require('pairup.overlay')
    local bufnr = vim.api.nvim_get_current_buf()
    local suggestions = overlay.get_suggestions(bufnr)

    -- Count suggestions
    local count = 0
    for _, _ in pairs(suggestions) do
      count = count + 1
    end

    if log_file then
      log_file:write(string.format('  - found %d overlays\n', count))
    end

    return count > 0
  end)

  if not ok_check or not has_overlays then
    if log_file then
      log_file:write(
        string.format(
          '  - no overlays to save: ok_check=%s, has_overlays=%s\n',
          tostring(ok_check),
          tostring(has_overlays)
        )
      )
      log_file:close()
    end
    return
  end

  -- Try to save, but don't block or show errors
  local save_ok, save_result = pcall(M.save_overlays)

  if log_file then
    log_file:write(string.format('  - save result: ok=%s, result=%s\n', tostring(save_ok), tostring(save_result)))
    log_file:close()
  end
end

-- Clean old session files (keep last N)
function M.clean_old_sessions(keep_count)
  keep_count = keep_count or 10
  local sessions = M.list_sessions()

  if #sessions > keep_count then
    for i = keep_count + 1, #sessions do
      os.remove(sessions[i].path)
    end
    return #sessions - keep_count
  end

  return 0
end

return M
