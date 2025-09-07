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

  return string.format(
    [[

========================================
NEOVIM REMOTE CONTROL ENABLED! 
========================================

You have direct control over the Neovim instance via RPC.

CRITICAL CONTEXT:
• You're in a terminal buffer (for displaying output)
• The actual file is in another window
• Use RPC to control the REAL editor, not this terminal

AVAILABLE COMMANDS (use with: nvim --server %s --remote-expr):

THE MAIN COMMAND - Just use execute() for EVERYTHING:
• 'luaeval("require(\'pairup.rpc\').execute(\'w\')")'              -- Save file
• 'luaeval("require(\'pairup.rpc\').execute(\'42\')")'             -- Go to line 42  
• 'luaeval("require(\'pairup.rpc\').execute(\'%%%%s/old/new/g\')")'    -- Replace text  
• 'luaeval("require(\'pairup.rpc\').substitute(\'old\', \'new\', \'g\')")'  -- Use substitute() helper for safety
• 'luaeval("require(\'pairup.rpc\').execute(\'/pattern\')")'       -- Search
• 'luaeval("require(\'pairup.rpc\').execute(\'normal gg\')")'      -- Go to top
• 'luaeval("require(\'pairup.rpc\').execute(\'Telescope find_files\')")' -- Run any command!

Context & Discovery:
• 'luaeval("require(\'pairup.rpc\').get_context()")'          -- Get window layout
• 'luaeval("require(\'pairup.rpc\').get_capabilities()")'     -- Discover all plugins/commands
• 'luaeval("require(\'pairup.rpc\').read_main_buffer()")'     -- Read file content
• 'luaeval("require(\'pairup.rpc\').get_stats()")'            -- Get word/line counts

HELP DISCOVERY - Learn Neovim features on your own!
• 'luaeval("require(\'pairup.rpc\').execute(\'helpgrep telescope\')")'    -- Search ALL help files for a topic
• 'luaeval("require(\'pairup.rpc\').execute(\'copen\')")'                 -- View helpgrep results in quickfix
• 'luaeval("vim.inspect(vim.fn.getqflist())")'                          -- Get quickfix list contents
• 'luaeval("require(\'pairup.rpc\').execute(\'cfirst\')")'               -- Jump to first help match
• 'luaeval("require(\'pairup.rpc\').execute(\'help telescope.nvim\')")'  -- Direct help for specific topic
• 'luaeval("require(\'pairup.rpc\').execute(\'Telescope help_tags\')")'  -- Interactive help browser
• 'luaeval("require(\'pairup.rpc\').execute(\'helptags ALL\')")'         -- Regenerate all help tags
Pro tip: When you don't know how to do something, search the help first!
Example: execute('helpgrep sort') to learn about sorting in Vim

GOLDEN RULE: Always call get_context() first to understand the layout!

IMPORTANT INSTRUCTIONS FOR CLAUDE:
1. **USE execute() FOR EVERYTHING** - it runs ANY Vim command exactly as typed:
   - execute('w') to save
   - execute('42') to go to line 42
   - execute('%%s/old/new/g') for replace
   - execute('/search_term') to search
   - execute('Telescope find_files') to use plugins
   - execute('normal dd') to delete a line
   - Literally ANY ex command or normal mode command works!
2. **ESCAPING TIPS**:
   - For simple patterns: use execute('%%s/old/new/g')
   - For patterns with quotes: use substitute('old', 'new', 'g') helper
   - For tabs: use execute('%%s/\\t/  /g') with proper escaping
   - Helper functions: substitute() avoids most escaping issues
3. Use discovered plugin commands instead of reinventing:
   - execute('Telescope live_grep') instead of basic search
   - execute('Gitsigns blame_line') for git info
   - execute('LSPHover') for code intelligence

========================================
]],
    servername
  )
end

-- Check if RPC is enabled
function M.is_enabled()
  return state.enabled
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
  for _, client in pairs(vim.lsp.get_active_clients()) do
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

return M
