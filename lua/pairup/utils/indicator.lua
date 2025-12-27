-- Status indicator for pairup.nvim (hook-based todo progress)

local M = {}
local config = require('pairup.config')

-- State
local file_watcher = nil
local peripheral_file_watcher = nil
local last_file_mtime = nil
local last_peripheral_file_mtime = nil
local virt_ns = vim.api.nvim_create_namespace('pairup_progress')
local virt_extmark_id = nil
local virt_extmark_buf = nil

---Setup highlight groups for color-coded indicators
local function setup_highlights()
  vim.api.nvim_set_hl(0, 'PairLocalIndicator', { fg = '#50fa7b', bold = true, default = true }) -- Green
  vim.api.nvim_set_hl(0, 'PairPeripheralIndicator', { fg = '#8be9fd', bold = true, default = true }) -- Blue
  vim.api.nvim_set_hl(0, 'PairSeparator', { fg = '#6272a4', default = true }) -- Gray
  vim.api.nvim_set_hl(0, 'PairSuspendedIndicator', { fg = '#ff5555', bold = true, default = true }) -- Red
end

---Update the LOCAL indicator variable
local function set_indicator(value)
  vim.g.pairup_indicator = value
  vim.g.claude_context_indicator = value -- legacy
  vim.cmd('redrawstatus')
end

---Update the PERIPHERAL indicator variable
local function set_peripheral_indicator(value)
  vim.g.pairup_peripheral_indicator = value
  vim.cmd('redrawstatus')
end

---Set virtual text showing current task at top of buffer (stable position)
---@param text string|nil
function M.set_virtual_text(text)
  -- Always clear existing first
  if virt_extmark_id and virt_extmark_buf and vim.api.nvim_buf_is_valid(virt_extmark_buf) then
    pcall(vim.api.nvim_buf_del_extmark, virt_extmark_buf, virt_ns, virt_extmark_id)
  end
  virt_extmark_id = nil
  virt_extmark_buf = nil
  if not text or text == '' then
    return
  end
  local buf = vim.api.nvim_get_current_buf()
  if vim.bo[buf].buftype ~= '' then
    return
  end
  -- Ensure highlight exists (green like statusline indicator)
  vim.api.nvim_set_hl(0, 'PairupProgress', { fg = '#a6e3a1', italic = true, default = true })
  -- Split into lines (wrap at ~80 chars or on newlines)
  local lines = {}
  for line in text:gmatch('[^\n]+') do
    if #line > 80 then
      while #line > 80 do
        local wrap_at = line:sub(1, 80):match('.*()%s') or 80
        table.insert(lines, line:sub(1, wrap_at))
        line = line:sub(wrap_at + 1)
      end
      if #line > 0 then
        table.insert(lines, line)
      end
    else
      table.insert(lines, line)
    end
  end
  -- Build virt_lines with icon on first line
  local virt_lines = {}
  for i, line in ipairs(lines) do
    local prefix = i == 1 and '  󰭻 ' or '    '
    table.insert(virt_lines, { { prefix .. line, 'PairupProgress' } })
  end
  -- Place below cursor (scroll_to_changes keeps view at edit location)
  local row = vim.api.nvim_win_get_cursor(0)[1] - 1
  virt_extmark_id = vim.api.nvim_buf_set_extmark(buf, virt_ns, row, 0, {
    virt_lines = virt_lines,
  })
  virt_extmark_buf = buf
end

---Get hook-based todo state file path (auto-detects most recent)
---@param peripheral boolean? If true, look for peripheral todo files
---@return string|nil
local function get_hook_file(peripheral)
  if not config.get('progress.enabled') then
    return nil
  end
  local session_id = config.get('progress.session_id')
  local pattern = peripheral and '^pairup%-peripheral%-todo%-.*%.json$' or '^pairup%-todo%-.*%.json$'
  local prefix = peripheral and 'pairup-peripheral-todo-' or 'pairup-todo-'

  if session_id then
    return '/tmp/' .. prefix .. session_id .. '.json'
  end
  -- Auto-detect: find most recent file matching pattern
  local handle = vim.loop.fs_scandir('/tmp')
  if not handle then
    return nil
  end
  local latest_file, latest_mtime = nil, 0
  while true do
    local name, type = vim.loop.fs_scandir_next(handle)
    if not name then
      break
    end
    if type == 'file' and name:match(pattern) then
      local stat = vim.loop.fs_stat('/tmp/' .. name)
      if stat and stat.mtime.sec > latest_mtime then
        latest_mtime = stat.mtime.sec
        latest_file = '/tmp/' .. name
      end
    end
  end
  return latest_file
end

---Check for hook-based todo state and update LOCAL indicator
local function check_hook_state()
  local hook_file = get_hook_file(false)
  if not hook_file then
    return
  end

  local stat = vim.loop.fs_stat(hook_file)
  if not stat then
    return
  end

  local mtime = stat.mtime.sec
  if mtime == last_file_mtime then
    return
  end
  last_file_mtime = mtime

  local f = io.open(hook_file, 'r')
  if not f then
    return
  end
  local content = f:read('*a')
  f:close()

  local ok, data = pcall(vim.json.decode, content)
  if not ok or not data then
    return
  end

  local total = data.total or 0
  local completed = data.completed or 0
  local current = data.current or ''

  if total == 0 then
    set_indicator('[CL]')
    M.set_virtual_text(nil)
  elseif completed == total then
    set_indicator('[CL:ready]')
    M.set_virtual_text(nil)
    vim.defer_fn(function()
      if vim.g.pairup_indicator == '[CL:ready]' then
        M.update()
      end
    end, 3000)
  else
    set_indicator('[CL:' .. completed .. '/' .. total .. ']')
    M.set_virtual_text(current)
  end
end

---Check for hook-based todo state and update PERIPHERAL indicator
local function check_peripheral_hook_state()
  local hook_file = get_hook_file(true)
  if not hook_file then
    return
  end

  local stat = vim.loop.fs_stat(hook_file)
  if not stat then
    return
  end

  local mtime = stat.mtime.sec
  if mtime == last_peripheral_file_mtime then
    return
  end
  last_peripheral_file_mtime = mtime

  local f = io.open(hook_file, 'r')
  if not f then
    return
  end
  local content = f:read('*a')
  f:close()

  local ok, data = pcall(vim.json.decode, content)
  if not ok or not data then
    return
  end

  local total = data.total or 0
  local completed = data.completed or 0

  if total == 0 then
    set_peripheral_indicator('[CP]')
  elseif completed == total then
    set_peripheral_indicator('[CP:ready]')
    vim.defer_fn(function()
      if vim.g.pairup_peripheral_indicator == '[CP:ready]' then
        M.update_peripheral()
      end
    end, 5000) -- 5s auto-clear for peripheral (longer than LOCAL)
  else
    set_peripheral_indicator('[CP:' .. completed .. '/' .. total .. ']')
  end
end

-- Update LOCAL status indicator
function M.update()
  local providers = require('pairup.providers')
  local buf = providers.find_terminal()
  if not buf then
    set_indicator('')
  else
    if vim.g.pairup_queued then
      set_indicator('[CL:queued]')
    elseif vim.g.pairup_pending then
      set_indicator('[CL:processing]')
    else
      set_indicator('[CL]')
    end
  end
end

-- Update PERIPHERAL status indicator
function M.update_peripheral()
  -- Check if peripheral worktree/terminal exists
  local peripheral_buf = vim.g.pairup_peripheral_buf
  if not peripheral_buf or not vim.api.nvim_buf_is_valid(peripheral_buf) then
    set_peripheral_indicator('')
  else
    if vim.g.pairup_peripheral_queued then
      set_peripheral_indicator('[CP:queued]')
    elseif vim.g.pairup_peripheral_pending then
      set_peripheral_indicator('[CP:processing]')
    else
      set_peripheral_indicator('[CP]')
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

-- Set peripheral pending status
function M.set_peripheral_pending(message)
  vim.g.pairup_peripheral_pending = message or 'analyzing'
  vim.g.pairup_peripheral_pending_time = os.time()
  M.update_peripheral()
end

-- Clear peripheral pending status
function M.clear_peripheral_pending()
  vim.g.pairup_peripheral_pending = nil
  vim.g.pairup_peripheral_pending_time = nil
  vim.g.pairup_peripheral_queued = false
  M.update_peripheral()
end

-- Set peripheral queued status
function M.set_peripheral_queued()
  vim.g.pairup_peripheral_queued = true
  M.update_peripheral()
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

-- Get LOCAL indicator for statusline
function M.get()
  return vim.g.pairup_indicator or ''
end

-- Get PERIPHERAL indicator for statusline
function M.get_peripheral()
  return vim.g.pairup_peripheral_indicator or ''
end

-- Get combined display (plain text, for simple use)
function M.get_display()
  local local_ind = vim.g.pairup_indicator or ''
  local periph_ind = vim.g.pairup_peripheral_indicator or ''
  local sep = vim.g.pairup_statusline_separator or '|'

  -- Build display: only show active indicators
  if local_ind ~= '' and periph_ind ~= '' then
    return local_ind .. ' ' .. sep .. ' ' .. periph_ind
  elseif local_ind ~= '' then
    return local_ind
  elseif periph_ind ~= '' then
    return periph_ind
  else
    return ''
  end
end

-- Get colored display (with highlight groups, for native statusline)
function M.get_colored_display()
  local local_ind = vim.g.pairup_indicator or ''
  local periph_ind = vim.g.pairup_peripheral_indicator or ''
  local sep = vim.g.pairup_statusline_separator or '|'

  -- Check if LOCAL is suspended (use red instead of green)
  local local_hl = vim.g.pairup_suspended and 'PairSuspendedIndicator' or 'PairLocalIndicator'

  -- Build display with color codes
  if local_ind ~= '' and periph_ind ~= '' then
    return string.format(
      '%%#%s#%s%%* %%#PairSeparator#%s%%* %%#PairPeripheralIndicator#%s%%*',
      local_hl,
      local_ind,
      sep,
      periph_ind
    )
  elseif local_ind ~= '' then
    return string.format('%%#%s#%s%%*', local_hl, local_ind)
  elseif periph_ind ~= '' then
    return string.format('%%#PairPeripheralIndicator#%s%%*', periph_ind)
  else
    return ''
  end
end

-- Setup file watchers for progress
function M.setup()
  -- Setup highlights
  setup_highlights()

  -- Setup LOCAL watcher
  if not file_watcher then
    file_watcher = vim.loop.new_timer()
    file_watcher:start(500, 500, vim.schedule_wrap(check_hook_state))
  end

  -- Setup PERIPHERAL watcher
  if not peripheral_file_watcher then
    peripheral_file_watcher = vim.loop.new_timer()
    peripheral_file_watcher:start(500, 500, vim.schedule_wrap(check_peripheral_hook_state))
  end
end

-- Cleanup timers on plugin unload
function M.cleanup()
  if file_watcher then
    if not file_watcher:is_closing() then
      file_watcher:stop()
      file_watcher:close()
    end
    file_watcher = nil
  end

  if peripheral_file_watcher then
    if not peripheral_file_watcher:is_closing() then
      peripheral_file_watcher:stop()
      peripheral_file_watcher:close()
    end
    peripheral_file_watcher = nil
  end

  last_file_mtime = nil
  last_peripheral_file_mtime = nil
  M.set_virtual_text(nil)
end

return M
