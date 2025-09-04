-- Pairup - AI Pair Programming for Neovim
-- Real-time context-aware AI assistance through git diffs
--
-- Author: Piotr1215
-- License: MIT

local M = {}

-- Version
M._version = '0.1.0'
M._name = 'pairup.nvim'

-- Load modules
local config = require('pairup.config')
local providers = require('pairup.providers')
local context = require('pairup.core.context')
local git = require('pairup.utils.git')

-- Public API
M.setup = function(opts)
  -- Setup configuration
  config.setup(opts or {})

  -- Initialize providers
  providers.setup()

  -- Initialize context module
  context.setup()

  -- Setup autocmds
  require('pairup.core.autocmds').setup()

  -- Initialize indicator
  require('pairup.utils.indicator').update()
end

-- Exported functions for external use
M.start = providers.start
M.toggle = providers.toggle
M.stop = providers.stop
M.send_context = context.send_context
M.send_message = providers.send_message
M.send_git_status = git.send_git_status
M.toggle_git_diff_send = function()
  config.values.enabled = not config.values.enabled
  require('pairup.utils.indicator').update()
end

-- Legacy Claude-specific aliases (for backward compatibility)
M.start_claude = providers.start
M.toggle_claude = providers.toggle
M.stop_claude = providers.stop

return M
