-- Load the plugin
vim.g.loaded_pairup = 1

-- Initialize
local pairup = require('pairup')

-- =============================================================================
-- CORE PAIRUP COMMANDS (AI control, not overlay-specific)
-- =============================================================================

vim.api.nvim_create_user_command('PairupStart', function(opts)
  pairup.start(opts.args ~= '' and opts.args or nil)
end, { desc = 'Start AI assistant', nargs = '?' })

vim.api.nvim_create_user_command('PairupStop', function()
  pairup.stop()
end, { desc = 'Stop AI assistant' })

vim.api.nvim_create_user_command('PairupToggle', function()
  pairup.toggle()
end, { desc = 'Toggle AI assistant visibility' })

vim.api.nvim_create_user_command('PairupSay', function(opts)
  pairup.send_message(opts.args)
end, { desc = 'Send message to AI', nargs = '*' })

vim.api.nvim_create_user_command('PairupContext', function()
  pairup.send_current_context()
end, { desc = 'Send current file context to AI' })

vim.api.nvim_create_user_command('PairupStatus', function()
  pairup.send_status()
end, { desc = 'Send git status to AI' })

vim.api.nvim_create_user_command('PairupFileInfo', function()
  pairup.send_file_info()
end, { desc = 'Send file information to AI' })

vim.api.nvim_create_user_command('PairupToggleDiff', function()
  pairup.toggle_git_diff_send()
end, { desc = 'Toggle automatic diff sending' })

vim.api.nvim_create_user_command('PairupToggleLSP', function()
  pairup.toggle_lsp()
end, { desc = 'Toggle LSP integration' })

vim.api.nvim_create_user_command('PairupResume', function()
  require('pairup.core.sessions').show_session_picker()
end, { desc = 'Resume a previous session' })

vim.api.nvim_create_user_command('PairupIntent', function(opts)
  pairup.set_intent(opts.args)
end, { desc = 'Set working intent', nargs = '*' })

vim.api.nvim_create_user_command('PairupAddDir', function(opts)
  local path = opts.args ~= '' and opts.args or vim.fn.getcwd()
  pairup.add_project_dir(path)
end, { desc = 'Add project directory to AI context', nargs = '?' })

vim.api.nvim_create_user_command('PairupStartUpdates', function()
  require('pairup.core.periodic').start_periodic_updates()
end, { desc = 'Start periodic status updates' })

vim.api.nvim_create_user_command('PairupStopUpdates', function()
  require('pairup.core.periodic').stop_periodic_updates()
end, { desc = 'Stop periodic status updates' })

vim.api.nvim_create_user_command('PairupRestoreLayout', function()
  require('pairup.utils.layout').restore_layout()
end, { desc = 'Restore window layout after AI closes' })

-- =============================================================================
-- OVERLAY COMMANDS - Simplified and consistent
-- =============================================================================

-- Navigation
vim.api.nvim_create_user_command('PairNext', function()
  require('pairup.overlay').next_overlay()
end, { desc = 'Next overlay' })

vim.api.nvim_create_user_command('PairPrev', function()
  require('pairup.overlay').prev_overlay()
end, { desc = 'Previous overlay' })

-- Staging Workflow (NEW - recommended)
vim.api.nvim_create_user_command('PairMark', function(opts)
  local overlay = require('pairup.overlay')
  if opts.args == '' then
    overlay.toggle_state()
  elseif opts.args:lower() == 'accept' or opts.args:lower() == 'a' then
    overlay.accept_staged()
  elseif opts.args:lower() == 'reject' or opts.args:lower() == 'r' then
    overlay.reject_staged()
  else
    vim.notify('Usage: :PairMark [accept|reject] or just :PairMark to toggle', vim.log.levels.WARN)
  end
end, { desc = 'Mark overlay (accept/reject/toggle)', nargs = '?' })

vim.api.nvim_create_user_command('PairProcess', function()
  require('pairup.overlay').process_overlays()
end, { desc = 'Process all marked overlays' })

vim.api.nvim_create_user_command('PairUnprocessed', function()
  require('pairup.overlay').next_unprocessed()
end, { desc = 'Jump to next unprocessed overlay' })

-- Smart Actions - mark and auto-process when done
vim.api.nvim_create_user_command('PairAccept', function()
  local overlay = require('pairup.overlay')
  overlay.accept_staged()
  -- Move to next unprocessed overlay
  overlay.next_unprocessed()
  -- Check if there are any more pending overlays, if not, process all
  local bufnr = vim.api.nvim_get_current_buf()
  if not overlay.has_pending_overlays(bufnr) then
    overlay.process_overlays(bufnr)
  end
end, { desc = 'Accept overlay and move to next (auto-process when done)' })

vim.api.nvim_create_user_command('PairReject', function()
  local overlay = require('pairup.overlay')
  overlay.reject_staged()
  -- Move to next unprocessed overlay
  overlay.next_unprocessed()
  -- Check if there are any more pending overlays, if not, process all
  local bufnr = vim.api.nvim_get_current_buf()
  if not overlay.has_pending_overlays(bufnr) then
    overlay.process_overlays(bufnr)
  end
end, { desc = 'Reject overlay and move to next (auto-process when done)' })

vim.api.nvim_create_user_command('PairAcceptAll', function()
  require('pairup.overlay').accept_all_overlays()
end, { desc = 'Accept all overlays immediately' })

-- Utilities
vim.api.nvim_create_user_command('PairClear', function()
  require('pairup.overlay').clear_overlays()
end, { desc = 'Clear all overlays' })

vim.api.nvim_create_user_command('PairEdit', function()
  require('pairup.overlay_editor').edit_at_cursor()
end, { desc = 'Edit overlay at cursor' })

-- Persistence
vim.api.nvim_create_user_command('PairSave', function(opts)
  local persist = require('pairup.overlay_persistence')
  local ok, path, count = persist.save_overlays(opts.args ~= '' and opts.args or nil)
  if ok then
    vim.notify(string.format('Saved %d overlays to %s', count, vim.fn.fnamemodify(path, ':~')), vim.log.levels.INFO)
  else
    vim.notify('Failed to save overlays: ' .. (path or 'unknown error'), vim.log.levels.ERROR)
  end
end, { desc = 'Save overlays to file', nargs = '?' })

vim.api.nvim_create_user_command('PairRestore', function(opts)
  local persist = require('pairup.overlay_persistence')
  local ok, path, count = persist.restore_overlays(opts.args ~= '' and opts.args or nil)
  if ok then
    vim.notify(
      string.format('Restored %d overlays from %s', count, vim.fn.fnamemodify(path, ':~')),
      vim.log.levels.INFO
    )
  else
    vim.notify('Failed to restore overlays: ' .. (path or 'unknown error'), vim.log.levels.ERROR)
  end
end, { desc = 'Restore overlays from file', nargs = '?' })

-- Special Commands
vim.api.nvim_create_user_command('PairMarkerToOverlay', function()
  local marker = require('pairup.marker_parser_direct')
  marker.parse_to_overlays()
end, { desc = 'Convert Claude markers to overlays' })

vim.api.nvim_create_user_command('PairHelp', function()
  local help = [[
=== Pairup Overlay Commands ===

STAGING WORKFLOW (Recommended):
  :PairMark        - Toggle overlay state (pending→accepted→rejected)
  :PairMark accept - Mark as accepted
  :PairMark reject - Mark as rejected
  :PairProcess     - Apply all marked overlays at once
  :PairUnprocessed - Jump to next unprocessed overlay

NAVIGATION:
  :PairNext        - Jump to next overlay
  :PairPrev        - Jump to previous overlay

IMMEDIATE ACTIONS (Old workflow):
  :PairAccept      - Accept overlay immediately
  :PairReject      - Reject overlay immediately
  :PairAcceptAll   - Accept all overlays

UTILITIES:
  :PairClear       - Clear all overlays
  :PairEdit        - Edit overlay before accepting
  :PairSave        - Save overlays to file
  :PairRestore     - Restore overlays from file

Visual indicators:
  ⏳ Pending    - Not yet reviewed
  ✅ Accepted   - Will be applied with :PairProcess
  ❌ Rejected   - Will be discarded with :PairProcess
  ✏️ Edited     - Accepted with modifications]]

  vim.notify(help, vim.log.levels.INFO)
end, { desc = 'Show overlay command help' })

-- Setup command (for lazy loading)
vim.api.nvim_create_user_command('PairupSetup', function()
  pairup.setup()
end, { desc = 'Initialize pairup.nvim' })
