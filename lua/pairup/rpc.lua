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
  local servername = vim.v.servername or ''
  if servername:match('^[^/]*:%d+$') then
    local port = servername:match(':(%d+)$')
    local expected_port = state.rpc_port:match('(%d+)$') or '6666'
    return port == expected_port
  end
  return false
end

-- Initialize RPC support when pairup starts
function M.setup(opts)
  opts = opts or {}

  if opts.port then
    state.rpc_port = opts.port
  end

  if M.check_rpc_available() then
    state.enabled = true
    M.update_layout()

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

  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.b[buf].is_pairup_assistant then
      state.terminal_window = vim.api.nvim_win_get_number(win)
    else
      local bufname = vim.api.nvim_buf_get_name(buf)
      if bufname ~= '' and not bufname:match('^term://') then
        state.main_window = vim.api.nvim_win_get_number(win)
        state.main_buffer = buf
      end
    end
  end
end

-- Get current RPC state
function M.get_state()
  M.update_layout()
  return state
end

-- =============================================================================
-- ROBUST RPC FUNCTIONS - Learning from mcp-neovim-server approach
-- =============================================================================

-- Helper to safely encode/decode data
local function safe_json_encode(data)
  local ok, result = pcall(vim.json.encode, data)
  if ok then
    return result
  else
    return vim.json.encode({ error = 'JSON encoding failed', details = tostring(result) })
  end
end

local function safe_json_decode(str)
  if not str or str == '' then
    return nil, 'Empty input'
  end
  local ok, result = pcall(vim.json.decode, str)
  if ok then
    return result, nil
  else
    return nil, tostring(result)
  end
end

-- Main RPC handler using luaeval for complex data
function M.rpc_call(method, args)
  if not state.enabled then
    return { success = false, error = 'RPC not enabled' }
  end

  -- Validate method exists
  if not M[method] then
    return { success = false, error = 'Method not found: ' .. tostring(method) }
  end

  -- Call the method with proper error handling
  local ok, result = pcall(M[method], args)
  if ok then
    return result
  else
    return { success = false, error = tostring(result) }
  end
end

-- =============================================================================
-- SINGLE UNIFIED OVERLAY METHOD - Auto-detects overlay type
-- =============================================================================

-- Smart overlay function that auto-detects the type based on args
function M.apply_overlay(args)
  -- Validate arguments
  if not args or type(args) ~= 'table' then
    return { success = false, error = 'Invalid arguments' }
  end

  -- Update layout to ensure we have the right buffer
  M.update_layout()
  if not state.main_buffer then
    return { success = false, error = 'No main buffer found' }
  end

  local overlay_api = require('pairup.overlay_api')

  -- Auto-detect overlay type based on args structure
  if args.variants then
    -- Has variants - check if single or multiline
    if args.end_line or args.start_line then
      -- Multiline with variants
      local start_line = tonumber(args.start_line)
      local end_line = tonumber(args.end_line)

      if not start_line or not end_line then
        return { success = false, error = 'Missing required parameters: start_line, end_line' }
      end

      -- Validate variants
      if type(args.variants) ~= 'table' or #args.variants == 0 then
        return { success = false, error = 'variants must be a non-empty array' }
      end

      for i, variant in ipairs(args.variants) do
        if type(variant) ~= 'table' then
          return { success = false, error = 'Each variant must be an object' }
        end
        if not variant.new_lines then
          return { success = false, error = 'Variant ' .. i .. ' missing new_lines' }
        end
        -- Ensure new_lines is an array
        if type(variant.new_lines) == 'string' then
          variant.new_lines = { variant.new_lines }
        end
      end

      local result = overlay_api.multiline_variants(start_line, end_line, args.variants)
      return type(result) == 'string' and safe_json_decode(result) or { success = true }
    else
      -- Single line with variants
      local line = tonumber(args.line)

      if not line then
        return { success = false, error = 'Missing required parameter: line' }
      end

      -- Validate variants
      if type(args.variants) ~= 'table' or #args.variants == 0 then
        return { success = false, error = 'variants must be a non-empty array' }
      end
      for i, variant in ipairs(args.variants) do
        if not variant.new_text then
          return { success = false, error = 'Variant ' .. i .. ' missing new_text' }
        end
      end

      local result = overlay_api.single_variants(line, args.variants)
      return type(result) == 'string' and safe_json_decode(result) or { success = true }
    end
  else
    -- No variants - check if single or multiline
    if args.end_line or args.start_line or args.new_lines then
      -- Multiline without variants
      local start_line = tonumber(args.start_line)
      local end_line = tonumber(args.end_line)
      local new_lines = args.new_lines
      local reasoning = args.reasoning or ''

      if not start_line or not end_line or not new_lines then
        return { success = false, error = 'Missing required parameters: start_line, end_line, new_lines' }
      end

      -- Ensure new_lines is a table
      if type(new_lines) == 'string' then
        new_lines = { new_lines }
      elseif type(new_lines) ~= 'table' then
        return { success = false, error = 'new_lines must be an array of strings' }
      end

      local result = overlay_api.multiline(start_line, end_line, new_lines, reasoning)
      return type(result) == 'string' and safe_json_decode(result) or { success = true }
    else
      -- Single line without variants
      local line = tonumber(args.line)
      local new_text = args.new_text
      local reasoning = args.reasoning or ''

      if not line or not new_text then
        return { success = false, error = 'Missing required parameters: line, new_text' }
      end

      local result = overlay_api.single(line, new_text, reasoning)
      return type(result) == 'string' and safe_json_decode(result) or { success = true }
    end
  end
end

-- =============================================================================
-- LUAEVAL-BASED ENTRY POINT - The key to robustness!
-- =============================================================================

-- Main entry point for luaeval calls - handles both overlays and vim commands
-- Example for overlays: nvim --server :6666 --remote-expr 'luaeval("require(\"pairup.rpc\").execute(_A)", {method = "apply_overlay", args = {line = 5, new_text = "hello", reasoning = "test"}})'
-- Example for vim commands: nvim --server :6666 --remote-expr 'luaeval("require(\"pairup.rpc\").execute(_A)", {command = "w"})'
function M.execute(request)
  -- Handle direct Lua table (when called with _A from luaeval)
  if type(request) == 'table' then
    -- Check if it's a vim command request
    if request.command then
      return M.execute_command(request.command)
    end

    -- Check if it's an overlay request (has method or direct args)
    if request.method == 'apply_overlay' then
      local result = M.apply_overlay(request.args or request)
      return safe_json_encode(result)
    end

    -- Direct overlay args (no method specified)
    if request.line or request.start_line or request.variants then
      local result = M.apply_overlay(request)
      return safe_json_encode(result)
    end

    -- Route to insert methods
    if request.method == 'insert_above' then
      local result = M.insert_above(request.args or request)
      return safe_json_encode(result)
    end

    if request.method == 'insert_below' then
      local result = M.insert_below(request.args or request)
      return safe_json_encode(result)
    end

    if request.method == 'append_to_file' then
      local result = M.append_to_file(request.args or request)
      return safe_json_encode(result)
    end

    -- Route to other methods if specified
    if request.method and M[request.method] then
      local result = M.rpc_call(request.method, request.args or {})
      return safe_json_encode(result)
    end

    return safe_json_encode({ success = false, error = 'Unknown request format' })
  end

  -- Handle string command (backwards compatibility for vim commands)
  if type(request) == 'string' then
    return M.execute_command(request)
  end

  return safe_json_encode({ success = false, error = 'Invalid request type' })
end

-- =============================================================================
-- INSERT METHODS - For adding content above/below lines
-- =============================================================================

-- Insert content above a specific line
function M.insert_above(args)
  M.update_layout()

  if not state.main_buffer then
    return { success = false, error = 'No main buffer found' }
  end

  local line = tonumber(args.line)
  local content = args.content
  local reasoning = args.reasoning or 'Inserted content'

  if not line or not content then
    return { success = false, error = 'Missing required parameters: line, content' }
  end

  -- Ensure content is a table of lines
  if type(content) == 'string' then
    content = vim.split(content, '\n', { plain = true })
  elseif type(content) ~= 'table' then
    return { success = false, error = 'content must be a string or array of strings' }
  end

  -- Special case: inserting at line 1 (beginning of file)
  if line == 1 then
    -- Get current first line
    local first_line = vim.api.nvim_buf_get_lines(state.main_buffer, 0, 1, false)[1] or ''

    -- Show overlay suggestion at line 1 that includes new content + existing line
    local combined = vim.deepcopy(content)
    table.insert(combined, first_line)

    local overlay = require('pairup.overlay')
    overlay.show_multiline_suggestion(state.main_buffer, 1, 1, { first_line }, combined, reasoning)
  else
    -- Normal case: insert above line (which means at end of previous line)
    local insert_pos = line - 1

    -- Show as multiline suggestion spanning from insert_pos to insert_pos
    local overlay = require('pairup.overlay')
    local current_line = vim.api.nvim_buf_get_lines(state.main_buffer, insert_pos - 1, insert_pos, false)[1] or ''

    -- Create suggestion that keeps current line and adds new content
    local combined = { current_line }
    for _, new_line in ipairs(content) do
      table.insert(combined, new_line)
    end

    overlay.show_multiline_suggestion(state.main_buffer, insert_pos, insert_pos, { current_line }, combined, reasoning)
  end

  return { success = true }
end

-- Insert content below a specific line
function M.insert_below(args)
  M.update_layout()

  if not state.main_buffer then
    return { success = false, error = 'No main buffer found' }
  end

  local line = tonumber(args.line)
  local content = args.content
  local reasoning = args.reasoning or 'Inserted content'

  if not line or not content then
    return { success = false, error = 'Missing required parameters: line, content' }
  end

  -- Ensure content is a table of lines
  if type(content) == 'string' then
    content = vim.split(content, '\n', { plain = true })
  elseif type(content) ~= 'table' then
    return { success = false, error = 'content must be a string or array of strings' }
  end

  local line_count = vim.api.nvim_buf_line_count(state.main_buffer)

  -- Special case: inserting after last line (EOF)
  if line >= line_count then
    -- Show as multiline suggestion at end of file
    local overlay = require('pairup.overlay')
    local last_line = vim.api.nvim_buf_get_lines(state.main_buffer, line_count - 1, line_count, false)[1] or ''

    -- Create suggestion that keeps last line and adds new content
    local combined = { last_line }
    for _, new_line in ipairs(content) do
      table.insert(combined, new_line)
    end

    overlay.show_multiline_suggestion(state.main_buffer, line_count, line_count, { last_line }, combined, reasoning)
  else
    -- Normal case: insert after line
    local next_line = line + 1
    local current_line = vim.api.nvim_buf_get_lines(state.main_buffer, next_line - 1, next_line, false)[1] or ''

    -- Show overlay that adds content before the next line
    local overlay = require('pairup.overlay')
    local combined = {}
    for _, new_line in ipairs(content) do
      table.insert(combined, new_line)
    end
    table.insert(combined, current_line)

    overlay.show_multiline_suggestion(state.main_buffer, next_line, next_line, { current_line }, combined, reasoning)
  end

  return { success = true }
end

-- Append content at end of file
function M.append_to_file(args)
  M.update_layout()

  if not state.main_buffer then
    return { success = false, error = 'No main buffer found' }
  end

  local content = args.content
  local reasoning = args.reasoning or 'Appended to end of file'

  if not content then
    return { success = false, error = 'Missing required parameter: content' }
  end

  -- Ensure content is a table of lines
  if type(content) == 'string' then
    content = vim.split(content, '\n', { plain = true })
  elseif type(content) ~= 'table' then
    return { success = false, error = 'content must be a string or array of strings' }
  end

  local line_count = vim.api.nvim_buf_line_count(state.main_buffer)

  -- Use insert_below for last line
  return M.insert_below({
    line = line_count,
    content = content,
    reasoning = reasoning,
  })
end

-- =============================================================================
-- OTHER RPC METHODS (keeping compatibility)
-- =============================================================================

-- Get context information
function M.get_context()
  M.update_layout()
  return safe_json_encode({
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

-- Read main buffer content
function M.read_main_buffer(start_line, end_line)
  if not state.main_buffer then
    return safe_json_encode({ error = 'No main buffer found' })
  end

  start_line = start_line or 1
  end_line = end_line or -1

  local lines = vim.api.nvim_buf_get_lines(state.main_buffer, start_line - 1, end_line, false)
  return safe_json_encode(lines)
end

-- Execute vim command (enhanced with informative responses)
function M.execute_command(command)
  if not state.main_window then
    return safe_json_encode({ error = 'No main window found' })
  end

  local current_win = vim.api.nvim_get_current_win()
  vim.cmd(state.main_window .. 'wincmd w')
  local ok, result = pcall(vim.cmd, command)
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
    response.error = tostring(result)
  end

  return safe_json_encode(response)
end

-- Get buffer statistics
function M.get_stats()
  if not state.main_buffer then
    return safe_json_encode({ error = 'No main buffer found' })
  end

  local current_win = vim.api.nvim_get_current_win()
  vim.cmd(state.main_window .. 'wincmd w')
  local wc = vim.fn.wordcount()
  vim.api.nvim_set_current_win(current_win)

  return safe_json_encode({
    lines = vim.api.nvim_buf_line_count(state.main_buffer),
    words = wc.words,
    chars = wc.chars,
    bytes = wc.bytes,
  })
end

-- Set/get registers
function M.set_register(reg, content)
  vim.fn.setreg(reg, content)
  return safe_json_encode({ success = true })
end

function M.get_register(reg)
  return safe_json_encode({ content = vim.fn.getreg(reg) })
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

  return safe_json_encode(caps)
end

-- Accept overlay at line
function M.overlay_accept(line)
  M.update_layout()
  if not state.main_buffer then
    return safe_json_encode({ error = 'No main buffer found' })
  end

  local overlay = require('pairup.overlay')
  overlay.apply_at_line(state.main_buffer, line)
  return safe_json_encode({ success = true, line = line, message = 'Overlay accepted' })
end

-- Reject overlay at line
function M.overlay_reject(line)
  M.update_layout()
  if not state.main_buffer then
    return safe_json_encode({ error = 'No main buffer found' })
  end

  local overlay = require('pairup.overlay')
  overlay.reject_at_line(state.main_buffer, line)
  return safe_json_encode({ success = true, line = line, message = 'Overlay rejected' })
end

-- List all overlays
function M.overlay_list()
  M.update_layout()
  if not state.main_buffer then
    return safe_json_encode({ error = 'No main buffer found', overlays = {}, count = 0 })
  end

  local overlay = require('pairup.overlay')
  local suggestions = overlay.get_suggestions(state.main_buffer)
  local list = {}

  for line_num, suggestion in pairs(suggestions) do
    local entry = {
      line = line_num,
      reasoning = suggestion.reasoning,
    }

    -- Handle both single-line and multiline overlays
    if suggestion.is_multiline then
      entry.is_multiline = true
      entry.start_line = suggestion.start_line
      entry.end_line = suggestion.end_line
      entry.old_lines = suggestion.old_lines
      entry.new_lines = suggestion.new_lines
    else
      entry.old_text = suggestion.old_text
      entry.new_text = suggestion.new_text
    end

    table.insert(list, entry)
  end

  -- Sort by line number
  table.sort(list, function(a, b)
    return a.line < b.line
  end)

  return safe_json_encode({
    success = true,
    overlays = list,
    count = #list,
  })
end

-- Get RPC instructions for Claude
function M.get_instructions()
  if not state.enabled then
    return nil
  end

  -- Check if experimental RPC instructions are enabled
  local config = require('pairup.config')
  if not config.get('experimental.inject_rpc_instructions') then
    return nil -- Don't inject instructions if feature is disabled
  end

  -- Get the actual server name from config or use what's running
  local configured_server = config.get('rpc_port') or '127.0.0.1:6666'
  local servername = vim.v.servername or configured_server

  -- Load the instructions markdown file
  local instructions_path = vim.fn.fnamemodify(debug.getinfo(1).source:sub(2), ':h') .. '/claude_instructions.md'
  local instructions_file = io.open(instructions_path, 'r')
  local instructions_content = ''

  if instructions_file then
    instructions_content = instructions_file:read('*all')
    instructions_file:close()
  else
    -- Fallback if file can't be read
    instructions_content = [[
# Claude RPC Instructions

You can interact with Neovim through RPC commands using the luaeval approach with _A parameter.
See the claude_instructions.md file for full documentation.
]]
  end

  -- Replace the placeholder with the actual server address
  -- The pattern will match lines like:
  -- nvim --server :6666 --remote-expr 'luaeval("require(\"pairup.rpc\").execute(_A)", TABLE)'
  instructions_content = instructions_content:gsub(':6666', servername)

  -- Add a header with the actual server address for clarity
  local header = string.format(
    [[
# RPC CONTROL AVAILABLE

Use this command pattern with server %s:
```bash
nvim --server %s --remote-expr "any command below"
```

]],
    servername,
    servername
  )

  return header .. instructions_content
end

-- Check if enabled
function M.is_enabled()
  return state.enabled
end

return M
