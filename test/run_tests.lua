#!/usr/bin/env -S nvim -l
-- Test runner script using Plenary

-- Completely reset environment
vim.cmd('set rtp=')
vim.cmd('set packpath=')

-- Add only what we need
vim.cmd('set rtp+=.') -- pairup.nvim itself

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

-- Load Plenary's test runner
local results = require('plenary.test_harness').test_directory('test', {
  minimal_init = 'test/plenary_init.lua',
  sequential = true,
})

-- Exit with proper code
vim.wait(100) -- Small delay to ensure output is flushed
os.exit(results and 0 or 1)
