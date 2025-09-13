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

  -- Initialize overlay module (for virtual text suggestions)
  require('pairup.overlay').setup()

  -- Initialize RPC support (auto-detects and enables Claude superpowers)
  require('pairup.rpc').setup({
    port = config.get('rpc.port') or '127.0.0.1:6666',
  })

  -- Setup autocmds
  require('pairup.core.autocmds').setup()

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
M.send_git_status = git.send_git_status
M.toggle_git_diff_send = function()
  config.values.enabled = not config.values.enabled
  require('pairup.utils.indicator').update()
end

-- Enhanced send_message with shell/vim command support
M.send_message = function(message)
  -- Check for shell command (starts with !)
  if message:sub(1, 1) == '!' then
    local cmd = message:sub(2)
    -- Expand vim filename modifiers (%, #, etc.)
    cmd = vim.fn.expandcmd(cmd)
    local output = vim.fn.system(cmd)
    local formatted_message = string.format('Shell command output for `%s`:\n```\n%s\n```', cmd, output)
    providers.send_message(formatted_message)

  -- Check for vim command (starts with :)
  elseif message:sub(1, 1) == ':' then
    local cmd = message:sub(2)
    -- Capture vim command output
    local ok, output = pcall(function()
      return vim.fn.execute(cmd)
    end)

    if ok then
      local formatted_message = string.format('Vim command output for `:%s`:\n```\n%s\n```', cmd, output)
      providers.send_message(formatted_message)
    else
      vim.notify('Error executing vim command: ' .. tostring(output), vim.log.levels.ERROR)
    end

  -- Regular message
  else
    providers.send_message(message)
  end
end

-- Restore claude/buffer window split layout
M.restore_layout = function()
  local provider = providers.get_current()
  if provider and provider.restore_layout then
    return provider.restore_layout()
  end
  vim.notify('No active assistant to restore layout', vim.log.levels.WARN)
end

-- Toggle LSP diagnostics
M.toggle_lsp = function()
  config.values.lsp.enabled = not config.values.lsp.enabled
  local status = config.values.lsp.enabled and 'enabled' or 'disabled'
  vim.notify('Pairup LSP diagnostics ' .. status, vim.log.levels.INFO)
end

-- Update or set session intent
M.set_intent = function(intent)
  if intent == '' then
    intent = vim.fn.input('Enter session intent: ', '')
  end

  if intent ~= '' then
    local sessions = require('pairup.core.sessions')
    local current_session = sessions.get_current_session()
    if not current_session then
      sessions.create_session(intent, '')
    else
      current_session.intent = intent
      vim.g.pairup_current_intent = intent
      sessions.save_session(current_session)
    end
  end
end

-- Overlay functions
M.toggle_overlay = function()
  local overlay = require('pairup.overlay')
  overlay.toggle()
end

M.accept_overlay = function()
  local overlay = require('pairup.overlay')
  overlay.apply_at_cursor()
end

M.reject_overlay = function()
  local overlay = require('pairup.overlay')
  overlay.reject_at_cursor()
end

M.accept_next_overlay = function()
  local overlay = require('pairup.overlay')
  overlay.accept_next_overlay()
end

M.accept_all_overlays = function()
  local overlay = require('pairup.overlay')
  overlay.accept_all_overlays()
end

M.next_overlay = function()
  local overlay = require('pairup.overlay')
  overlay.next_overlay()
end

M.prev_overlay = function()
  local overlay = require('pairup.overlay')
  overlay.prev_overlay()
end

M.toggle_follow_mode = function()
  local overlay = require('pairup.overlay')
  overlay.toggle_follow_mode()
end

M.toggle_suggestion_only = function()
  local overlay = require('pairup.overlay')
  overlay.toggle_suggestion_only()
end

M.open_overlay_scope = function()
  local overlay_scope = require('pairup.overlay_scope')
  overlay_scope.open_scope()
end

M.overlay_quickfix = function()
  local overlay_scope = require('pairup.overlay_scope')
  overlay_scope.create_quickfix_list()
end

-- Legacy Claude-specific aliases (for backward compatibility)
M.start_claude = M.start
M.toggle_claude = M.toggle
M.stop_claude = M.stop

return M
