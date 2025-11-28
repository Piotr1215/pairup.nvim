-- Autocmds for pairup.nvim

local M = {}
local config = require('pairup.config')
local providers = require('pairup.providers')

-- Timer reference for cleanup
local refresh_timer = nil

function M.setup()
  vim.api.nvim_create_augroup('Pairup', { clear = true })

  -- Process cc: markers on file save
  vim.api.nvim_create_autocmd('BufWritePost', {
    group = 'Pairup',
    pattern = '*',
    callback = function()
      local filepath = vim.fn.expand('%:p')
      if filepath:match('%.git/') or filepath:match('node_modules/') then
        return
      end

      if not providers.is_running() then
        return
      end

      local inline = require('pairup.inline')

      -- Update quickfix and process markers when pairup is running
      inline.update_quickfix()

      if inline.has_cc_markers() then
        inline.process()
      end
    end,
  })

  -- Save user's unsaved changes BEFORE reload to prevent data loss
  -- Also snapshot buffer for change highlighting
  vim.api.nvim_create_autocmd('FileChangedShell', {
    group = 'Pairup',
    pattern = '*',
    callback = function(args)
      local bufnr = args.buf

      -- Snapshot for change highlighting
      local flash = require('pairup.utils.flash')
      flash.snapshot(bufnr)

      local filepath = vim.fn.expand('%:p')
      local indicator = require('pairup.utils.indicator')

      if not indicator.is_pending(filepath) then
        return
      end

      if vim.bo[bufnr].modified then
        vim.cmd('silent! write')
      end

      vim.v.fcs_choice = 'reload'
    end,
  })

  -- Clear pending when cc: markers are gone + highlight changes
  vim.api.nvim_create_autocmd('FileChangedShellPost', {
    group = 'Pairup',
    pattern = '*',
    callback = function(args)
      local bufnr = args.buf

      -- Highlight changed lines
      local flash = require('pairup.utils.flash')
      flash.highlight_changes(bufnr)

      local filepath = vim.fn.expand('%:p')
      local indicator = require('pairup.utils.indicator')

      if vim.g.pairup_pending ~= filepath then
        return
      end

      local inline = require('pairup.inline')

      if not inline.has_cc_markers(bufnr) then
        indicator.clear_pending()
      elseif inline.has_uu_markers(bufnr) then
        indicator.clear_pending()
      else
        indicator.clear_pending()
        vim.defer_fn(function()
          if vim.api.nvim_buf_is_valid(bufnr) then
            inline.process(bufnr)
          end
        end, 300)
      end

      inline.update_quickfix()
    end,
  })

  -- Auto-reload files changed by Claude
  if config.get('auto_refresh.enabled') then
    vim.o.autoread = true

    -- Snapshot all file buffers before checktime
    local function snapshot_all_buffers()
      local flash = require('pairup.utils.flash')
      for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(bufnr) and vim.bo[bufnr].buftype == '' then
          flash.snapshot(bufnr)
        end
      end
    end

    vim.api.nvim_create_autocmd({ 'FocusGained', 'BufEnter', 'CursorHold' }, {
      group = 'Pairup',
      pattern = '*',
      callback = function()
        if vim.fn.mode() ~= 'c' and vim.fn.getcmdwintype() == '' then
          snapshot_all_buffers()
          vim.cmd('checktime')
        end
      end,
    })

    local interval = config.get('auto_refresh.interval_ms')
    if interval and interval > 0 then
      refresh_timer = vim.loop.new_timer()
      refresh_timer:start(
        interval,
        interval,
        vim.schedule_wrap(function()
          if vim.fn.mode() ~= 'c' and vim.fn.getcmdwintype() == '' then
            snapshot_all_buffers()
            vim.cmd('silent! checktime')
          end
        end)
      )
    end
  end
end

--- Cleanup timers on plugin unload
function M.cleanup()
  if refresh_timer then
    if not refresh_timer:is_closing() then
      refresh_timer:stop()
      refresh_timer:close()
    end
    refresh_timer = nil
  end
end

return M
