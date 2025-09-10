local M = {}

-- RPC state tracking
local state = {
  enabled = false,
  terminal_window = nil,
  main_window = nil,
  main_buffer = nil,
  rpc_port = '127.0.0.1:6666',
}

-- Check if RPC server is available
function M.check_rpc_available()
  -- Only check for TCP server on the configured port
  -- vim.v.servername contains the address when started with --listen
  local servername = vim.v.servername or ''

  -- Check if servername is a TCP address (contains IP:port or just :port)
  -- Examples: "127.0.0.1:6666", "localhost:6666", ":6666"
  -- Unix sockets look like: "/run/user/1000/nvim.xxxxx.0"
  if servername:match('^[^/]*:%d+$') then
    -- Extract port from servername
    local port = servername:match(':(%d+)$')
    -- Check if it matches our expected port (just the number part)
    local expected_port = state.rpc_port:match('(%d+)$') or '6666'
    return port == expected_port
  end

  return false
end

-- Initialize RPC support when pairup starts
function M.setup(opts)
  opts = opts or {}

  -- Allow configuring the expected RPC port
  if opts.rpc_port then
    state.rpc_port = opts.rpc_port
  end

  -- Auto-detect RPC on startup
  if M.check_rpc_available() then
    state.enabled = true

    -- Track window layout
    M.update_layout()

    -- Set up auto-tracking
    vim.api.nvim_create_autocmd({ 'WinEnter', 'BufEnter' }, {
      group = vim.api.nvim_create_augroup('PairupRPC', { clear = true }),
      callback = function()
        M.update_layout()
      end,
    })
  end
end

-- Update layout tracking
function M.update_layout()
  if not state.enabled then
    return
  end

  -- Find terminal buffer (pairup assistant)
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.b[buf].is_pairup_assistant then
      state.terminal_window = vim.api.nvim_win_get_number(win)
    else
      -- Track the main editing window
      local bufname = vim.api.nvim_buf_get_name(buf)
      if bufname ~= '' and not bufname:match('^term://') then
        state.main_window = vim.api.nvim_win_get_number(win)
        state.main_buffer = buf
      end
    end
  end
end

-- =============================================================================
-- CLAUDE-FRIENDLY RPC FUNCTIONS
-- These are what Claude calls via: --remote-expr 'lua require("pairup.rpc").function_name()'
-- =============================================================================

-- Get current context (Claude's most important function!)
function M.get_context()
  M.update_layout()
  return vim.json.encode({
    rpc_enabled = state.enabled,
    terminal_window = state.terminal_window,
    main_window = state.main_window,
    main_buffer = state.main_buffer,
    main_file = state.main_buffer and vim.api.nvim_buf_get_name(state.main_buffer) or nil,
    modified = state.main_buffer and vim.api.nvim_buf_get_option(state.main_buffer, 'modified') or false,
    cwd = vim.fn.getcwd(),
    windows = M.get_window_info(),
  })
end

-- Get info about all windows
function M.get_window_info()
  local windows = {}
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    local bufname = vim.api.nvim_buf_get_name(buf)
    table.insert(windows, {
      win = vim.api.nvim_win_get_number(win),
      buf = buf,
      name = bufname,
      type = bufname:match('^term://') and 'terminal' or 'file',
      is_pairup = vim.b[buf].is_pairup_assistant or false,
    })
  end
  return windows
end

-- Read the main file buffer (not the terminal!)
function M.read_main_buffer(start_line, end_line)
  if not state.main_buffer then
    return vim.json.encode({ error = 'No main buffer found' })
  end

  start_line = start_line or 1
  end_line = end_line or -1

  local lines = vim.api.nvim_buf_get_lines(state.main_buffer, start_line - 1, end_line, false)
  return vim.json.encode(lines)
end

-- Helper functions for common patterns
function M.escape_pattern(pattern)
  -- Helper to properly escape patterns for vim search/replace
  -- This helps with common escaping issues
  return pattern
end

-- Smart execute function - takes commands as you'd type them in Vim
-- Examples: "w" to save, "42" for line 42, "%s/old/new/g" to replace
-- For patterns with quotes, use Lua long strings: [[%s/'old'/'new'/g]]
function M.execute(command)
  if not state.main_window then
    return vim.json.encode({ error = 'No main window found' })
  end

  -- Save current window
  local current_win = vim.api.nvim_get_current_win()

  -- Execute in main window
  vim.cmd(state.main_window .. 'wincmd w')
  local ok, result = pcall(vim.cmd, command)

  -- Restore window
  vim.api.nvim_set_current_win(current_win)

  -- Provide more informative success messages
  local response = {
    success = ok,
    executed_in_window = state.main_window,
    command = command,
  }

  if ok then
    -- Add context for certain command types
    if command:match('^%d+$') then
      response.message = 'Jumped to line ' .. command
    elseif command:match('^w$') or command:match('^write') then
      response.message = 'File saved'
    elseif command:match('^%%s/') or command:match('^s/') or command:match('%d+,%d+s/') then
      response.message = 'Substitution completed'
    elseif command:match('^u$') or command:match('^undo') then
      response.message = 'Undo completed'
    elseif command:match('^normal ') then
      response.message = 'Normal mode command executed'
    else
      response.result = result or ''
    end
  else
    response.error = result
  end

  return vim.json.encode(response)
end

-- Helper function for safe substitution commands
function M.substitute(pattern, replacement, flags)
  -- Use Lua long strings to avoid escaping issues
  flags = flags or 'g'
  local cmd = string.format([[%%s/%s/%s/%s]], pattern, replacement, flags)
  return M.execute(cmd)
end

-- Helper for patterns with special characters
function M.execute_raw(command)
  -- Execute command using Lua long string to avoid escaping
  return M.execute(command)
end

-- Backward compatibility alias
M.execute_in_main = M.execute

-- These wrapper functions are DEPRECATED - just use execute() directly!
-- Keeping for backward compatibility only
function M.save()
  return M.execute('w')
end
function M.goto_line(line)
  return M.execute(tostring(line))
end
function M.replace(pattern, replacement, flags)
  flags = flags or 'g'
  local cmd = string.format('%%s/%s/%s/%s', pattern, replacement, flags)
  return M.execute(cmd)
end

-- Get buffer statistics
function M.get_stats()
  if not state.main_buffer then
    return vim.json.encode({ error = 'No main buffer found' })
  end

  -- Switch to main window for wordcount
  local current_win = vim.api.nvim_get_current_win()
  vim.cmd(state.main_window .. 'wincmd w')
  local wc = vim.fn.wordcount()
  vim.api.nvim_set_current_win(current_win)

  return vim.json.encode({
    lines = vim.api.nvim_buf_line_count(state.main_buffer),
    words = wc.words,
    chars = wc.chars,
    bytes = wc.bytes,
  })
end

-- Set/get registers (useful for Claude)
function M.set_register(reg, content)
  vim.fn.setreg(reg, content)
  return vim.json.encode({ success = true })
end

function M.get_register(reg)
  return vim.json.encode({ content = vim.fn.getreg(reg) })
end

-- Get RPC instructions for Claude
function M.get_instructions()
  if not state.enabled then
    return nil
  end

  -- Get the actual server name
  local servername = vim.v.servername or '/tmp/nvim'

  -- Load instructions from markdown file
  local source_path = debug.getinfo(1, 'S').source:sub(2)
  local plugin_root = vim.fn.fnamemodify(source_path, ':h:h:h') -- Go up 3 levels from lua/pairup/rpc.lua
  local prompt_file = plugin_root .. '/lua/pairup/prompts/rpc_instructions.md'

  -- Read the markdown file
  local file = io.open(prompt_file, 'r')
  if not file then
    vim.notify('Failed to load RPC instructions from: ' .. prompt_file, vim.log.levels.ERROR)
    return nil
  end

  local content = file:read('*all')
  file:close()

  -- Replace %s placeholders with the actual servername
  content = content:gsub('%%s', servername)

  return '\n' .. content .. '\n'
end

-- Check if RPC is enabled
function M.is_enabled()
  return state.enabled
end

-- Show overlay suggestion in buffer (with base64 encoding to avoid escaping issues)
function M.show_overlay_base64(line_num, old_text_b64, new_text_b64)
  local overlay = require('pairup.overlay')
  overlay.setup()

  -- Use main buffer if available
  if not state.main_buffer then
    return vim.json.encode({ error = 'No main buffer found' })
  end

  -- Decode base64 strings safely
  local old_text = nil
  local new_text = nil

  if old_text_b64 and old_text_b64 ~= '' then
    old_text = vim.fn.decode(vim.fn.split(old_text_b64, '\zs'), 'base64')
  end

  if new_text_b64 and new_text_b64 ~= '' then
    new_text = vim.fn.decode(vim.fn.split(new_text_b64, '\zs'), 'base64')
  end

  overlay.show_suggestion(state.main_buffer, line_num, old_text, new_text)
  return vim.json.encode({ success = true, message = 'Overlay shown at line ' .. line_num })
end

-- Show overlay suggestion in buffer (supports reasoning)
function M.show_overlay(line_num, old_text, new_text, reasoning)
  local overlay = require('pairup.overlay')
  overlay.setup()

  -- Use main buffer if available
  if not state.main_buffer then
    return vim.json.encode({ error = 'No main buffer found' })
  end

  overlay.show_suggestion(state.main_buffer, line_num, old_text, new_text, reasoning)
  return vim.json.encode({ success = true, message = 'Overlay shown at line ' .. line_num })
end

-- Clear all overlays
function M.clear_overlays()
  require('pairup.overlay').clear_overlays()
  return vim.json.encode({ success = true })
end

-- Show multiline overlay (for complex changes)
function M.show_multiline_overlay(start_line, end_line, old_lines_json, new_lines_json)
  local overlay = require('pairup.overlay')
  overlay.setup()

  if not state.main_buffer then
    return vim.json.encode({ error = 'No main buffer found' })
  end

  -- Parse JSON arrays
  local ok_old, old_lines = pcall(vim.json.decode, old_lines_json or '[]')
  local ok_new, new_lines = pcall(vim.json.decode, new_lines_json or '[]')

  if not ok_old or not ok_new then
    return vim.json.encode({ error = 'Invalid JSON arrays' })
  end

  overlay.show_multiline_suggestion(state.main_buffer, start_line, end_line, old_lines, new_lines)
  return vim.json.encode({ success = true, message = 'Multiline overlay shown' })
end

-- Show overlay via JSON (avoids ALL escaping issues)
function M.show_overlay_json(json_str)
  local overlay = require('pairup.overlay')
  overlay.setup()

  if not state.main_buffer then
    return vim.json.encode({ error = 'No main buffer found' })
  end

  -- Parse JSON object
  local ok, data = pcall(vim.json.decode, json_str)
  if not ok then
    return vim.json.encode({ error = 'Invalid JSON: ' .. tostring(data) })
  end

  -- Handle single line (with optional reasoning)
  if data.line then
    overlay.show_suggestion(state.main_buffer, data.line, data.old_text, data.new_text, data.reasoning)
    return vim.json.encode({ success = true, message = 'Overlay shown at line ' .. data.line })
  -- Handle multiline (with optional reasoning)
  elseif data.start_line and data.end_line then
    overlay.show_multiline_suggestion(
      state.main_buffer,
      data.start_line,
      data.end_line,
      data.old_lines,
      data.new_lines,
      data.reasoning
    )
    return vim.json.encode({ success = true, message = 'Multiline overlay shown' })
  else
    return vim.json.encode({ error = 'JSON must have either "line" or "start_line/end_line"' })
  end
end

-- Send overlay via file (ultimate escaping solution)
function M.show_overlay_file(filepath)
  local overlay = require('pairup.overlay')
  overlay.setup()

  if not state.main_buffer then
    return vim.json.encode({ error = 'No main buffer found' })
  end

  -- Read JSON from file
  local file = io.open(filepath, 'r')
  if not file then
    return vim.json.encode({ error = 'Cannot read file: ' .. filepath })
  end

  local json_str = file:read('*all')
  file:close()

  -- Use the JSON function
  return M.show_overlay_json(json_str)
end

-- Apply overlay at given line
function M.apply_overlay(line_num)
  local overlay = require('pairup.overlay')

  -- Switch to main window first
  if state.main_window then
    vim.cmd(state.main_window .. 'wincmd w')
  end

  -- Set cursor to the line
  vim.api.nvim_win_set_cursor(0, { line_num, 0 })

  -- Apply the overlay
  local result = overlay.apply_at_cursor()

  return vim.json.encode({ success = result })
end

-- Get available plugins and commands for Claude
function M.get_capabilities()
  local caps = {
    plugins = {},
    commands = {},
    lsp_clients = {},
    keymaps = {},
  }

  -- Get plugins if lazy.nvim is available
  local ok, lazy = pcall(require, 'lazy.core.config')
  if ok then
    caps.plugins = vim.tbl_keys(lazy.plugins)
  end

  -- Get user commands
  caps.commands = vim.tbl_keys(vim.api.nvim_get_commands({}))

  -- Get active LSP clients
  -- Use get_clients for Neovim 0.10+ compatibility, fallback to get_active_clients
  local get_clients = vim.lsp.get_clients or vim.lsp.get_active_clients
  for _, client in pairs(get_clients()) do
    table.insert(caps.lsp_clients, client.name)
  end

  -- Get leader key mappings (sample)
  local maps = vim.api.nvim_get_keymap('n')
  for _, map in ipairs(maps) do
    if map.lhs:match('^<leader>') then
      table.insert(caps.keymaps, {
        lhs = map.lhs,
        rhs = map.rhs or map.callback and '[Lua function]' or '',
        desc = map.desc,
      })
    end
  end

  return vim.json.encode(caps)
end

-- JSON-based overlay creation (handles all escaping issues)
function M.show_overlay_json(json_str)
  local ok, data = pcall(vim.json.decode, json_str)
  if not ok then
    return vim.json.encode({ error = 'Invalid JSON: ' .. tostring(data) })
  end

  local overlay = require('pairup.overlay')
  overlay.setup()

  if not state.main_buffer then
    return vim.json.encode({ error = 'No main buffer found' })
  end

  -- Handle both single and multiline overlays
  if data.is_multiline then
    overlay.show_multiline_suggestion(
      state.main_buffer,
      data.start_line,
      data.end_line,
      data.old_lines,
      data.new_lines,
      data.reasoning
    )
  else
    overlay.show_suggestion(state.main_buffer, data.line, data.old_text, data.new_text, data.reasoning)
  end

  return vim.json.encode({ success = true, message = 'Overlay created' })
end

-- Load overlay from a file (avoids all command line escaping)
function M.show_overlay_file(filepath)
  local file = io.open(filepath, 'r')
  if not file then
    return vim.json.encode({ error = 'Cannot read file: ' .. filepath })
  end

  local content = file:read('*all')
  file:close()

  return M.show_overlay_json(content)
end

-- In-memory overlay queue
local overlay_queue = {}
local max_queue_size = 50

-- Add overlay to queue (for Claude to use directly)
function M.queue_overlay(json_data)
  -- Parse the JSON data
  local ok, data = pcall(vim.json.decode, json_data)
  if not ok then
    return vim.json.encode({ error = 'Invalid JSON: ' .. tostring(data) })
  end

  -- Add to queue with timestamp
  data.timestamp = os.time()
  table.insert(overlay_queue, data)

  -- Limit queue size
  if #overlay_queue > max_queue_size then
    table.remove(overlay_queue, 1)
  end

  -- Apply the overlay immediately
  local result = M.show_overlay_json(json_data)

  return result
end

-- Apply all queued overlays
function M.apply_queued_overlays()
  local applied = 0
  local failed = 0

  for _, data in ipairs(overlay_queue) do
    local json = vim.json.encode(data)
    local result = M.show_overlay_json(json)
    local response = vim.json.decode(result)

    if response.success then
      applied = applied + 1
    else
      failed = failed + 1
    end
  end

  return vim.json.encode({
    success = true,
    applied = applied,
    failed = failed,
    total = #overlay_queue,
  })
end

-- Clear overlay queue
function M.clear_overlay_queue()
  local count = #overlay_queue
  overlay_queue = {}
  return vim.json.encode({ success = true, cleared = count })
end

-- Get overlay queue status
function M.get_overlay_queue()
  return vim.json.encode({
    queued = #overlay_queue,
    max_size = max_queue_size,
    overlays = overlay_queue,
  })
end

-- Get XDG data directory for persistent storage
function M.get_data_dir()
  local xdg_data = vim.env.XDG_DATA_HOME or (vim.env.HOME .. '/.local/share')
  local data_dir = xdg_data .. '/nvim/pairup/overlays'
  return data_dir
end

-- Export overlays to file (for user to save/share)
function M.export_overlays(filename)
  if not filename then
    -- Use default location with timestamp
    local data_dir = M.get_data_dir()
    vim.fn.mkdir(data_dir, 'p')
    filename = string.format('%s/overlays_%s.json', data_dir, os.date('%Y%m%d_%H%M%S'))
  end

  local file = io.open(filename, 'w')
  if not file then
    return vim.json.encode({ error = 'Cannot create file: ' .. filename })
  end

  -- Get current suggestions from all buffers
  local overlay = require('pairup.overlay')
  local all_suggestions = {}

  -- Export from overlay module
  for bufnr, suggestions in pairs(overlay.get_all_suggestions and overlay.get_all_suggestions() or {}) do
    if vim.api.nvim_buf_is_valid(bufnr) then
      local buf_name = vim.api.nvim_buf_get_name(bufnr)
      all_suggestions[buf_name] = suggestions
    end
  end

  -- Also include queued overlays
  all_suggestions.queued = overlay_queue

  file:write(vim.json.encode(all_suggestions, { indent = true }))
  file:close()

  return vim.json.encode({ success = true, file = filename })
end

-- Import overlays from file
function M.import_overlays(filename)
  if not filename then
    -- Look for most recent export
    local data_dir = M.get_data_dir()
    local files = vim.fn.glob(data_dir .. '/overlays_*.json', false, true)
    if #files == 0 then
      return vim.json.encode({ error = 'No overlay files found' })
    end
    table.sort(files)
    filename = files[#files]
  end

  local file = io.open(filename, 'r')
  if not file then
    return vim.json.encode({ error = 'Cannot read file: ' .. filename })
  end

  local content = file:read('*all')
  file:close()

  local ok, data = pcall(vim.json.decode, content)
  if not ok then
    return vim.json.encode({ error = 'Invalid JSON in file' })
  end

  -- Import queued overlays
  if data.queued then
    overlay_queue = data.queued
  end

  -- Apply overlays to buffers
  local imported = 0
  for buf_name, suggestions in pairs(data) do
    if buf_name ~= 'queued' then
      -- Find or create buffer
      local bufnr = vim.fn.bufnr(buf_name)
      if bufnr ~= -1 then
        -- Apply suggestions to buffer
        for line_num, suggestion in pairs(suggestions) do
          if type(line_num) == 'number' then
            imported = imported + 1
            -- Apply suggestion
            local overlay = require('pairup.overlay')
            if suggestion.is_multiline then
              overlay.show_multiline_suggestion(
                bufnr,
                suggestion.start_line,
                suggestion.end_line,
                suggestion.old_lines,
                suggestion.new_lines,
                suggestion.reasoning
              )
            else
              overlay.show_suggestion(bufnr, line_num, suggestion.old_text, suggestion.new_text, suggestion.reasoning)
            end
          end
        end
      end
    end
  end

  return vim.json.encode({ success = true, imported = imported, file = filename })
end

-- Batch overlay operations (for complex multiline suggestions)
function M.batch_add_single(line, old_text, new_text, reasoning)
  local batch = require('pairup.overlay_batch')
  local id = batch.add_single(line, old_text, new_text, reasoning)
  return vim.json.encode({ success = true, id = id })
end

function M.batch_add_multiline(start_line, end_line, old_lines, new_lines, reasoning)
  local batch = require('pairup.overlay_batch')
  local id = batch.add_multiline(start_line, end_line, old_lines, new_lines, reasoning)
  return vim.json.encode({ success = true, id = id })
end

function M.batch_add_deletion(line, old_text, reasoning)
  local batch = require('pairup.overlay_batch')
  local id = batch.add_deletion(line, old_text, reasoning)
  return vim.json.encode({ success = true, id = id })
end

function M.batch_apply()
  local batch = require('pairup.overlay_batch')
  local result = batch.apply_batch()
  return vim.json.encode(result)
end

function M.batch_clear()
  local batch = require('pairup.overlay_batch')
  batch.clear_batch()
  return vim.json.encode({ success = true })
end

function M.batch_status()
  local batch = require('pairup.overlay_batch')
  local status = batch.get_batch_status()
  return vim.json.encode(status)
end

-- Build and apply batch from structured data
function M.batch_from_json(json_data)
  local batch = require('pairup.overlay_batch')

  local ok, data = pcall(vim.json.decode, json_data)
  if not ok then
    return vim.json.encode({ error = 'Invalid JSON: ' .. tostring(data) })
  end

  local status = batch.build_from_data(data)
  local result = batch.apply_batch()

  return vim.json.encode(result)
end

-- Get RPC state (for batch operations to access)
function M.get_state()
  return state
end

-- Base64 batch operations (completely avoids escaping)
function M.batch_b64(base64_data)
  local batch = require('pairup.overlay_batch')

  -- Use vim.base64.decode if available (Neovim 0.10+)
  local decoded
  if vim.base64 and vim.base64.decode then
    local ok_decode, result = pcall(vim.base64.decode, base64_data)
    if ok_decode then
      decoded = result
    end
  end

  -- Fallback to vim.fn.decode
  if not decoded then
    local ok_decode, result = pcall(vim.fn.decode, base64_data, 'base64')
    if ok_decode then
      decoded = result
    end
  end

  -- Final fallback to system command
  if not decoded then
    decoded = vim.fn.system('echo ' .. vim.fn.shellescape(base64_data) .. ' | base64 -d')
    if vim.v.shell_error ~= 0 then
      return vim.json.encode({ error = 'Failed to decode base64', success = false })
    end
  end

  local ok, data = pcall(vim.json.decode, decoded)
  if not ok then
    return vim.json.encode({ error = 'Invalid JSON after base64 decode: ' .. tostring(data), success = false })
  end

  local status = batch.build_from_data(data)
  local result = batch.apply_batch()

  return vim.json.encode(result)
end

-- Simple overlay using line numbers (no text matching needed)
function M.simple_overlay(line_num, new_text, reasoning)
  local overlay = require('pairup.overlay')
  overlay.setup()

  if not state.main_buffer then
    return vim.json.encode({ error = 'No main buffer found' })
  end

  -- Get the current line text
  local lines = vim.api.nvim_buf_get_lines(state.main_buffer, line_num - 1, line_num, false)
  if #lines == 0 then
    return vim.json.encode({ error = 'Line ' .. line_num .. ' does not exist' })
  end

  local old_text = lines[1]

  -- Apply the overlay
  overlay.show_suggestion(state.main_buffer, line_num, old_text, new_text, reasoning)

  return vim.json.encode({ success = true, message = 'Overlay applied at line ' .. line_num })
end

-- Clear all overlays
function M.clear_all_overlays()
  local overlay = require('pairup.overlay')
  if state.main_buffer then
    overlay.clear_overlays(state.main_buffer)
  end
  return vim.json.encode({ success = true })
end

-- ============================================================================
-- SIMPLIFIED OVERLAY API - USE THESE INSTEAD OF THE COMPLEX ONES ABOVE
-- ============================================================================

-- Create single-line overlay (most robust method)
function M.overlay_single(line, new_text, reasoning)
  -- Use simple_overlay as fallback to avoid state issues
  return M.simple_overlay(line, new_text, reasoning)
end

-- Create multi-line overlay (most robust method)
function M.overlay_multiline(start_line, end_line, new_lines, reasoning)
  local state = M.get_state()
  if not state.main_buffer then
    return vim.json.encode({ error = 'No main buffer found' })
  end

  local overlay = require('pairup.overlay')

  -- Get old lines
  local old_lines = vim.api.nvim_buf_get_lines(state.main_buffer, start_line - 1, end_line, false)

  -- Ensure new_lines is a table
  if type(new_lines) == 'string' then
    new_lines = vim.split(new_lines, '\n', { plain = true })
  end

  overlay.show_multiline_suggestion(state.main_buffer, start_line, end_line, old_lines, new_lines, reasoning or '')

  return vim.json.encode({
    success = true,
    start_line = start_line,
    end_line = end_line,
    message = 'Multiline overlay created',
  })
end

-- Clear all overlays
function M.overlay_clear()
  local state = M.get_state()
  if not state.main_buffer then
    return vim.json.encode({ error = 'No main buffer found' })
  end

  local overlay = require('pairup.overlay')
  overlay.clear_overlays(state.main_buffer)
  return vim.json.encode({ success = true, message = 'All overlays cleared' })
end

-- Accept overlay at line
function M.overlay_accept(line)
  local state = M.get_state()
  if not state.main_buffer then
    return vim.json.encode({ error = 'No main buffer found' })
  end

  local overlay = require('pairup.overlay')
  overlay.apply_at_line(state.main_buffer, line)
  return vim.json.encode({ success = true, line = line, message = 'Overlay accepted' })
end

-- Reject overlay at line
function M.overlay_reject(line)
  local state = M.get_state()
  if not state.main_buffer then
    return vim.json.encode({ error = 'No main buffer found' })
  end

  local overlay = require('pairup.overlay')
  overlay.reject_at_line(state.main_buffer, line)
  return vim.json.encode({ success = true, line = line, message = 'Overlay rejected' })
end

-- List all overlays
function M.overlay_list()
  local state = M.get_state()
  if not state.main_buffer then
    return vim.json.encode({ error = 'No main buffer found', overlays = {}, count = 0 })
  end

  local overlay = require('pairup.overlay')
  local suggestions = overlay.get_suggestions(state.main_buffer)
  local list = {}

  for line_num, suggestion in pairs(suggestions) do
    table.insert(list, {
      line = line_num,
      old_text = suggestion.old_text,
      new_text = suggestion.new_text,
      reasoning = suggestion.reasoning,
    })
  end

  -- Sort by line number
  table.sort(list, function(a, b)
    return a.line < b.line
  end)

  return vim.json.encode({
    success = true,
    overlays = list,
    count = #list,
  })
end

-- Accept-safe JSON handling (Claude sends raw JSON, we handle encoding)
function M.overlay_json_safe(json_str)
  -- This function accepts raw JSON string without any encoding
  -- Claude can send complex JSON without worrying about escaping
  local ok, data = pcall(vim.json.decode, json_str)
  if not ok then
    return vim.json.encode({ error = 'Invalid JSON: ' .. tostring(data) })
  end

  local overlay = require('pairup.overlay')
  overlay.setup()

  if not state.main_buffer then
    return vim.json.encode({ error = 'No main buffer found' })
  end

  -- Handle batch operations
  if data.batch or data.overlays then
    local batch = require('pairup.overlay_batch')
    batch.clear_batch()

    local overlays = data.overlays or {}
    local count = 0

    for _, o in ipairs(overlays) do
      if o.type == 'multiline' then
        batch.add_multiline(o.start_line, o.end_line, o.old_lines, o.new_lines, o.reasoning)
      elseif o.type == 'deletion' then
        batch.add_deletion(o.start_line, o.end_line, o.reasoning)
      else
        batch.add_single(o.line, o.old_text, o.new_text, o.reasoning)
      end
      count = count + 1
    end

    local result = batch.apply_batch()
    return vim.json.encode({ success = true, count = count, applied = result.applied })
  end

  -- Handle deletion overlays
  if data.type == 'deletion' then
    overlay.show_deletion_suggestion(state.main_buffer, data.start_line, data.end_line, data.reasoning)
    return vim.json.encode({ success = true, count = 1 })
  end

  -- Validate required fields for single/multiline
  if data.type == 'multiline' or data.is_multiline then
    if not data.start_line or not data.end_line or not data.new_lines then
      return vim.json.encode({ error = 'Multiline overlay missing required fields', success = false })
    end
    overlay.show_multiline_suggestion(
      state.main_buffer,
      data.start_line,
      data.end_line,
      data.old_lines,
      data.new_lines,
      data.reasoning
    )
  else
    if not data.line or not data.new_text then
      return vim.json.encode({ error = 'Single overlay missing required fields', success = false })
    end
    overlay.show_suggestion(state.main_buffer, data.line, data.old_text, data.new_text, data.reasoning)
  end

  return vim.json.encode({ success = true, count = 1 })
end

return M
