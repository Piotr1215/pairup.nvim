-- Status indicator for pairup.nvim (hook-based todo progress)

local M = {}
local config = require('pairup.config')

-- State
local file_watcher = nil
local last_file_mtime = nil
local virt_ns = vim.api.nvim_create_namespace('pairup_progress')
local virt_extmark_id = nil
local virt_extmark_buf = nil

---Update the indicator variable
local function set_indicator(value)
  vim.g.pairup_indicator = value
  vim.g.claude_context_indicator = value -- legacy
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
---@return string|nil
local function get_hook_file()
  if not config.get('progress.enabled') then
    return nil
  end
  local session_id = config.get('progress.session_id')
  if session_id then
    return '/tmp/pairup-todo-' .. session_id .. '.json'
  end
  -- Auto-detect: find most recent pairup-todo-*.json
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
    if type == 'file' and name:match('^pairup%-todo%-.*%.json$') then
      local stat = vim.loop.fs_stat('/tmp/' .. name)
      if stat and stat.mtime.sec > latest_mtime then
        latest_mtime = stat.mtime.sec
        latest_file = '/tmp/' .. name
      end
    end
  end
  return latest_file
end

---Get indicator prefix (C or CD if draft mode enabled)
---@return string
local function get_prefix()
  local provider = config.get_provider()
  local prefix = provider:sub(1, 1):upper()
  local drafts = require('pairup.drafts')
  if drafts.is_enabled() then
    return prefix .. 'D'
  end
  return prefix
end

---Check for hook-based todo state and update indicator
local function check_hook_state()
  local hook_file = get_hook_file()
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

  local prefix = get_prefix()
  if total == 0 then
    set_indicator('[' .. prefix .. ']')
    M.set_virtual_text(nil)
  elseif completed == total then
    set_indicator('[' .. prefix .. ':ready]')
    M.set_virtual_text(nil)
    -- Process queued markers if any
    if vim.g.pairup_queued then
      local queued_file = vim.g.pairup_queued
      vim.g.pairup_queued = false
      vim.defer_fn(function()
        local inline = require('pairup.inline')
        if type(queued_file) == 'string' then
          local bufnr = vim.fn.bufnr(queued_file)
          if bufnr ~= -1 then
            inline.process(bufnr)
          end
        else
          inline.process()
        end
      end, 300)
    else
      vim.defer_fn(function()
        if vim.g.pairup_indicator == '[' .. prefix .. ':ready]' then
          M.update()
        end
      end, 3000)
    end
  else
    set_indicator('[' .. prefix .. ':' .. completed .. '/' .. total .. ']')
    M.set_virtual_text(current)
  end
end

-- Update status indicator
function M.update()
  local providers = require('pairup.providers')
  local buf = providers.find_terminal()
  if not buf then
    set_indicator('')
  else
    local prefix = get_prefix()

    if vim.g.pairup_queued then
      set_indicator(string.format('[%s:queued]', prefix))
    elseif vim.g.pairup_pending then
      set_indicator(string.format('[%s:processing]', prefix))
    else
      set_indicator(string.format('[%s]', prefix))
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
function M.set_queued(filepath)
  vim.g.pairup_queued = filepath or true
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

-- Check if Claude is busy (has active todos)
function M.is_busy()
  -- In draft mode, never busy (edits go to JSON, no tool progression)
  local drafts = require('pairup.drafts')
  if drafts.is_enabled() then
    return false
  end

  local hook_file = get_hook_file()
  if not hook_file then
    return vim.g.pairup_pending ~= nil
  end
  local f = io.open(hook_file, 'r')
  if not f then
    return vim.g.pairup_pending ~= nil
  end
  local content = f:read('*a')
  f:close()
  local ok, data = pcall(vim.json.decode, content)
  if not ok or not data then
    return vim.g.pairup_pending ~= nil
  end
  local total = data.total or 0
  local completed = data.completed or 0
  return total > 0 and completed < total
end

-- Setup file watcher for progress
function M.setup()
  if file_watcher then
    return
  end
  file_watcher = vim.loop.new_timer()
  file_watcher:start(500, 500, vim.schedule_wrap(check_hook_state))
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
  last_file_mtime = nil
  M.set_virtual_text(nil)
end

return M
