-- Configuration module for pairup.nvim
local M = {}

-- Default configuration (CLEAN AND SIMPLE!)
local defaults = {
  -- AI provider
  provider = 'claude',

  -- Provider configurations
  providers = {
    claude = {
      path = vim.fn.exepath('claude') or '/home/decoder/.npm-global/bin/claude',
      permission_mode = 'plan', -- Start in plan mode by default
      add_dir_on_start = true,
    },
  },

  -- Session management
  sessions = {
    persist = true,
    auto_populate_intent = true,
    intent_template = "This is just an intent declaration. I'm planning to work on the file `%s` to...",
  },

  -- Git integration
  git = {
    enabled = true,
    diff_context_lines = 10,
    fyi_suffix = '\nYou have received a git diff, it is your turn now to be active it our pair programming session. Take over and suggest improvements\n',
  },

  -- Terminal settings
  terminal = {
    split_position = 'left',
    split_width = 0.4, -- 40% for AI, 60% for editor
    auto_insert = true,
    auto_scroll = true,
  },

  -- RPC settings (only active when nvim --listen is used)
  rpc = {
    port = '127.0.0.1:6666',
    inject_instructions = false, -- Only inject when RPC is actually active
    instructions_path = nil, -- Optional custom path
  },

  -- Overlay settings (marker-based suggestions)
  overlay = {
    inject_instructions = true, -- Send marker instructions to Claude
    instructions_path = nil, -- Optional custom path
    persistence = {
      enabled = true,
      auto_save = true,
      auto_restore = true,
      max_sessions = 10,
    },
  },

  -- Filtering settings
  filter = {
    ignore_whitespace_only = true,
    min_change_lines = 0,
    batch_delay_ms = 500,
  },

  -- Auto-refresh settings
  auto_refresh = {
    enabled = true,
    interval_ms = 500,
  },

  -- Periodic updates
  periodic_updates = {
    enabled = false,
    interval_minutes = 10,
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
