#!/usr/bin/env -S nvim -l
-- Test runner script using Plenary

-- PREVENT ALL BLOCKING - Critical for CI/automated tests
vim.g.pairup_test_mode = true
vim.fn.input = function()
  return ''
end
vim.fn.inputlist = function()
  return 1
end
vim.fn.confirm = function()
  return 1
end
vim.fn.getchar = function()
  return 13
end

-- Completely reset environment
vim.cmd('set rtp=')
vim.cmd('set packpath=')

-- Add only what we need
vim.cmd('set rtp+=.') -- pairup.nvim itself
vim.cmd('set rtp+=./test') -- test directory for mocks

-- Find and add Plenary
local plenary_paths = {
  vim.fn.expand('~/.local/share/nvim/lazy/plenary.nvim'),
  vim.fn.stdpath('data') .. '/site/pack/vendor/start/plenary.nvim',
  vim.fn.expand('~/.local/share/nvim/site/pack/vendor/start/plenary.nvim'),
}

local plenary_found = false
for _, path in ipairs(plenary_paths) do
  if vim.fn.isdirectory(path) == 1 then
    vim.cmd('set rtp+=' .. path)
    plenary_found = true
    break
  end
end

if not plenary_found then
  print('Error: Plenary not found!')
  os.exit(1)
end

-- Add Neovim runtime last
vim.cmd('set rtp+=' .. vim.env.VIMRUNTIME)

-- Load Plenary's test runner with timeout
local results = require('plenary.test_harness').test_directory('test/pairup', {
  minimal_init = 'test/plenary_init.lua',
  sequential = true,
  timeout = 5000, -- 5 second timeout per test
})

-- Force exit after short delay
vim.defer_fn(function()
  os.exit(results and 0 or 1)
end, 100)
