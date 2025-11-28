-- Flash highlights for changed lines after external file modification

local M = {}

local buffer_snapshots = {} -- bufnr -> { lines = {}, mtime = number }
local ns = vim.api.nvim_create_namespace('pairup_flash')

---Setup flash highlight (respects light/dark background)
---Users can override with: vim.api.nvim_set_hl(0, 'PairupFlash', { ... })
local function setup_highlight()
  local existing = vim.api.nvim_get_hl(0, { name = 'PairupFlash' })
  if vim.tbl_isempty(existing) then
    local is_light = vim.o.background == 'light'
    vim.api.nvim_set_hl(0, 'PairupFlash', {
      bg = is_light and '#d4edda' or '#2d4f2d', -- subtle green
    })
  end
end

setup_highlight()

---Get file mtime
---@param bufnr integer
---@return number|nil
local function get_mtime(bufnr)
  local filepath = vim.api.nvim_buf_get_name(bufnr)
  if filepath == '' then
    return nil
  end
  local stat = vim.loop.fs_stat(filepath)
  return stat and stat.mtime.sec or nil
end

---Store current buffer content as snapshot (only if mtime unchanged)
---@param bufnr integer
function M.snapshot(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if vim.bo[bufnr].buftype ~= '' then
    return
  end

  local mtime = get_mtime(bufnr)
  local existing = buffer_snapshots[bufnr]

  -- Only update snapshot if no existing or mtime changed (file was modified externally)
  if existing and existing.mtime == mtime then
    return -- Keep existing snapshot
  end

  buffer_snapshots[bufnr] = {
    lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false),
    mtime = mtime,
  }
end

---Compare current buffer with snapshot and highlight changed lines
---@param bufnr integer
---@param timeout integer? Duration in ms (default 3000)
function M.highlight_changes(bufnr, timeout)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  timeout = timeout or 3000

  local snapshot = buffer_snapshots[bufnr]
  if not snapshot then
    return
  end

  local old_lines = snapshot.lines
  local new_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  -- Use vim.diff for proper LCS-based diff
  local old_text = table.concat(old_lines, '\n') .. '\n'
  local new_text = table.concat(new_lines, '\n') .. '\n'

  local diff = vim.diff(old_text, new_text, { result_type = 'indices' })
  -- diff returns list of hunks: {old_start, old_count, new_start, new_count}

  local changed_lines = {}
  for _, hunk in ipairs(diff) do
    local new_start, new_count = hunk[3], hunk[4]
    -- Highlight all new/modified lines in this hunk
    for i = new_start, new_start + new_count - 1 do
      changed_lines[i] = true
    end
  end

  -- Clear snapshot
  buffer_snapshots[bufnr] = nil

  -- Highlight changed lines using vim.hl.range (Neovim 0.11+)
  for lnum in pairs(changed_lines) do
    if lnum <= #new_lines then
      pcall(vim.hl.range, bufnr, ns, 'PairupFlash', { lnum - 1, 0 }, { lnum - 1, #new_lines[lnum] }, {
        timeout = timeout,
      })
    end
  end

  return vim.tbl_count(changed_lines)
end

---Clear snapshot for buffer
---@param bufnr integer?
function M.clear(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  buffer_snapshots[bufnr] = nil
end

return M
