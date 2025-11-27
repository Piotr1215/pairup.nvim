-- Health check for pairup.nvim

local M = {}

function M.check()
  vim.health.start('pairup.nvim')

  -- Check Neovim version
  local nvim_version = vim.version()
  if nvim_version.major >= 0 and nvim_version.minor >= 9 then
    vim.health.ok(string.format('Neovim version %s.%s.%s', nvim_version.major, nvim_version.minor, nvim_version.patch))
  else
    vim.health.error('Neovim 0.9+ required', {
      'Please upgrade Neovim to version 0.9 or higher',
    })
  end

  -- Check git
  if vim.fn.executable('git') == 1 then
    local git_version = vim.fn.system('git --version'):gsub('\n', '')
    vim.health.ok('Git: ' .. git_version)
  else
    vim.health.warn('Git not found', {
      'Git is optional but recommended',
    })
  end

  -- Check Claude CLI
  vim.health.start('pairup.nvim provider')

  local config = require('pairup.config')
  local claude_config = config.get_provider_config('claude')

  if claude_config and claude_config.path then
    if vim.fn.executable(claude_config.path) == 1 then
      vim.health.ok('Claude CLI found at: ' .. claude_config.path)
    else
      vim.health.error('Claude CLI not found at: ' .. claude_config.path, {
        'Install Claude CLI: https://docs.anthropic.com/en/docs/claude-code',
        'Or configure the path in setup()',
      })
    end
  end

  -- Check configuration
  vim.health.start('pairup.nvim configuration')

  if config.values and next(config.values) then
    vim.health.ok('Configuration loaded')

    if config.get('inline.enabled') then
      vim.health.ok('Inline mode: enabled')
      vim.health.info('Command marker: ' .. config.get('inline.markers.command'))
      vim.health.info('Question marker: ' .. config.get('inline.markers.question'))
    else
      vim.health.info('Inline mode: disabled')
    end
  else
    vim.health.error('Configuration not loaded', {
      "Run :lua require('pairup').setup()",
    })
  end

  -- Check session status
  vim.health.start('pairup.nvim session')

  local providers = require('pairup.providers')
  local buf = providers.find_terminal()

  if buf then
    vim.health.ok('Claude session active')
  else
    vim.health.info('No active session (use :Pairup start)')
  end
end

return M
