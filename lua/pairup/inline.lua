-- Inline conversational editing for pairup.nvim
-- Detects cc: (Claude Command) and uu: (User Question) markers

local M = {}
local config = require('pairup.config')
local providers = require('pairup.providers')

--- Detect cc:/uu: markers in buffer
---@param bufnr? number Buffer number (defaults to current)
---@return table[] markers List of {line, type, content}
function M.detect_markers(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  if not vim.api.nvim_buf_is_valid(bufnr) then
    return {}
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local markers = {}

  local cc_pattern = config.get('inline.markers.command') or 'cc:'
  local uu_pattern = config.get('inline.markers.question') or 'uu:'

  -- Check uu: first (AI questions) since cc: (user commands) should not override
  -- Use find with plain=true for literal matching (markers may contain magic chars)
  for i, line in ipairs(lines) do
    if line:find(uu_pattern, 1, true) then
      table.insert(markers, { line = i, type = 'uu', content = line })
    elseif line:find(cc_pattern, 1, true) then
      table.insert(markers, { line = i, type = 'cc', content = line })
    end
  end

  return markers
end

--- Check if buffer has cc: markers
---@param bufnr? number Buffer number (defaults to current)
---@return boolean
function M.has_cc_markers(bufnr)
  local markers = M.detect_markers(bufnr)
  for _, m in ipairs(markers) do
    if m.type == 'cc' then
      return true
    end
  end
  return false
end

--- Check if buffer has uu: markers
---@param bufnr? number Buffer number (defaults to current)
---@return boolean
function M.has_uu_markers(bufnr)
  local markers = M.detect_markers(bufnr)
  for _, m in ipairs(markers) do
    if m.type == 'uu' then
      return true
    end
  end
  return false
end

--- Build prompt for Claude
---@param filepath string Absolute file path
---@return string
function M.build_prompt(filepath)
  local prompt = require('pairup.prompt')
  local cc_marker = config.get('inline.markers.command') or 'cc:'
  local uu_marker = config.get('inline.markers.question') or 'uu:'
  return prompt.build(filepath, cc_marker, uu_marker)
end

--- Process cc: markers in buffer - send to Claude
---@param bufnr? number Buffer number (defaults to current)
---@return boolean success Whether markers were found and sent
function M.process(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  if not M.has_cc_markers(bufnr) then
    return false
  end

  local filepath = vim.api.nvim_buf_get_name(bufnr)
  if filepath == '' then
    return false
  end

  -- Check if already pending for this file
  local indicator = require('pairup.utils.indicator')
  if indicator.is_pending(filepath) then
    -- Mark as queued - user's new markers will be processed after Claude finishes
    indicator.set_queued()
    return false
  end

  -- Check if Claude is running
  local buf, _, job_id = providers.find_terminal()
  if not buf then
    vim.notify('Claude not running. Use :PairupStart first.', vim.log.levels.WARN)
    return false
  end

  local prompt = M.build_prompt(filepath)

  -- Send to terminal (500ms delay for Enter - proven reliable in v2)
  if job_id then
    vim.fn.chansend(job_id, prompt)
    vim.defer_fn(function()
      vim.fn.chansend(job_id, string.char(13)) -- CR = Enter
    end, 500)
    indicator.set_pending(filepath)
  else
    providers.send_message(prompt)
    indicator.set_pending(filepath)
  end

  return true
end

--- Populate quickfix with uu: markers from all loaded buffers
function M.update_quickfix()
  if not config.get('inline.quickfix') then
    return
  end

  local qf_items = {}

  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) and vim.api.nvim_buf_is_valid(bufnr) then
      local filepath = vim.api.nvim_buf_get_name(bufnr)

      -- Skip terminal buffers and empty paths
      if filepath == '' or filepath:match('^term://') then
        goto continue
      end

      local markers = M.detect_markers(bufnr)

      for _, m in ipairs(markers) do
        if m.type == 'uu' then
          local uu_marker = config.get('inline.markers.question') or 'uu:'
          local text = m.content:match(uu_marker .. '%s*(.+)') or m.content
          table.insert(qf_items, {
            bufnr = bufnr,
            filename = filepath,
            lnum = m.line,
            text = text,
            type = 'W',
          })
        end
      end

      ::continue::
    end
  end

  vim.fn.setqflist(qf_items, 'r')
  vim.fn.setqflist({}, 'a', { title = 'Claude Questions (uu:)' })
  -- Don't auto-open quickfix - user opens with :copen when ready
end

--- Jump to next uu: marker in current buffer
function M.next_question()
  local bufnr = vim.api.nvim_get_current_buf()
  local markers = M.detect_markers(bufnr)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local current_line = cursor[1]

  for _, m in ipairs(markers) do
    if m.type == 'uu' and m.line > current_line then
      vim.api.nvim_win_set_cursor(0, { m.line, 0 })
      return true
    end
  end

  -- Wrap around
  for _, m in ipairs(markers) do
    if m.type == 'uu' then
      vim.api.nvim_win_set_cursor(0, { m.line, 0 })
      return true
    end
  end

  return false
end

return M
