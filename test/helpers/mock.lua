-- Mock helpers for tests
local M = {}

-- Mock Claude CLI for testing
M.mock_claude_cli = function()
  -- Store original functions
  local original_exepath = vim.fn.exepath
  local original_system = vim.fn.system

  -- Mock exepath to return mock-claude
  vim.fn.exepath = function(cmd)
    if cmd == 'claude' then
      return '/usr/bin/mock-claude'
    end
    return original_exepath(cmd)
  end

  -- Return cleanup function
  return function()
    vim.fn.exepath = original_exepath
    vim.fn.system = original_system
  end
end

-- Mock terminal for testing
M.mock_terminal = function()
  local mock_buf = vim.api.nvim_create_buf(false, true)
  local mock_job_id = 12345

  -- Store original functions
  local original_cmd = vim.cmd
  local original_termopen = vim.fn.termopen

  -- Mock vim.cmd to handle terminal creation
  vim.cmd = function(cmd_str)
    if cmd_str:match('vsplit term://') then
      -- Simulate terminal buffer creation
      vim.api.nvim_set_current_buf(mock_buf)
      vim.b[mock_buf].terminal_job_id = mock_job_id
      return
    end
    return original_cmd(cmd_str)
  end

  -- Mock termopen
  vim.fn.termopen = function()
    return mock_job_id
  end

  -- Return cleanup function
  return function()
    vim.cmd = original_cmd
    vim.fn.termopen = original_termopen
    if vim.api.nvim_buf_is_valid(mock_buf) then
      vim.api.nvim_buf_delete(mock_buf, { force = true })
    end
  end
end

-- Mock chansend for testing terminal communication
M.mock_chansend = function()
  local sent_messages = {}

  local original_chansend = vim.fn.chansend

  vim.fn.chansend = function(job_id, data)
    table.insert(sent_messages, { job_id = job_id, data = data })
    return 1
  end

  -- Return messages getter and cleanup function
  return sent_messages, function()
    vim.fn.chansend = original_chansend
  end
end

return M
