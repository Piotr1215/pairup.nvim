-- Autocmds for pairup.nvim

local M = {}
local config = require('pairup.config')
local providers = require('pairup.providers')

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

      if not providers.find_terminal() then
        return
      end

      if config.get('inline.enabled') then
        local inline = require('pairup.inline')
        if inline.has_cc_markers() then
          inline.process()
        end
        inline.update_quickfix()
      end
    end,
  })

  -- Save user's unsaved changes BEFORE reload to prevent data loss
  vim.api.nvim_create_autocmd('FileChangedShell', {
    group = 'Pairup',
    pattern = '*',
    callback = function()
      if not config.get('inline.enabled') then
        return
      end

      local filepath = vim.fn.expand('%:p')
      local indicator = require('pairup.utils.indicator')

      if not indicator.is_pending(filepath) then
        return
      end

      local bufnr = vim.api.nvim_get_current_buf()
      if vim.bo[bufnr].modified then
        vim.cmd('silent! write')
      end

      vim.v.fcs_choice = 'reload'
    end,
  })

  -- Clear pending when cc: markers are gone
  vim.api.nvim_create_autocmd('FileChangedShellPost', {
    group = 'Pairup',
    pattern = '*',
    callback = function()
      if not config.get('inline.enabled') then
        return
      end

      local filepath = vim.fn.expand('%:p')
      local indicator = require('pairup.utils.indicator')

      if vim.g.pairup_pending ~= filepath then
        return
      end

      local inline = require('pairup.inline')
      local bufnr = vim.api.nvim_get_current_buf()

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

    vim.api.nvim_create_autocmd({ 'FocusGained', 'BufEnter', 'CursorHold' }, {
      group = 'Pairup',
      pattern = '*',
      callback = function()
        if vim.fn.mode() ~= 'c' and vim.fn.getcmdwintype() == '' then
          vim.cmd('checktime')
        end
      end,
    })

    local interval = config.get('auto_refresh.interval_ms')
    if interval and interval > 0 then
      local timer = vim.loop.new_timer()
      timer:start(
        interval,
        interval,
        vim.schedule_wrap(function()
          if vim.fn.mode() ~= 'c' and vim.fn.getcmdwintype() == '' then
            vim.cmd('silent! checktime')
          end
        end)
      )
    end
  end
end

return M
