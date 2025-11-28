-- Health check for pairup.nvim

local M = {}

local health = vim.health or require('health')
local start = health.start or health.report_start
local ok = health.ok or health.report_ok
local warn = health.warn or health.report_warn
local error = health.error or health.report_error
local info = health.info or health.report_info

---Check if pairup.nvim is loaded and configured
---@return boolean success
local function check_plugin_loaded()
  local pairup_loaded = pcall(require, 'pairup')
  if not pairup_loaded then
    error('pairup.nvim is not loaded')
    return false
  end
  ok('pairup.nvim is loaded')

  local config = require('pairup.config')
  if config.values and next(config.values) then
    ok('Configuration loaded')
    return true
  else
    error('Configuration not loaded', {
      "Run require('pairup').setup()",
    })
    return false
  end
end

---Check if configured CLI is available
local function check_cli()
  local config = require('pairup.config')
  local provider = config.get_provider()
  local provider_config = config.get_provider_config()

  if not provider_config or not provider_config.path then
    error('No provider configured')
    return
  end

  local cli_path = provider_config.path

  -- Check if CLI exists
  if vim.fn.executable(cli_path) ~= 1 then
    error(string.format('%s CLI not found: %s', provider, cli_path), {
      'Install Claude CLI: https://docs.anthropic.com/en/docs/claude-code',
      'Or specify path: require("pairup").setup({ providers = { claude = { path = "/path/to/claude" } } })',
    })
    return
  end

  -- Try to get version
  local version_cmd = cli_path .. ' --version 2>/dev/null'
  local handle = io.popen(version_cmd)
  if handle then
    local result = handle:read('*a')
    handle:close()
    if result and result ~= '' then
      ok(string.format('%s CLI: %s', provider, vim.trim(result)))
    else
      ok(string.format('%s CLI found: %s', provider, cli_path))
    end
  else
    ok(string.format('%s CLI found: %s', provider, cli_path))
  end
end

---Check git availability
local function check_git()
  local config = require('pairup.config')

  if not config.get('git.enabled') then
    info('Git integration is disabled')
    return
  end

  if vim.fn.executable('git') == 1 then
    local handle = io.popen('git --version 2>/dev/null')
    if handle then
      local result = handle:read('*a')
      handle:close()
      ok('Git: ' .. vim.trim(result))
    else
      ok('Git is available')
    end
  else
    warn('Git not found', {
      'Git integration requires git in PATH',
      'Disable with: require("pairup").setup({ git = { enabled = false } })',
    })
  end
end

---Check inline mode configuration
local function check_inline_mode()
  local config = require('pairup.config')

  if config.get('inline.enabled') then
    ok('Inline mode: ENABLED')
    info('  Command marker: ' .. config.get('inline.markers.command'))
    info('  Question marker: ' .. config.get('inline.markers.question'))
  else
    info('Inline mode: DISABLED')
    info('  Enable with: require("pairup").setup({ inline = { enabled = true } })')
  end
end

---Check session status
local function check_session()
  local providers = require('pairup.providers')
  local buf = providers.find_terminal()

  if buf then
    ok('Claude session is active')
  else
    info('No active session')
    info('  Start with: :Pairup start')
  end
end

---Check statusline integration
local function check_statusline()
  local config = require('pairup.config')

  if config.get('statusline.auto_inject') == false then
    info('Lualine auto-injection: DISABLED')
    info('  Enable with: require("pairup").setup({ statusline = { auto_inject = true } })')
    return
  end

  local statusline = require('pairup.integrations.statusline')

  if package.loaded['lualine'] then
    ok('Lualine detected')
    if statusline.inject() then
      ok('Pairup component injected into lualine_c')
    else
      warn('Failed to inject pairup component')
    end
  else
    info('Lualine not detected, using native statusline')
    if statusline.inject() then
      ok('Pairup indicator added to statusline')
    else
      warn('Failed to inject into statusline')
    end
  end
end

---Show usage examples
local function show_usage()
  info('')
  info('Quick Start:')
  info('  :Pairup start          Start Claude session (split terminal)')
  info('  :Pairup stop           Stop Claude session')
  info('  :Pairup toggle         Toggle Claude terminal visibility')
  info('')
  info('Inline Mode (cc: markers):')
  info('  gC{motion}             Insert cc: marker for text object')
  info('  gC in visual mode      Insert cc: marker for selection')
  info('  Write instruction after cc: marker, save file')
  info('  Claude reads and executes instructions automatically')
  info('')
  info('Navigation:')
  info('  ]C                     Jump to next cc:/uu: marker')
  info('  [C                     Jump to previous cc:/uu: marker')
  info('')
  info('Example workflow:')
  info('  1. Start session: :Pairup start')
  info('  2. In your code, type: // cc: add error handling')
  info('  3. Save file - Claude receives the instruction')
  info('  4. Claude edits your file directly')
end

---Run health checks for pairup.nvim
function M.check()
  start('pairup.nvim')

  if not check_plugin_loaded() then
    return
  end

  start('Provider CLI')
  check_cli()

  start('Git Integration')
  check_git()

  start('Inline Mode')
  check_inline_mode()

  start('Session Status')
  check_session()

  start('Statusline Integration')
  check_statusline()

  start('Usage')
  show_usage()
end

return M
