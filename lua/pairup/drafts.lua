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
  require('pairup.utils.indicator').update()
  vim.notify('Draft mode enabled', vim.log.levels.INFO)
end

---Disable draft mode (edits apply normally)
function M.disable()
  local flag_path = get_flag_path()
  if flag_path then
    os.remove(flag_path)
  end
  require('pairup.utils.indicator').update()
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
  return M.apply_at_index(1)
end

---Apply draft at specific index
---@param idx integer Draft index (1-based)
---@return boolean, string
function M.apply_at_index(idx)
  local drafts = M.get_all()
  if #drafts == 0 then
    return false, 'No pending drafts'
  end
  if idx < 1 or idx > #drafts then
    return false, 'Invalid draft index: ' .. idx
  end

  local draft = drafts[idx]
  local ok, err = apply_draft(draft)
  if ok then
    table.remove(drafts, idx)
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

---Find line number where old_string starts in file
---@param file string
---@param old_string string
---@return number
local function find_line_number(file, old_string)
  if vim.fn.filereadable(file) == 0 then
    return 1
  end
  local first_line = old_string:match('^([^\n]+)')
  if not first_line then
    return 1
  end
  local bufnr = vim.fn.bufnr(file)
  if bufnr == -1 then
    bufnr = vim.fn.bufadd(file)
    vim.fn.bufload(bufnr)
  end
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  for lnum, line in ipairs(lines) do
    if line:find(vim.pesc(first_line), 1, true) then
      return lnum
    end
  end
  return 1
end

-- Store current draft index for navigation
M._current_idx = 1
M._diff_ctx = nil

---Show draft as diff in split view (does NOT modify source buffer)
function M.preview()
  local drafts = M.get_all()
  if #drafts == 0 then
    vim.notify('No pending drafts', vim.log.levels.INFO)
    return
  end

  M._current_idx = 1
  M._show_draft(drafts[1], 1, #drafts)
end

---Show a single draft as diff
function M._show_draft(draft, idx, total)
  local ft = vim.fn.fnamemodify(draft.file, ':e')
  local old_lines = vim.split(draft.old_string or '', '\n', { plain = true })
  local new_lines = vim.split(draft.new_string or '', '\n', { plain = true })

  local old_buf = vim.api.nvim_create_buf(false, true)
  local new_buf = vim.api.nvim_create_buf(false, true)

  vim.api.nvim_buf_set_lines(old_buf, 0, -1, false, old_lines)
  vim.api.nvim_buf_set_lines(new_buf, 0, -1, false, new_lines)
  pcall(vim.api.nvim_buf_set_name, old_buf, string.format('CURRENT [%d/%d]', idx, total))
  pcall(vim.api.nvim_buf_set_name, new_buf, string.format('PROPOSED [%d/%d]', idx, total))
  vim.bo[old_buf].filetype = ft
  vim.bo[new_buf].filetype = ft
  vim.bo[old_buf].bufhidden = 'wipe'
  vim.bo[new_buf].bufhidden = 'wipe'

  M._diff_ctx = { draft = draft, idx = idx, total = total, old_buf = old_buf, new_buf = new_buf }

  local function set_keymaps(buf)
    vim.keymap.set('n', 'ga', M.accept_current, { buffer = buf, desc = 'Accept draft' })
    vim.keymap.set('n', 'gx', M.reject_current, { buffer = buf, desc = 'Reject draft' })
    vim.keymap.set('n', ']d', M.next_draft, { buffer = buf, desc = 'Next draft' })
    vim.keymap.set('n', '[d', M.prev_draft, { buffer = buf, desc = 'Prev draft' })
    vim.keymap.set('n', 'q', function()
      M._diff_ctx = nil
      vim.cmd('tabclose')
    end, { buffer = buf, desc = 'Close' })
  end

  set_keymaps(old_buf)
  set_keymaps(new_buf)

  vim.cmd('tabnew')
  vim.api.nvim_set_current_buf(old_buf)
  vim.cmd('diffthis')
  vim.cmd('vsplit')
  vim.api.nvim_set_current_buf(new_buf)
  vim.cmd('diffthis')
  vim.cmd('set diffopt+=algorithm:patience,indent-heuristic')

  -- Legend in cmdline
  vim.api.nvim_echo({
    { 'ga', 'DiagnosticOk' },
    { '=accept  ', 'Comment' },
    { 'gx', 'DiagnosticError' },
    { '=reject  ', 'Comment' },
    { ']d', 'DiagnosticInfo' },
    { '/', 'Comment' },
    { '[d', 'DiagnosticInfo' },
    { '=nav  ', 'Comment' },
    { 'q', 'DiagnosticWarn' },
    { '=close', 'Comment' },
  }, false, {})
end

function M.next_draft()
  local drafts = M.get_all()
  if M._current_idx < #drafts then
    M._current_idx = M._current_idx + 1
    vim.cmd('tabclose')
    M._show_draft(drafts[M._current_idx], M._current_idx, #drafts)
  end
end

function M.prev_draft()
  local drafts = M.get_all()
  if M._current_idx > 1 then
    M._current_idx = M._current_idx - 1
    vim.cmd('tabclose')
    M._show_draft(drafts[M._current_idx], M._current_idx, #drafts)
  end
end

function M.accept_current()
  if not M._diff_ctx then
    return
  end
  local draft = M._diff_ctx.draft
  local idx = M._diff_ctx.idx
  local ok, msg = M.apply_at_index(idx)
  vim.cmd('tabclose!')
  M._diff_ctx = nil

  if ok then
    vim.notify(msg, vim.log.levels.INFO)
    local remaining = M.get_all()
    if #remaining > 0 then
      M._current_idx = math.min(idx, #remaining)
      M._show_draft(remaining[M._current_idx], M._current_idx, #remaining)
    else
      local bufnr = vim.fn.bufnr(draft.file)
      if bufnr ~= -1 then
        vim.cmd('buffer ' .. bufnr)
      else
        vim.cmd('edit! ' .. vim.fn.fnameescape(draft.file))
      end
      local lnum = find_line_number(draft.file, draft.new_string or '')
      pcall(vim.api.nvim_win_set_cursor, 0, { lnum, 0 })
    end
  end
end

function M.reject_current()
  if not M._diff_ctx then
    return
  end
  local idx = M._diff_ctx.idx
  local drafts = M.get_all()
  if #drafts > 0 and idx >= 1 and idx <= #drafts then
    table.remove(drafts, idx)
    if #drafts == 0 then
      M.clear()
    else
      local f = io.open(DRAFTS_FILE, 'w')
      if f then
        f:write(vim.json.encode(drafts))
        f:close()
      end
    end
  end
  vim.cmd('tabclose!')
  M._diff_ctx = nil
  vim.notify('Draft rejected', vim.log.levels.INFO)

  local remaining = M.get_all()
  if #remaining > 0 then
    M._current_idx = math.min(idx, #remaining)
    M._show_draft(remaining[M._current_idx], M._current_idx, #remaining)
  end
end

---Materialize drafts as conflict markers in buffer
---@param filepath string|nil File to materialize (defaults to current buffer)
function M.materialize(filepath)
  filepath = filepath or vim.api.nvim_buf_get_name(0)
  local all = M.get_all()
  local file_drafts = vim.tbl_filter(function(d)
    return d.file == filepath
  end, all)

  if #file_drafts == 0 then
    vim.notify('No drafts for ' .. vim.fn.fnamemodify(filepath, ':t'), vim.log.levels.INFO)
    return
  end

  local bufnr = vim.fn.bufnr(filepath)
  if bufnr == -1 then
    bufnr = vim.fn.bufadd(filepath)
    vim.fn.bufload(bufnr)
  end

  local content = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), '\n')

  -- Apply drafts in reverse order (bottom-up) to preserve line numbers
  local applied = 0
  for i = #file_drafts, 1, -1 do
    local draft = file_drafts[i]
    if draft.old_string and draft.new_string then
      local conflict = '<<<<<<< CURRENT\n'
        .. draft.old_string
        .. '\n=======\n'
        .. draft.new_string
        .. '\n>>>>>>> PROPOSED'
      local new_content, count = content:gsub(vim.pesc(draft.old_string), conflict, 1)
      if count > 0 then
        content = new_content
        applied = applied + 1
      end
    end
  end

  if applied > 0 then
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(content, '\n', { plain = true }))
    vim.notify(string.format('Materialized %d draft(s) as conflicts', applied), vim.log.levels.INFO)
    -- Remove materialized drafts from queue
    local remaining = vim.tbl_filter(function(d)
      return d.file ~= filepath
    end, all)
    if #remaining == 0 then
      M.clear()
    else
      local f = io.open(DRAFTS_FILE, 'w')
      if f then
        f:write(vim.json.encode(remaining))
        f:close()
      end
    end
  else
    vim.notify('Could not materialize drafts (old_string not found)', vim.log.levels.WARN)
  end
end

return M
