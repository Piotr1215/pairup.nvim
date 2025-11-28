-- Provider abstraction layer for pairup.nvim

local M = {}
local config = require('pairup.config')

M.providers = {}
M.current = nil

function M.register(name, provider)
  M.providers[name] = provider
end

function M.setup()
  local claude = require('pairup.providers.claude')
  M.register('claude', claude)
end

function M.get(name)
  name = name or config.get_provider()
  return M.providers[name]
end

function M.start()
  local provider_name = config.get_provider()
  local provider = M.get(provider_name)

  if not provider then
    return false
  end

  M.current = provider
  return provider.start()
end

function M.toggle()
  if M.current then
    return M.current.toggle()
  end
  -- No current provider - try to start one
  local success = M.start()
  if success then
    -- After successful start, toggle to show the terminal
    return M.current and M.current.toggle()
  end
  return false
end

function M.stop()
  if M.current then
    M.current.stop()
    M.current = nil
  end
end

function M.send_message(message)
  if M.current then
    M.current.send_message(message)
  end
end

function M.send_to_provider(message)
  if M.current and M.current.send_to_terminal then
    return M.current.send_to_terminal(message)
  end
  return false
end

-- Fast check if any provider is running (for hot paths)
function M.is_running()
  -- Check cache directly - O(1)
  local cached_buf = vim.g.pairup_terminal_buf
  return cached_buf and vim.api.nvim_buf_is_valid(cached_buf)
end

function M.find_terminal()
  if M.current and M.current.find_terminal then
    return M.current.find_terminal()
  end

  local provider_name = config.get_provider()
  local provider = M.providers[provider_name]
  if provider and provider.find_terminal then
    local buf, win, job_id = provider.find_terminal()
    if buf then
      M.current = provider
      return buf, win, job_id
    end
  end

  return nil, nil, nil
end

return M
