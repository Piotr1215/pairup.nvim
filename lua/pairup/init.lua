-- Pairup - AI Pair Programming for Neovim
-- Inline editing with cc:/uu: markers
--
-- Author: Piotr1215
-- License: MIT

local M = {}

M._version = '4.0.0'
M._name = 'pairup.nvim'

-- Load modules
local config = require('pairup.config')
local providers = require('pairup.providers')

-- Public API
M.setup = function(opts)
  config.setup(opts or {})
  providers.setup()
  require('pairup.core.autocmds').setup()
  require('pairup.utils.indicator').update()
end

-- Core functions
M.start = function(intent)
  return providers.start(intent)
end

M.stop = function()
  return providers.stop()
end

M.toggle = function()
  return providers.toggle()
end

-- Send message to Claude
M.send_message = function(message)
  if message:sub(1, 1) == '!' then
    -- Shell command
    local cmd = vim.fn.expandcmd(message:sub(2))
    local output = vim.fn.system(cmd)
    providers.send_message(string.format('Shell output for `%s`:\n```\n%s\n```', cmd, output))
  elseif message:sub(1, 1) == ':' then
    -- Vim command
    local cmd = message:sub(2)
    local ok, output = pcall(vim.fn.execute, cmd)
    if ok then
      providers.send_message(string.format('Vim output for `:%s`:\n```\n%s\n```', cmd, output))
    else
      vim.notify('Error: ' .. tostring(output), vim.log.levels.ERROR)
    end
  else
    providers.send_message(message)
  end
end

-- Toggle git diff sending
M.toggle_git_diff_send = function()
  config.values.enabled = not config.values.enabled
  require('pairup.utils.indicator').update()
  local status = config.values.enabled and 'enabled' or 'disabled'
  vim.notify('Git diff sending ' .. status, vim.log.levels.INFO)
end

-- Toggle LSP integration
M.toggle_lsp = function()
  config.values.lsp = config.values.lsp or {}
  config.values.lsp.enabled = not config.values.lsp.enabled
  local status = config.values.lsp.enabled and 'enabled' or 'disabled'
  vim.notify('LSP integration ' .. status, vim.log.levels.INFO)
end

return M
