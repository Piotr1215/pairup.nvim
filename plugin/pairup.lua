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

-- v3.0 Simplified Actions - immediate accept/reject
vim.api.nvim_create_user_command('PairAccept', function()
  local overlay = require('pairup.overlay')
  if overlay.apply_at_cursor() then
    -- Move to next overlay if available
    overlay.next_overlay()
  end
end, { desc = 'Accept overlay at cursor and move to next' })

vim.api.nvim_create_user_command('PairReject', function()
  local overlay = require('pairup.overlay')
  if overlay.reject_at_cursor() then
    -- Move to next overlay if available
    overlay.next_overlay()
  end
end, { desc = 'Reject overlay at cursor and move to next' })

vim.api.nvim_create_user_command('PairAcceptAll', function()
  require('pairup.overlay').accept_all_overlays()
end, { desc = 'Accept all overlays immediately' })

-- Utilities
vim.api.nvim_create_user_command('PairClear', function()
  require('pairup.overlay').clear_buffer()
end, { desc = 'Clear all overlays in current buffer' })

vim.api.nvim_create_user_command('PairEdit', function()
  require('pairup.overlay_editor').edit_at_cursor()
end, { desc = 'Edit overlay at cursor before accepting' })

-- Special Commands
vim.api.nvim_create_user_command('PairMarkerToOverlay', function()
  local marker = require('pairup.marker_parser_direct')
  marker.parse_to_overlays()
end, { desc = 'Convert Claude markers to overlays' })

vim.api.nvim_create_user_command('PairHelp', function()
  local help = [[
=== Pairup Overlay Commands (v3.0 Simplified) ===

CORE WORKFLOW:
  1. AI outputs CLAUDE:MARKER suggestions
  2. Run :PairMarkerToOverlay to create overlays
  3. Review and accept/reject individual suggestions

NAVIGATION:
  :PairNext        - Jump to next overlay
  :PairPrev        - Jump to previous overlay

ACTIONS:
  :PairAccept      - Accept overlay at cursor and move to next
  :PairReject      - Reject overlay at cursor and move to next
  :PairEdit        - Edit overlay before accepting
  :PairAcceptAll   - Accept all overlays in buffer

UTILITIES:
  :PairClear       - Clear all overlays in buffer
  :PairMarkerToOverlay - Convert Claude markers to overlays

MARKER FORMAT (for AI):
  CLAUDE:MARKER-LINE,COUNT | Reasoning
  replacement code here]]

  vim.notify(help, vim.log.levels.INFO)
end, { desc = 'Show overlay command help' })

-- Setup command (for lazy loading)
vim.api.nvim_create_user_command('PairupSetup', function()
  pairup.setup()
end, { desc = 'Initialize pairup.nvim' })
