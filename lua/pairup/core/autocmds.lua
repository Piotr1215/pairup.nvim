-- Autocmds for pairup.nvim

local M = {}
local config = require('pairup.config')
local context = require('pairup.core.context')
local providers = require('pairup.providers')

-- Setup autocmds
function M.setup()
  -- Create augroup
  vim.api.nvim_create_augroup('Pairup', { clear = true })

  -- Send context on file save
  vim.api.nvim_create_autocmd('BufWritePost', {
    group = 'Pairup',
    pattern = '*',
    callback = function()
      if not config.get('enabled') then
        return
      end

      -- Skip certain files
      local filepath = vim.fn.expand('%:p')
      if filepath:match('%.git/') or filepath:match('node_modules/') or filepath:match('%.log$') then
        return
      end

      -- Only send if AI assistant is running
      local buf = providers.find_terminal()
      if buf then
        context.send_context()
      end
    end,
    desc = 'Send git diff to AI assistant on file save',
  })

  -- Auto-reload files when changed externally (by AI)
  if config.get('auto_refresh.enabled') then
    vim.o.autoread = true
    vim.o.updatetime = 1000 -- Check for file changes every 1 second when idle

    -- Event-based reload
    vim.api.nvim_create_autocmd({ 'FocusGained', 'BufEnter', 'CursorHold', 'CursorHoldI' }, {
      group = 'Pairup',
      pattern = '*',
      callback = function()
        if vim.fn.mode() ~= 'c' then
          vim.cmd('checktime')
        end
      end,
      desc = 'Auto-reload files changed by AI assistant',
    })

    -- Aggressive timer-based reload if configured
    local interval = config.get('auto_refresh.interval_ms')
    if interval and interval > 0 then
      local reload_timer = vim.loop.new_timer()
      reload_timer:start(
        interval,
        interval,
        vim.schedule_wrap(function()
          if vim.fn.mode() ~= 'c' then
            vim.cmd('silent! checktime')
          end
        end)
      )
    end
  end
end

return M
