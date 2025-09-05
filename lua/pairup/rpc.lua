local M = {}

-- RPC state tracking
local state = {
  enabled = false,
  terminal_window = nil,
  main_window = nil,
  main_buffer = nil,
  rpc_port = "127.0.0.1:6666"
}

-- Check if RPC server is available
function M.check_rpc_available()
  -- The servername doesn't show TCP listen address, so we need a different approach
  -- Check if we can get the list of channels and see if any are listening on TCP
  local channels = vim.api.nvim_list_chans()
  
  for _, chan in ipairs(channels) do
    -- Check if this channel is a TCP server listening on our port
    if chan.stream == "tcp" and chan.mode == "rpc" and chan.server then
      local addr = chan.addr or ""
      if addr:match("6666") then
        return true
      end
    end
  end
  
  -- Alternative: Just check if servername exists (meaning --listen was used)
  -- and assume user used the right port
  local servername = vim.v.servername or ""
  return servername ~= ""
end

-- Initialize RPC support when pairup starts
function M.setup()
  
  -- Auto-detect RPC on startup
  if M.check_rpc_available() then
    state.enabled = true
    
    -- Track window layout
    M.update_layout()
    
    -- Set up auto-tracking
    vim.api.nvim_create_autocmd({"WinEnter", "BufEnter"}, {
      group = vim.api.nvim_create_augroup("PairupRPC", { clear = true }),
      callback = function()
        M.update_layout()
      end
    })
  end
end

-- Update layout tracking
function M.update_layout()
  if not state.enabled then return end
  
  -- Find terminal buffer (pairup assistant)
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.b[buf].is_pairup_assistant then
      state.terminal_window = vim.api.nvim_win_get_number(win)
    else
      -- Track the main editing window
      local bufname = vim.api.nvim_buf_get_name(buf)
      if bufname ~= "" and not bufname:match("^term://") then
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
    windows = M.get_window_info()
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
      type = bufname:match("^term://") and "terminal" or "file",
      is_pairup = vim.b[buf].is_pairup_assistant or false
    })
  end
  return windows
end

-- Read the main file buffer (not the terminal!)
function M.read_main_buffer(start_line, end_line)
  if not state.main_buffer then
    return vim.json.encode({ error = "No main buffer found" })
  end
  
  start_line = start_line or 1
  end_line = end_line or -1
  
  local lines = vim.api.nvim_buf_get_lines(state.main_buffer, start_line - 1, end_line, false)
  return vim.json.encode(lines)
end

-- Execute command in main window (not terminal!)
function M.execute_in_main(command)
  if not state.main_window then
    return vim.json.encode({ error = "No main window found" })
  end
  
  -- Save current window
  local current_win = vim.api.nvim_get_current_win()
  
  -- Execute in main window
  vim.cmd(state.main_window .. "wincmd w")
  local ok, result = pcall(vim.cmd, command)
  
  -- Restore window
  vim.api.nvim_set_current_win(current_win)
  
  return vim.json.encode({ 
    success = ok, 
    result = result,
    executed_in_window = state.main_window
  })
end

-- Search in main buffer
function M.search(pattern, flags)
  if not state.main_buffer then
    return vim.json.encode({ error = "No main buffer found" })
  end
  
  flags = flags or ""
  local lines = vim.api.nvim_buf_get_lines(state.main_buffer, 0, -1, false)
  local matches = {}
  
  for i, line in ipairs(lines) do
    if vim.fn.match(line, pattern) >= 0 then
      table.insert(matches, { line = i, text = line })
    end
  end
  
  return vim.json.encode(matches)
end

-- Replace in main buffer  
function M.replace(pattern, replacement, flags)
  if not state.main_window then
    return vim.json.encode({ error = "No main window found" })
  end
  
  flags = flags or "g"
  local cmd = string.format("%%s/%s/%s/%s", pattern, replacement, flags)
  return M.execute_in_main(cmd)
end

-- Save main buffer
function M.save()
  if not state.main_window then
    return vim.json.encode({ error = "No main window found" })
  end
  
  return M.execute_in_main("w")
end

-- Jump to line in main buffer
function M.goto_line(line)
  if not state.main_window then
    return vim.json.encode({ error = "No main window found" })
  end
  
  return M.execute_in_main(tostring(line))
end

-- Get buffer statistics
function M.get_stats()
  if not state.main_buffer then
    return vim.json.encode({ error = "No main buffer found" })
  end
  
  -- Switch to main window for wordcount
  local current_win = vim.api.nvim_get_current_win()
  vim.cmd(state.main_window .. "wincmd w")
  local wc = vim.fn.wordcount()
  vim.api.nvim_set_current_win(current_win)
  
  return vim.json.encode({
    lines = vim.api.nvim_buf_line_count(state.main_buffer),
    words = wc.words,
    chars = wc.chars,
    bytes = wc.bytes
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
  
  return [[

========================================
NEOVIM REMOTE CONTROL ENABLED! 🚀
========================================

You have direct control over the Neovim instance via RPC.

CRITICAL CONTEXT:
• You're in a terminal buffer (for displaying output)
• The actual file is in another window
• Use RPC to control the REAL editor, not this terminal

AVAILABLE COMMANDS (use with: nvim --server /tmp/nvim --remote-expr):

Get Context & Layout:
• 'luaeval("require(\'pairup.rpc\').get_context()")'
  Returns: terminal_window, main_window, main_file, modified status

File Operations:
• 'luaeval("require(\'pairup.rpc\').read_main_buffer()")'        -- Read file content
• 'luaeval("require(\'pairup.rpc\').read_main_buffer(1, 50)")'   -- Read lines 1-50
• 'luaeval("require(\'pairup.rpc\').save()")'                    -- Save file
• 'luaeval("require(\'pairup.rpc\').get_stats()")'               -- Get word/line counts

Editing:
• 'luaeval("require(\'pairup.rpc\').search(\'pattern\')")'         -- Search in file
• 'luaeval("require(\'pairup.rpc\').replace(\'old\', \'new\', \'g\')")'-- Replace text
• 'luaeval("require(\'pairup.rpc\').goto_line(42)")'             -- Jump to line
• 'luaeval("require(\'pairup.rpc\').execute_in_main(\'cmd\')")'    -- Run vim command

Registers:
• 'luaeval("require(\'pairup.rpc\').set_register(\'a\', \'text\')")' -- Set register
• 'luaeval("require(\'pairup.rpc\').get_register(\'a\')")'         -- Get register

Discovery:
• 'luaeval("require(\'pairup.rpc\').get_capabilities()")'  -- Get all plugins, commands, LSP clients, keymaps!

GOLDEN RULE: Always call get_context() first to understand the layout!
PRO TIP: Call get_capabilities() to discover all available features!

IMPORTANT INSTRUCTIONS FOR CLAUDE:
1. Start every session by calling get_capabilities() to discover available tools
2. Use discovered commands to leverage the user's existing plugins:
   - Use :Telescope commands for searching instead of basic grep
   - Use :LSP commands for code intelligence
   - Use :Git/Gitsigns commands for version control
   - Use :GoTest, :GoRun etc for Go development
   - Use existing formatters and linters
3. Prefer using Neovim's superior editing capabilities over your own text manipulation
4. When you need to edit files, use these RPC commands - they're far more powerful and reliable!
5. Always check what plugins are available before suggesting installations
6. Leverage the user's keymaps and workflow instead of generic suggestions

========================================
]]
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
    keymaps = {}
  }
  
  -- Get plugins if lazy.nvim is available
  local ok, lazy = pcall(require, "lazy.core.config")
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
    if map.lhs:match("^<leader>") then
      table.insert(caps.keymaps, {
        lhs = map.lhs,
        rhs = map.rhs or map.callback and "[Lua function]" or "",
        desc = map.desc
      })
    end
  end
  
  return vim.json.encode(caps)
end

return M