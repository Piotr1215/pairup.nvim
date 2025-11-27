-- Status indicator for pairup.nvim (includes progress bar)

local M = {}
local config = require('pairup.config')

-- Progress state
local progress_file = '/tmp/claude_progress'
local bar_width = 10
local bar_filled = '█'
local bar_empty = '░'
local active_progress = nil -- { start_time, duration, message, timer }
local file_watcher = nil
local last_file_mtime = nil -- Track file modification time

---Generate progress bar string
local function make_bar(progress)
  local filled = math.floor(progress * bar_width + 0.5)
  local empty = bar_width - filled
  return string.rep(bar_filled, filled) .. string.rep(bar_empty, empty)
end

---Update the indicator variable
local function set_indicator(value)
  vim.g.pairup_indicator = value
  vim.g.claude_context_indicator = value -- legacy
  vim.cmd('redrawstatus')
end

---Update progress bar display
local function update_progress()
  if not active_progress then
    return
  end

  local elapsed = os.time() - active_progress.start_time
  local remaining = math.max(0, active_progress.duration - elapsed)
  local progress = math.min(elapsed / active_progress.duration, 1.0)

  if progress >= 1.0 then
    -- Done - show ready (green)
    set_indicator('[C:' .. make_bar(1.0) .. '] ' .. active_progress.message)
    M.stop_progress()
  else
    -- Show progress bar with remaining seconds (green)
    set_indicator('[C:' .. make_bar(progress) .. '] ' .. remaining .. 's ' .. active_progress.message)
  end
end

---Check for progress file and start timer
local function check_progress_file()
  -- Check file modification time first
  local stat = vim.loop.fs_stat(progress_file)
  if not stat then
    return
  end

  -- Skip if file hasn't changed
  local mtime = stat.mtime.sec
  if mtime == last_file_mtime then
    return
  end

  local f = io.open(progress_file, 'r')
  if not f then
    return
  end

  local content = f:read('*a')
  f:close()

  content = vim.trim(content)

  -- Check for "done" signal
  if content == 'done' then
    last_file_mtime = mtime
    M.stop_progress()
    set_indicator('[C:ready]')
    os.remove(progress_file)
    -- Clear ready after 3 seconds
    vim.defer_fn(function()
      if vim.g.pairup_indicator == '[C:ready]' then
        M.update()
      end
    end, 3000)
    return
  end

  local duration, message = content:match('^(%d+):(.+)')
  if not duration or not message then
    return
  end

  duration = tonumber(duration)
  message = vim.trim(message)

  -- File changed - update mtime and reset progress
  last_file_mtime = mtime

  -- Stop previous
  M.stop_progress()

  -- Start new progress
  active_progress = {
    start_time = os.time(),
    duration = duration,
    message = message,
  }

  local interval = duration <= 10 and 200 or 500
  local timer = vim.loop.new_timer()
  active_progress.timer = timer

  timer:start(
    0,
    interval,
    vim.schedule_wrap(function()
      if active_progress and active_progress.timer then
        update_progress()
      end
      -- Timer cleanup handled by stop_progress()
    end)
  )

  -- Delete file so we don't re-read
  os.remove(progress_file)
end

-- Stop progress and return to normal indicator
function M.stop_progress()
  if active_progress and active_progress.timer then
    local timer = active_progress.timer
    active_progress.timer = nil -- Clear first to prevent double-close
    if not timer:is_closing() then
      timer:stop()
      timer:close()
    end
  end
  active_progress = nil
  M.update()
end

-- Update status indicator (normal mode, no progress)
function M.update()
  -- Don't override active progress
  if active_progress then
    return
  end

  local providers = require('pairup.providers')
  local buf = providers.find_terminal()
  if not buf then
    set_indicator('') -- AI not running
  else
    local provider = config.get_provider()
    local prefix = provider:sub(1, 1):upper()
    local inline_mode = config.get('inline.enabled')

    if inline_mode then
      if vim.g.pairup_queued then
        set_indicator(string.format('[%s:queued]', prefix))
      elseif vim.g.pairup_pending then
        set_indicator(string.format('[%s:pending]', prefix))
      else
        set_indicator(string.format('[%s]', prefix))
      end
    elseif config.get('enabled') then
      set_indicator(string.format('[%s]', prefix))
    else
      set_indicator(string.format('[%s-off]', prefix))
    end
  end
end

-- Set status to pending for a file
function M.set_pending(filepath)
  vim.g.pairup_pending = filepath
  vim.g.pairup_pending_time = os.time()
  M.update()
end

-- Clear pending status
function M.clear_pending()
  vim.g.pairup_pending = nil
  vim.g.pairup_pending_time = nil
  vim.g.pairup_queued = false
  M.update()
end

-- Set queued status
function M.set_queued()
  vim.g.pairup_queued = true
  M.update()
end

-- Check if file is pending
function M.is_pending(filepath)
  if vim.g.pairup_pending ~= filepath then
    return false
  end
  local elapsed = os.time() - (vim.g.pairup_pending_time or 0)
  if elapsed > 60 then
    M.clear_pending()
    return false
  end
  return true
end

-- Get indicator for statusline
function M.get()
  return vim.g.pairup_indicator or ''
end

-- Setup file watcher for progress
function M.setup()
  if file_watcher then
    return -- Already setup
  end
  file_watcher = vim.loop.new_timer()
  file_watcher:start(
    500,
    500,
    vim.schedule_wrap(function()
      check_progress_file()
    end)
  )
end

return M
