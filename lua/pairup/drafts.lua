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
---Apply draft at specific index (used by inline and diff workflows)
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

---Materialize drafts as conflict markers (background process)
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

-- Virtual text overlay system (adapted from legacy-v3)
local ns_id = vim.api.nvim_create_namespace('pairup_drafts_overlay')
local rendered = {} -- Track which buffers have overlays: {[bufnr] = {[marker_line] = draft_id}}

---Build virtual lines for a draft
---@param draft table
---@return table[] virt_lines
local function build_virt_lines(draft)
  local virt_lines = {}
  local old_lines = vim.split(draft.old_string or '', '\n', { plain = true })
  local new_lines = vim.split(draft.new_string or '', '\n', { plain = true })

  -- Header
  table.insert(virt_lines, {
    { '╭─ Claude suggests: ', 'PairupHeader' },
  })

  -- Show old lines (deletion/replacement)
  if #old_lines > 0 and old_lines[1] ~= '' then
    table.insert(virt_lines, { { '│ ', 'PairupBorder' }, { '── Original ──', 'PairupSubHeader' } })
    for _, line in ipairs(old_lines) do
      table.insert(virt_lines, { { '│ ', 'PairupBorder' }, { line, 'PairupDelete' } })
    end
  end

  -- Show new lines (insertion/replacement)
  if #new_lines > 0 then
    if #old_lines > 0 and old_lines[1] ~= '' then
      table.insert(virt_lines, { { '│ ', 'PairupBorder' }, { '── Suggestion ──', 'PairupSubHeader' } })
    end
    for _, line in ipairs(new_lines) do
      table.insert(virt_lines, { { '│ ', 'PairupBorder' }, { line, 'PairupAdd' } })
    end
  end

  -- Footer with keybindings
  table.insert(virt_lines, {
    { '╰─ ', 'PairupBorder' },
    { 'ga', 'PairupAcceptKey' },
    { '=accept  ', 'PairupHint' },
    { 'gx', 'PairupRejectKey' },
    { '=reject', 'PairupHint' },
  })

  return virt_lines
end

---Render draft as virtual text at marker position
---@param bufnr number
---@param draft table
local function render_draft(bufnr, draft)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local marker_line = draft.marker_line
  if not marker_line or marker_line < 1 then
    return
  end

  local line_count = vim.api.nvim_buf_line_count(bufnr)
  if marker_line > line_count then
    return
  end

  -- Build and place virtual lines
  local virt_lines = build_virt_lines(draft)
  local ok = pcall(vim.api.nvim_buf_set_extmark, bufnr, ns_id, marker_line - 1, 0, {
    virt_lines = virt_lines,
    virt_lines_above = false,
    priority = 100,
    id = tonumber(draft.id),
  })

  if ok then
    if not rendered[bufnr] then
      rendered[bufnr] = {}
    end
    rendered[bufnr][marker_line] = draft.id
  end
end

---Clear all draft overlays from buffer
---@param bufnr number
function M.clear_overlays(bufnr)
  if not bufnr then
    bufnr = vim.api.nvim_get_current_buf()
  end
  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
  end
  rendered[bufnr] = nil
end

---Render all drafts for current buffer as virtual text
function M.render_all()
  local bufnr = vim.api.nvim_get_current_buf()
  local filepath = vim.api.nvim_buf_get_name(bufnr)

  -- Clear existing overlays
  M.clear_overlays(bufnr)

  -- Get drafts for this file
  local all = M.get_all()
  for _, draft in ipairs(all) do
    if draft.file == filepath and draft.marker_line then
      render_draft(bufnr, draft)
    end
  end
end

---Find draft at cursor position
---@return table|nil draft
---@return number|nil index
function M.find_at_cursor()
  local bufnr = vim.api.nvim_get_current_buf()
  local filepath = vim.api.nvim_buf_get_name(bufnr)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = cursor[1]

  -- Check for extmarks in range (virtual text appears below extmark position)
  local start_line = math.max(0, line - 10)
  local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, { start_line, 0 }, { line, 0 }, {})
  if #marks == 0 then
    return nil, nil
  end

  -- Use closest extmark before cursor
  local draft_id = tostring(marks[#marks][1])

  -- Find draft in list
  local all = M.get_all()
  for idx, draft in ipairs(all) do
    if draft.id == draft_id and draft.file == filepath then
      return draft, idx
    end
  end

  return nil, nil
end

---Accept draft at cursor (apply edit, remove marker, clear overlay)
function M.accept_at_cursor()
  local draft, idx = M.find_at_cursor()
  if not draft then
    vim.notify('No draft at cursor', vim.log.levels.WARN)
    return
  end

  local ok, msg = M.apply_at_index(idx)
  if ok then
    M.clear_overlays(vim.api.nvim_get_current_buf())
    -- TODO: Remove marker line
    vim.notify(msg, vim.log.levels.INFO)
    -- Re-render remaining drafts
    vim.defer_fn(M.render_all, 100)
  else
    vim.notify(msg, vim.log.levels.ERROR)
  end
end

---Reject draft at cursor (remove from queue, clear overlay, keep marker)
function M.reject_at_cursor()
  local draft, idx = M.find_at_cursor()
  if not draft then
    vim.notify('No draft at cursor', vim.log.levels.WARN)
    return
  end

  -- Remove from queue
  local all = M.get_all()
  table.remove(all, idx)

  if #all == 0 then
    M.clear()
  else
    local f = io.open(DRAFTS_FILE, 'w')
    if f then
      f:write(vim.json.encode(all))
      f:close()
    end
  end

  M.clear_overlays(vim.api.nvim_get_current_buf())
  vim.notify('Draft rejected', vim.log.levels.INFO)
  vim.defer_fn(M.render_all, 100)
end

return M
