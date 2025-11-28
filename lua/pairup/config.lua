-- Configuration module for pairup.nvim
local M = {}

-- Default configuration
local defaults = {
  -- AI provider
  provider = 'claude',

  -- Provider configurations
  providers = {
    claude = {
      path = vim.fn.exepath('claude') or 'claude',
    },
  },

  -- Git integration
  git = {
    enabled = true,
    diff_context_lines = 10,
  },

  -- Terminal settings
  terminal = {
    split_position = 'left',
    split_width = 0.4, -- 40% for AI, 60% for editor
    auto_insert = true,
    auto_scroll = true,
  },

  -- Auto-refresh settings (for detecting Claude's file edits)
  auto_refresh = {
    enabled = true,
    interval_ms = 500,
  },

  -- Inline editing (cc:/uu: markers)
  inline = {
    enabled = true,
    markers = {
      command = 'cc:', -- User command marker
      question = 'uu:', -- Claude question marker
    },
    quickfix = true, -- Show uu: questions in quickfix
  },

  -- Statusline integration
  statusline = {
    auto_inject = true, -- Auto-inject into lualine if available
  },
}

-- Current configuration
M.values = {}

-- Setup function
function M.setup(opts)
  opts = opts or {}
  M.values = vim.tbl_deep_extend('force', defaults, opts)
  M.validate()
end

-- Validate configuration
function M.validate()
  local provider = M.values.provider
  local provider_config = M.values.providers[provider]

  if not provider_config then
    vim.notify(string.format("Unknown provider '%s'. Using 'claude' as default.", provider), vim.log.levels.WARN)
    M.values.provider = 'claude'
  end

  -- Validate terminal split width
  if M.values.terminal.split_width <= 0 or M.values.terminal.split_width >= 1 then
    M.values.terminal.split_width = 0.4
    vim.notify('Invalid terminal split_width. Using default 0.4', vim.log.levels.WARN)
  end
end

-- Get a config value
function M.get(key)
  local keys = vim.split(key, '.', { plain = true })
  local value = M.values

  for _, k in ipairs(keys) do
    value = value[k]
    if value == nil then
      return nil
    end
  end

  return value
end

-- Set a config value
function M.set(key, val)
  local keys = vim.split(key, '.', { plain = true })
  local config = M.values

  for i = 1, #keys - 1 do
    local k = keys[i]
    config[k] = config[k] or {}
    config = config[k]
  end

  config[keys[#keys]] = val
end

-- Get current provider
function M.get_provider()
  return M.values.provider
end

-- Get provider config
function M.get_provider_config(provider)
  provider = provider or M.values.provider
  return M.values.providers[provider]
end

return M
