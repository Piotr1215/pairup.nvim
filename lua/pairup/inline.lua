-- Inline conversational editing for pairup.nvim
-- Detects cc: (Claude Command) and uu: (User Question) markers

local M = {}
local config = require('pairup.config')
local providers = require('pairup.providers')

--- Get all configured markers sorted by pattern length (longest first)
---@return table[] Array of {type, pattern} sorted by pattern length descending
local function get_sorted_markers()
  local marker_types = { 'command', 'question', 'constitution', 'plan' }
  local result = {}
  for _, mtype in ipairs(marker_types) do
    local pattern = config.get('inline.markers.' .. mtype)
    if pattern and pattern ~= '' then
      table.insert(result, { type = mtype, pattern = pattern })
    end
  end
  table.sort(result, function(a, b)
    return #a.pattern > #b.pattern
  end)
  return result
end

--- Detect markers in buffer
---@param bufnr? number Buffer number (defaults to current)
---@return table[] markers List of {line, type, content}
function M.detect_markers(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  if not vim.api.nvim_buf_is_valid(bufnr) then
    return {}
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local markers = {}
  local sorted_markers = get_sorted_markers()

  for i, line in ipairs(lines) do
    for _, m in ipairs(sorted_markers) do
      if line:find(m.pattern, 1, true) then
        table.insert(markers, { line = i, type = m.type, content = line })
        break -- First match wins (longest pattern matched first)
      end
    end
  end

  return markers
end

--- Check if buffer has command markers (command, constitution, or plan)
---@param bufnr? number Buffer number (defaults to current)
---@return boolean
function M.has_cc_markers(bufnr)
  local markers = M.detect_markers(bufnr)
  for _, m in ipairs(markers) do
    if m.type == 'command' or m.type == 'constitution' or m.type == 'plan' then
      return true
    end
  end
  return false
end

--- Check if buffer has question markers
---@param bufnr? number Buffer number (defaults to current)
---@return boolean
function M.has_uu_markers(bufnr)
  local markers = M.detect_markers(bufnr)
  for _, m in ipairs(markers) do
    if m.type == 'question' then
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
  local markers = {
    command = config.get('inline.markers.command') or 'cc:',
    question = config.get('inline.markers.question') or 'uu:',
    constitution = config.get('inline.markers.constitution') or 'cc!:',
    plan = config.get('inline.markers.plan') or 'ccp:',
  }
  return prompt.build(filepath, markers)
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

  -- Use provider's send function (handles timing reliably)
  providers.send_to_provider(prompt)
  indicator.set_pending(filepath)

  return true
end

--- Populate quickfix with markers from all loaded buffers
---@param filter? string 'claude' for cc:/cc!:/ccp:, 'user' for uu: (default: 'user')
function M.update_quickfix(filter)
  if not config.get('inline.quickfix') then
    return
  end

  filter = filter or 'user'
  local claude_types = { command = true, constitution = true, plan = true }
  local qf_items = {}

  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) and vim.api.nvim_buf_is_valid(bufnr) then
      local filepath = vim.api.nvim_buf_get_name(bufnr)
      local buftype = vim.bo[bufnr].buftype
      if filepath == '' or filepath:match('^term://') or buftype ~= '' then
        goto continue
      end

      for _, m in ipairs(M.detect_markers(bufnr)) do
        local matches = (filter == 'claude' and claude_types[m.type]) or (filter == 'user' and m.type == 'question')
        if matches then
          local marker_key = m.type == 'question' and 'question' or m.type
          local pattern = config.get('inline.markers.' .. marker_key) or ''
          local text = m.content:match(vim.pesc(pattern) .. '%s*(.+)') or m.content
          table.insert(qf_items, { bufnr = bufnr, filename = filepath, lnum = m.line, text = text, type = 'W' })
        end
      end
      ::continue::
    end
  end

  local title = filter == 'claude' and 'Claude Commands (cc:)' or 'User Questions (uu:)'
  vim.fn.setqflist(qf_items, 'r')
  vim.fn.setqflist({}, 'a', { title = title })
end

--- Jump to next uu: marker in current buffer
function M.next_question()
  local bufnr = vim.api.nvim_get_current_buf()
  local markers = M.detect_markers(bufnr)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local current_line = cursor[1]

  for _, m in ipairs(markers) do
    if m.type == 'question' and m.line > current_line then
      vim.api.nvim_win_set_cursor(0, { m.line, 0 })
      return true
    end
  end

  -- Wrap around
  for _, m in ipairs(markers) do
    if m.type == 'question' then
      vim.api.nvim_win_set_cursor(0, { m.line, 0 })
      return true
    end
  end

  return false
end

return M
