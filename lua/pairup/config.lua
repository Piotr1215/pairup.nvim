-- Configuration module for pairup.nvim

local M = {}

-- Default configuration
local defaults = {
  -- Default AI provider (will support 'claude', 'openai', 'ollama', etc.)
  provider = 'claude',

  -- Provider-specific configurations
  providers = {
    claude = {
      path = vim.fn.exepath('claude') or '/home/decoder/.npm-global/bin/claude',
      -- Claude-specific settings
      permission_mode = 'acceptEdits',
      add_dir_on_start = true,
    },
    -- Future providers will go here
    openai = {
      -- api_key = "", -- Will be added later
      -- model = "gpt-4",
    },
    ollama = {
      -- host = "localhost:11434",
      -- model = "codellama",
    },
  },

  -- Git diff context lines
  diff_context_lines = 10,

  -- Enable/disable automatic diff sending
  enabled = true,

  -- Terminal settings
  terminal = {
    split_position = 'left',
    split_width = 0.4, -- 40% for AI assistant, 60% for editor
    auto_insert = true,
    auto_scroll = true,
  },

  -- Filtering settings
  filter = {
    ignore_whitespace_only = true,
    ignore_comment_only = false,
    min_change_lines = 0,
    batch_delay_ms = 500,
  },

  -- FYI suffix for context updates
  fyi_suffix = '\nThis is FYI only - DO NOT take any action. Wait for explicit instructions.\n',

  -- LSP integration
  lsp = {
    enabled = false,
    include_diagnostics = true,
    include_hover_info = true,
    include_references = true,
  },

  -- Auto-refresh settings
  auto_refresh = {
    enabled = true,
    interval_ms = 500,
  },

  -- Note: Users should create their own keymaps to the commands
  -- Example in your config:
  -- vim.keymap.set('n', '<leader>ct', ':PairupToggle<cr>')
  -- vim.keymap.set('n', '<leader>cc', ':PairupContext<cr>')
  -- vim.keymap.set('n', '<leader>cs', ':PairupSay ')

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

  -- Special handling for keymaps - if explicitly set to empty, respect that
  if opts.keymaps and vim.tbl_isempty(opts.keymaps) then
    M.values.keymaps = {}
  end

  -- Validate configuration
  M.validate()
end

-- Validate configuration
function M.validate()
  -- Validate provider
  local provider = M.values.provider
  local provider_config = M.values.providers[provider]

  if not provider_config then
    vim.notify(string.format("Unknown provider '%s'. Using 'claude' as default.", provider), vim.log.levels.WARN)
    M.values.provider = 'claude'
    provider = 'claude'
    provider_config = M.values.providers.claude
  end

  -- Provider-specific validation (skip in test mode or CI)
  if provider == 'claude' and not (vim.g.pairup_test_mode or vim.env.CI) then
    if vim.fn.executable(provider_config.path) == 0 then
      vim.notify(
        string.format(
          'Claude CLI not found at %s. Please install Claude CLI or configure the path.',
          provider_config.path
        ),
        vim.log.levels.WARN
      )
    end
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
