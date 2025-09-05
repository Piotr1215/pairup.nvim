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
local sessions = require('pairup.core.sessions')

-- Public API
M.setup = function(opts)
  -- Setup configuration
  config.setup(opts or {})

  -- Initialize providers
  providers.setup()

  -- Initialize context module
  context.setup()

  -- Initialize sessions module
  sessions.setup()

  -- Initialize RPC support (auto-detects and enables Claude superpowers)
  require('pairup.rpc').setup()

  -- Setup autocmds
  require('pairup.core.autocmds').setup()

  -- Setup commands
  require('pairup.commands').setup()

  -- Initialize indicator
  require('pairup.utils.indicator').update()
end

-- Exported functions for external use
M.start = function(intent_mode, session_id)
  return providers.start(intent_mode, session_id)
end
M.toggle = function(intent_mode, session_id)
  return providers.toggle(intent_mode, session_id)
end
M.start_with_resume = function()
  return providers.start_with_resume()
end
M.stop = function()
  return providers.stop()
end
M.send_context = context.send_context
M.send_message = providers.send_message
M.send_git_status = git.send_git_status
M.toggle_git_diff_send = function()
  config.values.enabled = not config.values.enabled
  require('pairup.utils.indicator').update()
end

-- Legacy Claude-specific aliases (for backward compatibility)
M.start_claude = M.start
M.toggle_claude = M.toggle
M.stop_claude = M.stop

return M
