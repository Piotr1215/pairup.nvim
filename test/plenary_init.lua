-- Proper Plenary test initialization
-- Prevent loading user config by clearing paths FIRST
vim.opt.rtp = {}
vim.opt.packpath = {}

-- Skip loading user init.lua
vim.env.MYVIMRC = ''

-- Add only what we need
vim.opt.rtp:append('.')

-- Try multiple locations for Plenary (CI vs local)
local plenary_paths = {
  '/home/decoder/.local/share/nvim/lazy/plenary.nvim',
  vim.fn.stdpath('data') .. '/site/pack/vendor/start/plenary.nvim',
  '~/.local/share/nvim/site/pack/vendor/start/plenary.nvim',
}

for _, path in ipairs(plenary_paths) do
  local expanded = vim.fn.expand(path)
  if vim.fn.isdirectory(expanded) == 1 then
    vim.opt.rtp:append(expanded)
    break
  end
end

vim.opt.rtp:append(vim.env.VIMRUNTIME)

-- Disable unnecessary plugins
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

-- Basic vim settings for tests
vim.opt.swapfile = false
vim.opt.backup = false
vim.opt.writebackup = false
vim.opt.hidden = true
