-- Drafts module for pairup.nvim
-- Reads and applies queued edits from /tmp/pairup-drafts.json

local M = {}

local DRAFTS_FILE = '/tmp/pairup-drafts.json'

---Get session-specific flag file path
---@return string|nil
local function get_flag_path()
  local session_id = vim.g.pairup_session_id
  if not session_id then
    return nil
  end
  return '/tmp/pairup-draft-mode-' .. session_id
end

---Enable draft mode (edits get captured instead of applied)
function M.enable()
  local flag_path = get_flag_path()
  if not flag_path then
    vim.notify('No pairup session. Run :Pairup start first.', vim.log.levels.WARN)
    return
  end
  local f = io.open(flag_path, 'w')
  if f then
    f:write(vim.g.pairup_session_id)
    f:close()
  end
  vim.notify('Draft mode enabled', vim.log.levels.INFO)
end

---Disable draft mode (edits apply normally)
function M.disable()
  local flag_path = get_flag_path()
  if flag_path then
    os.remove(flag_path)
  end
  vim.notify('Draft mode disabled', vim.log.levels.INFO)
end

---Check if draft mode is enabled
---@return boolean
function M.is_enabled()
  local flag_path = get_flag_path()
  if not flag_path then
    return false
  end
  local f = io.open(flag_path, 'r')
  if f then
    f:close()
    return true
  end
  return false
end

---Read all pending drafts
---@return table[]
function M.get_all()
  local f = io.open(DRAFTS_FILE, 'r')
  if not f then
    return {}
  end
  local content = f:read('*a')
  f:close()
  local ok, drafts = pcall(vim.json.decode, content)
  return (ok and type(drafts) == 'table') and drafts or {}
end

---@return number
function M.count()
  return #M.get_all()
end

function M.clear()
  os.remove(DRAFTS_FILE)
end

---Apply a single draft (handles old_string/new_string format)
---@param draft table
---@return boolean, string|nil error message
local function apply_draft(draft)
  local file = draft.file
  local old_string = draft.old_string
  local new_string = draft.new_string

  if not file or not old_string or not new_string then
    return false, 'Invalid draft format: missing required fields'
  end

  if vim.fn.filereadable(file) == 0 then
    return false, 'File not found: ' .. file
  end

  local bufnr = vim.fn.bufnr(file)
  if bufnr == -1 then
    bufnr = vim.fn.bufadd(file)
    vim.fn.bufload(bufnr)
  end

  if not vim.api.nvim_buf_is_valid(bufnr) then
    return false, 'Cannot open buffer: ' .. file
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local content = table.concat(lines, '\n')
  local new_content, count = content:gsub(vim.pesc(old_string), new_string, 1)

  if count == 0 then
    return false, 'old_string not found in ' .. file
  end

  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(new_content, '\n', { plain = true }))
  return true, nil
end

---@return boolean, string
function M.apply_next()
  local drafts = M.get_all()
  if #drafts == 0 then
    return false, 'No pending drafts'
  end

  local draft = drafts[1]
  local ok, err = apply_draft(draft)
  if ok then
    table.remove(drafts, 1)
    if #drafts == 0 then
      M.clear()
    else
      local f = io.open(DRAFTS_FILE, 'w')
      if f then
        f:write(vim.json.encode(drafts))
        f:close()
      end
    end
    vim.cmd('checktime')
    return true, 'Applied edit to ' .. draft.file
  end
  return false, err or 'Failed to apply'
end

---@return number, number, string[] errors
function M.apply_all()
  local drafts = M.get_all()
  local applied, failed = 0, 0
  local errors = {}
  for i = #drafts, 1, -1 do
    local ok, err = apply_draft(drafts[i])
    if ok then
      applied = applied + 1
    else
      failed = failed + 1
      table.insert(errors, err or 'Unknown error')
    end
  end
  M.clear()
  vim.cmd('checktime')
  return applied, failed, errors
end

function M.preview()
  local drafts = M.get_all()
  if #drafts == 0 then
    vim.notify('No pending drafts', vim.log.levels.INFO)
    return
  end

  local qf_items = {}
  for i, draft in ipairs(drafts) do
    local preview = (draft.new_string or ''):sub(1, 50):gsub('\n', ' ')
    table.insert(qf_items, {
      filename = draft.file,
      lnum = 1,
      text = string.format('[%d] %s...', i, preview),
      type = 'I',
    })
  end

  vim.fn.setqflist(qf_items, 'r')
  vim.fn.setqflist({}, 'a', { title = 'Pairup Drafts (' .. #drafts .. ')' })
  vim.cmd('copen')
end

return M
