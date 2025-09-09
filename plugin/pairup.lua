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

vim.api.nvim_create_user_command('PairupRestoreLayout', function()
  require('pairup').restore_layout()
end, { desc = 'Restore Claude/buffer window split to configured width' })

-- Overlay creation command
vim.api.nvim_create_user_command('PairupCreateOverlay', function(opts)
  local overlay = require('pairup.overlay')
  overlay.setup()

  local bufnr = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = cursor[1]

  if opts.args and opts.args ~= '' then
    -- Send to Claude to get suggestion
    local providers = require('pairup.providers')
    local current_text = vim.api.nvim_buf_get_lines(bufnr, line - 1, line, false)[1]
    local message = string.format(
      'Please suggest an improvement for line %d:\n```\n%s\n```\nTask: %s\n\nRespond with ONLY the improved line, no explanation.',
      line,
      current_text,
      opts.args
    )
    providers.send_to_provider(message)
    vim.notify('Sent to Claude for suggestion. Claude can use overlays to show the suggestion.', vim.log.levels.INFO)
  else
    -- Test with simple suggestion
    local current_text = vim.api.nvim_buf_get_lines(bufnr, line - 1, line, false)[1]
    overlay.show_suggestion(bufnr, line, current_text, '// TODO: Claude suggests changing this line')
    vim.notify(
      'Test overlay shown. Use :PairupCreateOverlay <task> to ask Claude for specific improvements.',
      vim.log.levels.INFO
    )
  end
end, { nargs = '?', desc = 'Create overlay suggestion (optionally ask Claude)' })

vim.api.nvim_create_user_command('PairupClearOverlay', function()
  require('pairup.overlay').clear_overlays()
  vim.notify('Overlay cleared', vim.log.levels.INFO)
end, {})

-- Overlay interaction commands
vim.api.nvim_create_user_command('PairupAcceptOverlay', function()
  require('pairup.overlay').apply_at_cursor()
end, { desc = 'Accept suggestion at cursor position' })

vim.api.nvim_create_user_command('PairupAcceptNextOverlay', function()
  require('pairup.overlay').accept_next_overlay()
end, { desc = 'Find and accept nearest overlay suggestion' })

vim.api.nvim_create_user_command('PairupRejectOverlay', function()
  require('pairup.overlay').reject_at_cursor()
end, { desc = 'Reject suggestion at cursor position' })

vim.api.nvim_create_user_command('PairupNextOverlay', function()
  require('pairup.overlay').next_overlay()
end, { desc = 'Navigate to next overlay suggestion' })

vim.api.nvim_create_user_command('PairupPrevOverlay', function()
  require('pairup.overlay').prev_overlay()
end, { desc = 'Navigate to previous overlay suggestion' })

vim.api.nvim_create_user_command('PairupToggleOverlay', function()
  require('pairup.overlay').toggle()
end, { desc = 'Toggle overlay visibility' })

vim.api.nvim_create_user_command('PairupFollowMode', function()
  require('pairup.overlay').toggle_follow_mode()
end, { desc = 'Toggle auto-jump to new overlay suggestions' })

vim.api.nvim_create_user_command('PairupSuggestionOnly', function()
  require('pairup.overlay').toggle_suggestion_only()
end, { desc = 'Toggle suggestion-only mode (hide buffer content)' })
