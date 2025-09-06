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
end, { nargs = '+', desc = 'Send message to AI (use ! for shell, : for vim commands)' })

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

vim.api.nvim_create_user_command('PairupStartUpdates', function(opts)
  local interval = tonumber(opts.args) or 10
  require('pairup.core.periodic').start_updates(interval)
  vim.notify(string.format('Started periodic updates every %d minutes', interval), vim.log.levels.INFO)
end, { nargs = '?', desc = 'Start periodic status updates (default 10 minutes)' })

vim.api.nvim_create_user_command('PairupStopUpdates', function()
  require('pairup.core.periodic').stop_updates()
  vim.notify('Stopped periodic updates', vim.log.levels.INFO)
end, { desc = 'Stop periodic status updates' })

vim.api.nvim_create_user_command('PairupToggleLSP', function()
  require('pairup').toggle_lsp()
end, { desc = 'Toggle LSP diagnostics in context updates' })

vim.api.nvim_create_user_command('PairupIntent', function(opts)
  require('pairup').set_intent(opts.args)
end, { nargs = '*', desc = 'Update or set the current session intent' })

vim.api.nvim_create_user_command('PairupResume', function()
  require('pairup').start_with_resume()
end, { desc = 'Start with interactive session picker (--resume)' })
