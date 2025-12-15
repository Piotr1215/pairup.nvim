-- Configuration module for pairup.nvim
local M = {}

-- Default configuration
local defaults = {
  -- AI provider
  provider = 'claude',

  -- Provider configurations
  providers = {
    claude = {
      -- Full command with flags
      cmd = (vim.fn.exepath('claude') or 'claude') .. ' --permission-mode acceptEdits',
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
    auto_insert = false, -- Enter insert mode when opening terminal
    auto_scroll = true,
  },

  -- Auto-refresh settings (for detecting Claude's file edits)
  auto_refresh = {
    enabled = true,
    interval_ms = 500,
  },

  -- Flash highlight settings
  flash = {
    scroll_to_changes = false, -- Auto-scroll to first changed line
  },

  -- Inline editing (cc:/uu: markers)
  inline = {
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

  -- Progress indicator (optional, disabled by default)
  -- When enabled, user must grant Claude write access: --add-dir /tmp
  progress = {
    enabled = false,
    file = '/tmp/claude_progress',
  },
}

-- Current configuration
M.values = {}

-- Setup function
function M.setup(opts)
  opts = opts or {}

  -- Type validation with vim.validate
  if opts.provider then
    vim.validate({ provider = { opts.provider, 'string' } })
  end
  if opts.terminal then
    vim.validate({
      ['terminal.split_position'] = { opts.terminal.split_position, 'string', true },
      ['terminal.split_width'] = { opts.terminal.split_width, 'number', true },
      ['terminal.auto_insert'] = { opts.terminal.auto_insert, 'boolean', true },
      ['terminal.auto_scroll'] = { opts.terminal.auto_scroll, 'boolean', true },
    })
  end
  if opts.progress then
    vim.validate({
      ['progress.enabled'] = { opts.progress.enabled, 'boolean', true },
      ['progress.file'] = { opts.progress.file, 'string', true },
    })
  end
  if opts.flash then
    vim.validate({
      ['flash.scroll_to_changes'] = { opts.flash.scroll_to_changes, 'boolean', true },
    })
  end

  M.values = vim.tbl_deep_extend('force', defaults, opts)
  M.validate_values()
end

-- Validate configuration values (semantic validation)
function M.validate_values()
  local provider = M.values.provider
  local provider_config = M.values.providers[provider]

  if not provider_config then
    vim.notify(string.format("Unknown provider '%s'. Using 'claude' as default.", provider), vim.log.levels.WARN)
    M.values.provider = 'claude'
  end

  -- Validate terminal split width (must be between 0 and 1 exclusive)
  local width = M.values.terminal.split_width
  if type(width) ~= 'number' or width <= 0 or width >= 1 then
    M.values.terminal.split_width = 0.4
    vim.notify('Invalid terminal split_width (must be 0 < width < 1). Using default 0.4', vim.log.levels.WARN)
  end

  -- Validate split_position
  local pos = M.values.terminal.split_position
  if pos ~= 'left' and pos ~= 'right' then
    M.values.terminal.split_position = 'left'
    vim.notify("Invalid terminal split_position (must be 'left' or 'right'). Using default 'left'", vim.log.levels.WARN)
  end
end

-- Legacy alias
M.validate = M.validate_values

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
