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

-- ============================================================================
-- OVERLAY COMMANDS - All overlay-related commands use PairupOverlay* prefix
-- ============================================================================

-- Overlay creation command
vim.api.nvim_create_user_command('PairupOverlayCreate', function(opts)
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

vim.api.nvim_create_user_command('PairupOverlayClear', function()
  require('pairup.overlay').clear_overlays()
  vim.notify('Overlay cleared', vim.log.levels.INFO)
end, {})

-- Overlay interaction commands
vim.api.nvim_create_user_command('PairupOverlayAccept', function()
  require('pairup.overlay').apply_at_cursor()
end, { desc = 'Accept suggestion at cursor position' })

vim.api.nvim_create_user_command('PairupOverlayAcceptNext', function()
  require('pairup.overlay').accept_next_overlay()
end, { desc = 'Find and accept nearest overlay suggestion' })

vim.api.nvim_create_user_command('PairupOverlayReject', function()
  require('pairup.overlay').reject_at_cursor()
end, { desc = 'Reject suggestion at cursor position' })

vim.api.nvim_create_user_command('PairupOverlayNext', function()
  require('pairup.overlay').next_overlay()
end, { desc = 'Navigate to next overlay suggestion' })

vim.api.nvim_create_user_command('PairupOverlayPrev', function()
  require('pairup.overlay').prev_overlay()
end, { desc = 'Navigate to previous overlay suggestion' })

vim.api.nvim_create_user_command('PairupOverlayToggle', function()
  require('pairup.overlay').toggle()
end, { desc = 'Toggle overlay visibility' })

vim.api.nvim_create_user_command('PairupOverlayFollowMode', function()
  require('pairup.overlay').toggle_follow_mode()
end, { desc = 'Toggle auto-jump to new overlay suggestions' })

vim.api.nvim_create_user_command('PairupOverlaySuggestionOnly', function()
  require('pairup.overlay').toggle_suggestion_only()
end, { desc = 'Toggle suggestion-only mode (hide buffer content)' })

-- Overlay scope commands
vim.api.nvim_create_user_command('PairupOverlayScope', function()
  require('pairup.overlay_scope').open_scope()
end, { desc = 'Open overlay scope view showing only suggestions' })

vim.api.nvim_create_user_command('PairupOverlayQuickfix', function()
  require('pairup.overlay_scope').create_quickfix_list()
end, { desc = 'Create quickfix list from overlay suggestions' })

vim.api.nvim_create_user_command('PairupOverlayEdit', function()
  require('pairup.overlay_editor').edit_overlay_at_cursor()
end, { desc = 'Edit overlay suggestion at cursor position' })

vim.api.nvim_create_user_command('PairupOverlayExport', function(opts)
  local rpc = require('pairup.rpc')
  local result = vim.json.decode(rpc.export_overlays(opts.args ~= '' and opts.args or nil))
  if result.success then
    vim.notify('Overlays exported to: ' .. result.file, vim.log.levels.INFO)
  else
    vim.notify('Export failed: ' .. (result.error or 'Unknown error'), vim.log.levels.ERROR)
  end
end, { desc = 'Export overlays to file', nargs = '?' })

vim.api.nvim_create_user_command('PairupOverlayImport', function(opts)
  local rpc = require('pairup.rpc')
  local result = vim.json.decode(rpc.import_overlays(opts.args ~= '' and opts.args or nil))
  if result.success then
    vim.notify('Imported ' .. result.imported .. ' overlays from: ' .. result.file, vim.log.levels.INFO)
  else
    vim.notify('Import failed: ' .. (result.error or 'Unknown error'), vim.log.levels.ERROR)
  end
end, { desc = 'Import overlays from file', nargs = '?' })

-- Variant cycling commands
vim.api.nvim_create_user_command('PairupOverlayCycle', function()
  local overlay = require('pairup.overlay')
  local cursor = vim.api.nvim_win_get_cursor(0)
  local bufnr = vim.api.nvim_get_current_buf()
  if overlay.cycle_variant(bufnr, cursor[1], 1) then
    vim.notify('Cycled to next variant', vim.log.levels.INFO)
  else
    vim.notify('No variants to cycle', vim.log.levels.WARN)
  end
end, { desc = 'Cycle to next overlay variant' })

vim.api.nvim_create_user_command('PairupOverlayCyclePrev', function()
  local overlay = require('pairup.overlay')
  local cursor = vim.api.nvim_win_get_cursor(0)
  local bufnr = vim.api.nvim_get_current_buf()
  if overlay.cycle_variant(bufnr, cursor[1], -1) then
    vim.notify('Cycled to previous variant', vim.log.levels.INFO)
  else
    vim.notify('No variants to cycle', vim.log.levels.WARN)
  end
end, { desc = 'Cycle to previous overlay variant' })

-- ============================================================================
-- SHORTER COMMAND ALIASES FOR BETTER UX
-- ============================================================================

vim.api.nvim_create_user_command('PairAccept', function()
  require('pairup.overlay').apply_at_cursor()
end, { desc = 'Accept overlay at cursor (alias for PairupOverlayAccept)' })

vim.api.nvim_create_user_command('PairReject', function()
  require('pairup.overlay').reject_at_cursor()
end, { desc = 'Reject overlay at cursor (alias for PairupOverlayReject)' })

vim.api.nvim_create_user_command('PairNext', function()
  require('pairup.overlay').next_overlay()
end, { desc = 'Go to next overlay (alias for PairupOverlayNext)' })

vim.api.nvim_create_user_command('PairPrev', function()
  require('pairup.overlay').prev_overlay()
end, { desc = 'Go to previous overlay (alias for PairupOverlayPrev)' })

vim.api.nvim_create_user_command('PairEdit', function()
  require('pairup.overlay_editor').edit_overlay_at_cursor()
end, { desc = 'Edit overlay at cursor (alias for PairupOverlayEdit)' })

vim.api.nvim_create_user_command('PairClear', function()
  require('pairup.overlay').clear_overlays()
  vim.notify('All overlays cleared', vim.log.levels.INFO)
end, { desc = 'Clear all overlays (alias for PairupOverlayClear)' })

vim.api.nvim_create_user_command('PairStatus', function()
  local overlay = require('pairup.overlay')
  local bufnr = vim.api.nvim_get_current_buf()
  local suggestions = overlay.get_suggestions(bufnr)
  local count = 0
  local lines = {}

  for line_num, _ in pairs(suggestions) do
    count = count + 1
    table.insert(lines, line_num)
  end
  table.sort(lines)

  if count > 0 then
    vim.notify(string.format('%d overlays at lines: %s', count, table.concat(lines, ', ')), vim.log.levels.INFO)
  else
    vim.notify('No overlays in current buffer', vim.log.levels.INFO)
  end
end, { desc = 'Show overlay status' })

vim.api.nvim_create_user_command('PairHelp', function()
  local help = [[
=== Pairup Overlay Commands (Short Aliases) ===

Navigation:
  :PairNext       - Jump to next overlay
  :PairPrev       - Jump to previous overlay
  
Actions:
  :PairAccept     - Accept overlay at cursor
  :PairReject     - Reject overlay at cursor  
  :PairEdit       - Edit overlay before accepting
  :PairClear      - Clear all overlays
  :PairStatus     - Show overlay count and locations
  
Full Commands (same functionality):
  :PairupOverlay[Accept|Reject|Next|Prev|Edit|Clear|Toggle]
  
Tips:
  - Overlays track position with extmarks (survive edits)
  - Use tab completion to discover all commands
  - Add overlay count to statusline with require('pairup.overlay').get_status()]]

  vim.notify(help, vim.log.levels.INFO)
end, { desc = 'Show overlay command help' })

-- ============================================================================
-- OVERLAY PERSISTENCE COMMANDS
-- ============================================================================

vim.api.nvim_create_user_command('PairupOverlaySave', function(opts)
  local persist = require('pairup.overlay_persistence')
  local ok, path, count = persist.save_overlays(opts.args ~= '' and opts.args or nil)

  if ok then
    vim.notify(string.format('Saved %d overlays to %s', count, vim.fn.fnamemodify(path, ':~')), vim.log.levels.INFO)
  else
    vim.notify('Failed to save: ' .. path, vim.log.levels.ERROR)
  end
end, { desc = 'Save current overlays to file', nargs = '?' })

vim.api.nvim_create_user_command('PairupOverlayRestore', function(opts)
  local persist = require('pairup.overlay_persistence')

  -- If no file specified, show picker
  if opts.args == '' then
    local sessions = persist.list_sessions()
    if #sessions == 0 then
      vim.notify('No saved overlay sessions found', vim.log.levels.WARN)
      return
    end

    -- Build picker items
    local items = {}
    for _, session in ipairs(sessions) do
      table.insert(
        items,
        string.format(
          '%s | %d overlays | %s',
          session.date,
          session.overlay_count,
          vim.fn.fnamemodify(session.file, ':t')
        )
      )
    end

    -- Show picker
    vim.ui.select(items, {
      prompt = 'Select overlay session to restore:',
    }, function(choice, idx)
      if choice and idx then
        local session = sessions[idx]
        local ok, msg = persist.restore_overlays(session.path)
        if ok then
          vim.notify(msg, vim.log.levels.INFO)
        else
          vim.notify('Failed: ' .. msg, vim.log.levels.ERROR)
        end
      end
    end)
  else
    -- Direct file path provided
    local ok, msg = persist.restore_overlays(opts.args)
    if ok then
      vim.notify(msg, vim.log.levels.INFO)
    else
      vim.notify('Failed: ' .. msg, vim.log.levels.ERROR)
    end
  end
end, { desc = 'Restore overlays from file', nargs = '?' })

vim.api.nvim_create_user_command('PairupOverlayList', function()
  local persist = require('pairup.overlay_persistence')
  local sessions = persist.list_sessions()

  if #sessions == 0 then
    vim.notify('No saved overlay sessions', vim.log.levels.INFO)
    return
  end

  local lines = { '=== Saved Overlay Sessions ===', '' }
  for i, session in ipairs(sessions) do
    table.insert(lines, string.format('%d. %s', i, session.date))
    table.insert(lines, string.format('   File: %s', vim.fn.fnamemodify(session.file, ':~')))
    table.insert(lines, string.format('   Overlays: %d', session.overlay_count))
    table.insert(lines, '')
  end

  vim.notify(table.concat(lines, '\n'), vim.log.levels.INFO)
end, { desc = 'List saved overlay sessions' })

vim.api.nvim_create_user_command('PairupOverlayAutoSave', function()
  require('pairup.overlay_persistence').auto_save()
end, { desc = 'Auto-save current overlays' })

-- Shorter aliases for persistence
vim.api.nvim_create_user_command('PairSave', function(opts)
  vim.cmd('PairupOverlaySave ' .. opts.args)
end, { desc = 'Save overlays (alias)', nargs = '?' })

vim.api.nvim_create_user_command('PairRestore', function(opts)
  vim.cmd('PairupOverlayRestore ' .. opts.args)
end, { desc = 'Restore overlays (alias)', nargs = '?' })

-- Set up autocmds for overlay persistence
local function setup_overlay_persistence_autocmds()
  local config = require('pairup.config')

  -- Only set up autocmds if persistence is enabled
  if not config.get('overlay_persistence.enabled') or not config.get('overlay_persistence.auto_save') then
    return
  end

  local group = vim.api.nvim_create_augroup('PairupOverlayPersistence', { clear = true })

  -- Auto-save on buffer write
  vim.api.nvim_create_autocmd('BufWritePost', {
    group = group,
    pattern = '*',
    callback = function()
      local persist = require('pairup.overlay_persistence')
      local overlay = require('pairup.overlay')
      local suggestions = overlay.get_suggestions()

      -- Only save if there are overlays
      local count = 0
      for _, _ in pairs(suggestions) do
        count = count + 1
      end

      if count > 0 then
        persist.auto_save()
        -- Clean old sessions based on config
        local max_sessions = config.get('overlay_persistence.max_sessions')
        if max_sessions then
          persist.clean_old_sessions(max_sessions)
        end
      end
    end,
    desc = 'Auto-save overlays after buffer write',
  })

  -- Auto-save on buffer unload
  vim.api.nvim_create_autocmd('BufUnload', {
    group = group,
    pattern = '*',
    callback = function()
      local persist = require('pairup.overlay_persistence')
      persist.auto_save()
    end,
    desc = 'Auto-save overlays when unloading buffer',
  })

  -- Auto-save before exiting Neovim
  vim.api.nvim_create_autocmd('VimLeavePre', {
    group = group,
    pattern = '*',
    callback = function()
      local persist = require('pairup.overlay_persistence')
      persist.auto_save()
    end,
    desc = 'Auto-save overlays before exiting Neovim',
  })
end

-- Initialize overlay persistence autocmds after config is loaded
vim.defer_fn(function()
  setup_overlay_persistence_autocmds()
end, 0)
