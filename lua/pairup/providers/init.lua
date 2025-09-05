-- Provider abstraction layer for pairup.nvim
-- Manages different AI providers (Claude, OpenAI, Ollama, etc.)

local M = {}
local config = require('pairup.config')

-- Available providers
M.providers = {}

-- Current active provider instance
M.current = nil

-- Register a provider
function M.register(name, provider)
  M.providers[name] = provider
end

-- Initialize providers
function M.setup()
  -- Register Claude provider
  local claude = require('pairup.providers.claude')
  M.register('claude', claude)

  -- Future providers will be registered here
  -- M.register('openai', require('pairup.providers.openai'))
  -- M.register('ollama', require('pairup.providers.ollama'))
end

-- Get provider by name
function M.get(name)
  name = name or config.get_provider()
  return M.providers[name]
end

-- Start AI assistant with configured provider
function M.start(intent_mode, session_id)
  local provider_name = config.get_provider()
  local provider = M.get(provider_name)

  if not provider then
    vim.notify(string.format("Provider '%s' not found", provider_name), vim.log.levels.ERROR)
    return false
  end

  M.current = provider
  return provider.start(intent_mode, session_id)
end

-- Start AI assistant with resume flag (Claude-specific)
function M.start_with_resume()
  local provider_name = config.get_provider()
  local provider = M.get(provider_name)

  if not provider then
    vim.notify(string.format("Provider '%s' not found", provider_name), vim.log.levels.ERROR)
    return false
  end

  -- Check if provider supports resume
  if not provider.start_with_resume then
    vim.notify(string.format("Provider '%s' does not support resume", provider_name), vim.log.levels.WARN)
    return false
  end

  M.current = provider
  return provider.start_with_resume()
end

-- Toggle AI assistant window
function M.toggle(intent_mode, session_id)
  if M.current then
    return M.current.toggle(intent_mode, session_id)
  else
    return M.start(intent_mode, session_id)
  end
end

-- Stop AI assistant
function M.stop()
  if M.current then
    M.current.stop()
    M.current = nil
  else
    vim.notify('No AI assistant is running', vim.log.levels.INFO)
  end
end

-- Send message to current provider
function M.send_message(message)
  if M.current then
    M.current.send_message(message)
  else
    vim.notify('No AI assistant is running. Use :PairupStart to begin.', vim.log.levels.WARN)
  end
end

-- Send to provider (internal use)
function M.send_to_provider(message)
  if M.current and M.current.send_to_terminal then
    return M.current.send_to_terminal(message)
  end
  return false
end

-- Find current provider terminal
function M.find_terminal()
  if M.current and M.current.find_terminal then
    return M.current.find_terminal()
  end
  return nil, nil, nil
end

return M
