-- Pairup plugin entry point
if vim.g.loaded_pairup then
  return
end
vim.g.loaded_pairup = true

-- Create user commands
vim.api.nvim_create_user_command('PairupStart', function(opts)
  require('pairup').start(opts.args ~= '' and opts.args or nil)
end, { nargs = '?', desc = 'Start AI pair programming assistant' })

vim.api.nvim_create_user_command('PairupToggle', function()
  require('pairup').toggle()
end, { desc = 'Toggle AI assistant window' })

vim.api.nvim_create_user_command('PairupStop', function()
  require('pairup').stop()
end, { desc = 'Stop AI assistant' })

vim.api.nvim_create_user_command('PairupContext', function()
  require('pairup').send_context(true)
end, { desc = 'Send current file git diff to AI' })

vim.api.nvim_create_user_command('PairupSay', function(opts)
  require('pairup').send_message(opts.args)
end, { nargs = '+', desc = 'Send message to AI' })

vim.api.nvim_create_user_command('PairupToggleDiff', function()
  require('pairup').toggle_git_diff_send()
end, { desc = 'Toggle automatic git diff sending' })

vim.api.nvim_create_user_command('PairupStatus', function()
  require('pairup').send_git_status()
end, { desc = 'Send git status to AI' })

vim.api.nvim_create_user_command('PairupFileInfo', function()
  require('pairup.core.context').send_file_info()
end, { desc = 'Send file info to AI' })

vim.api.nvim_create_user_command('PairupAddDir', function()
  require('pairup.core.context').add_current_directory()
end, { desc = 'Add directory to AI context' })
