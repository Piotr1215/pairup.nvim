local M = {}

-- Helper to create a temporary buffer
function M.create_temp_buffer(content)
  local buf = vim.api.nvim_create_buf(false, true)
  if content then
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(content, '\n'))
  end
  return buf
end

-- Helper to create a test file
function M.create_test_file(path, content)
  local file = io.open(path, 'w')
  if file then
    file:write(content or '')
    file:close()
    return true
  end
  return false
end

-- Helper to clean up test files
function M.cleanup_test_file(path)
  os.remove(path)
end

-- Helper to wait for async operations
function M.wait_for(condition, timeout)
  timeout = timeout or 1000
  local start = vim.loop.now()

  while not condition() do
    if vim.loop.now() - start > timeout then
      return false
    end
    vim.wait(10)
  end

  return true
end

-- Mock terminal buffer
function M.mock_terminal_buffer()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.b[buf].is_pairup_assistant = true
  vim.b[buf].provider = 'claude'
  vim.b[buf].terminal_job_id = 999
  return buf
end

return M
