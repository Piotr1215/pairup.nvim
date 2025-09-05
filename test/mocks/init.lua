local M = {}

-- Complete mock setup for testing without real Claude CLI
function M.setup()
  -- Always in test mode
  vim.g.pairup_test_mode = true
  vim.o.updatetime = 10 -- Fast updates for tests

  -- Clear all pairup modules
  for k, _ in pairs(package.loaded) do
    if k:match('^pairup') then
      package.loaded[k] = nil
    end
  end

  -- Mock terminal creation
  local mock_terminal_buf = nil

  -- Store original functions
  M.original_cmd = vim.cmd
  M.original_fn = vim.fn
  M.original_wait = vim.wait
  M.original_defer = vim.defer_fn

  -- Mock vim.defer_fn to execute immediately in tests
  vim.defer_fn = function(fn, timeout)
    if timeout and timeout > 1000 then
      -- Don't wait for long timeouts in tests
      return
    end
    fn()
  end

  -- Mock vim.wait to not actually wait in tests
  vim.wait = function(_, callback)
    if callback then
      return callback()
    end
    return true
  end

  -- Mock vim.cmd for terminal commands
  local original_cmd = M.original_cmd
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.cmd = function(cmd_str)
    if type(cmd_str) == 'string' and cmd_str:match('term://') then
      -- Create mock terminal buffer
      if not mock_terminal_buf or not vim.api.nvim_buf_is_valid(mock_terminal_buf) then
        mock_terminal_buf = vim.api.nvim_create_buf(false, true)
        vim.b[mock_terminal_buf].is_pairup_assistant = true
        vim.b[mock_terminal_buf].provider = 'claude'
        vim.b[mock_terminal_buf].terminal_job_id = 999
      end
      vim.api.nvim_set_current_buf(mock_terminal_buf)
      return
    end
    if type(cmd_str) == 'string' and cmd_str:match('^%s*wincmd') then
      return -- Ignore window commands in tests
    end
    if type(cmd_str) == 'string' and cmd_str:match('^%s*startinsert') then
      return -- Ignore insert mode in tests
    end
    if type(cmd_str) == 'string' and cmd_str:match('^%s*stopinsert') then
      return -- Ignore insert mode in tests
    end
    if type(cmd_str) == 'string' and cmd_str:match('^%s*checktime') then
      return -- Ignore file reload in tests
    end
    return original_cmd(cmd_str)
  end

  -- Mock vim.fn functions
  local original_fn = vim.fn
  vim.fn = setmetatable({
    exepath = function(cmd)
      if cmd == 'claude' then
        return '/mock/claude'
      end
      return ''
    end,
    system = function(cmd)
      if cmd:match('uuidgen') then
        return 'test-uuid-' .. math.random(1000, 9999) .. '\n'
      elseif cmd:match('git rev%-parse') then
        return '' -- Not in git repo
      end
      return ''
    end,
    systemlist = function(cmd)
      if cmd:match('git rev%-parse') then
        return {} -- Not in git repo
      end
      return {}
    end,
    shellescape = function(s)
      return "'" .. s .. "'"
    end,
    executable = function(cmd)
      if cmd == '/mock/claude' or cmd == 'claude' then
        return 1
      end
      return 0
    end,
    isdirectory = function(_)
      -- Mock directories as existing
      return 1
    end,
    filereadable = function(_)
      -- Mock files as not existing for session tests
      return 0
    end,
    glob = function()
      return {}
    end,
    jobstart = function()
      return 999
    end,
    jobstop = function()
      return 1
    end,
    chansend = function()
      return 1
    end,
    mkdir = function()
      return 1
    end,
  }, {
    __index = original_fn,
  })

  return mock_terminal_buf
end

-- Cleanup function
function M.cleanup()
  -- Restore original functions
  if M.original_cmd then
    vim.cmd = M.original_cmd
  end
  if M.original_fn then
    vim.fn = M.original_fn
  end
  if M.original_wait then
    vim.wait = M.original_wait
  end
  if M.original_defer then
    vim.defer_fn = M.original_defer
  end

  -- Clean up any test buffers
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.b[buf] and vim.b[buf].is_pairup_assistant then
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
  end

  -- Reset vim.g test vars
  vim.g.pairup_test_mode = nil
  vim.g.pairup_current_session_id = nil
  vim.g.pairup_current_intent = nil
  vim.g.pairup_session_files = nil
end

return M
