" Minimal init for testing
set rtp+=.
set rtp+=~/.local/share/nvim/site/pack/packer/start/plenary.nvim
set rtp+=~/.local/share/nvim/lazy/plenary.nvim

runtime! plugin/plenary.vim
runtime! plugin/pairup.lua

" Set test mode
let g:pairup_test_mode = 1

" Prevent blocking in tests
autocmd VimEnter * lua vim.fn.input = function() return "" end