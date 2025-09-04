-- Health check for pairup.nvim

local M = {}

function M.check()
  vim.health.start('pairup.nvim')

  -- Check Neovim version
  local nvim_version = vim.version()
  if nvim_version.major >= 0 and nvim_version.minor >= 8 then
    vim.health.ok(string.format('Neovim version %s.%s.%s', nvim_version.major, nvim_version.minor, nvim_version.patch))
  else
    vim.health.error('Neovim 0.8+ required', {
      'Please upgrade Neovim to version 0.8 or higher',
    })
  end

  -- Check git
  if vim.fn.executable('git') == 1 then
    local git_version = vim.fn.system('git --version'):gsub('\n', '')
    vim.health.ok('Git: ' .. git_version)
  else
    vim.health.error('Git not found', {
      'Git is required for diff functionality',
      'Install git from https://git-scm.com/',
    })
  end

  -- Check for notify-send (optional)
  if vim.fn.executable('notify-send') == 1 then
    vim.health.ok('notify-send found (system notifications available)')
  else
    vim.health.info('notify-send not found (optional)', {
      'System notifications will not be available',
      'Install libnotify (Linux) or terminal-notifier (macOS)',
    })
  end

  -- Check providers
  vim.health.start('pairup.nvim providers')

  local config = require('pairup.config')
  local current_provider = config.get_provider()

  -- Check Claude
  local claude_config = config.get_provider_config('claude')
  if claude_config and claude_config.path then
    if vim.fn.executable(claude_config.path) == 1 then
      vim.health.ok('Claude CLI found at: ' .. claude_config.path)
      if current_provider == 'claude' then
        vim.health.info('Claude is the active provider')
      end
    else
      if current_provider == 'claude' then
        vim.health.error('Claude CLI not found at: ' .. claude_config.path, {
          'Install Claude CLI: npm install -g @anthropic-ai/claude-cli',
          'Or configure the path in setup()',
        })
      else
        vim.health.info('Claude CLI not found (not the active provider)')
      end
    end
  end

  -- Future provider checks will go here
  if current_provider == 'openai' then
    vim.health.info('OpenAI provider not yet implemented')
  elseif current_provider == 'ollama' then
    vim.health.info('Ollama provider not yet implemented')
  end

  -- Check configuration
  vim.health.start('pairup.nvim configuration')

  if config.values and next(config.values) then
    vim.health.ok('Configuration loaded')

    -- Check critical settings
    if config.get('enabled') then
      vim.health.ok('Auto diff sending: enabled')
    else
      vim.health.info('Auto diff sending: disabled')
    end

    if config.get('lsp.enabled') then
      vim.health.info('LSP integration: enabled (experimental)')
    end

    if config.get('periodic_updates.enabled') then
      vim.health.info(
        string.format('Periodic updates: every %d minutes', config.get('periodic_updates.interval_minutes'))
      )
    end
  else
    vim.health.error('Configuration not loaded', {
      "Run :lua require('pairup').setup()",
    })
  end

  -- Check current session
  vim.health.start('pairup.nvim session')

  local providers = require('pairup.providers')
  local buf = providers.find_terminal()

  if buf then
    vim.health.ok('AI assistant session is active')
    local state = require('pairup.utils.state')
    local dirs = state.get('added_directories')
    if dirs and next(dirs) then
      vim.health.info('Directories with access:')
      for dir, _ in pairs(dirs) do
        vim.health.info('  • ' .. dir)
      end
    end
  else
    vim.health.info('No active AI assistant session')
    vim.health.info('Start with :PairupStart or :ClaudeStart')
  end
end

return M
