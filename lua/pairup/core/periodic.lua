-- Periodic updates for pairup.nvim

local M = {}
local git = require('pairup.utils.git')
local providers = require('pairup.providers')

-- Timer for periodic updates
local status_timer = nil

-- Start periodic status updates
function M.start_updates(interval_minutes)
  if status_timer then
    status_timer:stop()
  end

  local interval_ms = (interval_minutes or 10) * 60 * 1000
  status_timer = vim.loop.new_timer()

  status_timer:start(
    interval_ms,
    interval_ms,
    vim.schedule_wrap(function()
      local buf = providers.find_terminal()
      if buf then
        git.send_git_status()
      end
    end)
  )
end

-- Stop periodic updates
function M.stop_updates()
  if status_timer then
    status_timer:stop()
    status_timer = nil
  end
end

return M
