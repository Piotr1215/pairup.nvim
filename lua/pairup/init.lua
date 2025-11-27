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
  require('pairup.utils.indicator').setup()
  require('pairup.utils.indicator').update()
  require('pairup.operator').setup(opts and opts.operator)
  require('pairup.signs').setup()
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

-- Send git diff to Claude
M.send_diff = function()
  require('pairup.utils.git').send_git_status()
  vim.notify('Sent git diff to Claude', vim.log.levels.INFO)
end

-- Send LSP diagnostics to Claude
M.send_lsp = function()
  local bufnr = vim.api.nvim_get_current_buf()
  local filepath = vim.api.nvim_buf_get_name(bufnr)
  local diagnostics = vim.diagnostic.get(bufnr)

  if #diagnostics == 0 then
    vim.notify('No LSP diagnostics in current buffer', vim.log.levels.INFO)
    return
  end

  local lines = {}
  table.insert(lines, string.format('File: %s', filepath))
  table.insert(lines, string.format('Diagnostics (%d):', #diagnostics))
  table.insert(lines, '')

  for _, d in ipairs(diagnostics) do
    local severity = vim.diagnostic.severity[d.severity] or 'UNKNOWN'
    table.insert(lines, string.format('Line %d: [%s] %s', d.lnum + 1, severity, d.message))
  end

  table.insert(lines, '')
  table.insert(lines, 'Fix these issues.')

  providers.send_message(table.concat(lines, '\n'))
  vim.notify(string.format('Sent %d diagnostics to Claude', #diagnostics), vim.log.levels.INFO)
end

return M
