" Minimal init for testing

" Clear all runtimepath and packpath to prevent loading user config
set rtp=
set packpath=

" Disable loading of user config files
set noloadplugins
let g:loaded_netrwPlugin = 1
let g:loaded_tutor_mode_plugin = 1
let g:loaded_2html_plugin = 1
let g:loaded_zipPlugin = 1
let g:loaded_tarPlugin = 1
let g:loaded_gzip = 1

" Add only what we need
set rtp+=.
set rtp+=~/.local/share/nvim/site/pack/packer/start/plenary.nvim
set rtp+=~/.local/share/nvim/lazy/plenary.nvim

" Add Neovim runtime last to get basic functionality
exe 'set rtp+=' . $VIMRUNTIME

runtime! plugin/plenary.vim
runtime! plugin/pairup.lua

" Set test mode
let g:pairup_test_mode = 1

" Prevent blocking in tests
autocmd VimEnter * lua vim.fn.input = function() return "" end