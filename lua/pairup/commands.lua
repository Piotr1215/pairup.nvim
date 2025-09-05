local M = {}
local pairup = require('pairup')
local sessions = require('pairup.core.sessions')

function M.setup()
  -- Start command
  vim.api.nvim_create_user_command('PairupStart', function()
    pairup.start()
  end, {
    desc = 'Start AI assistant with intent prompt',
  })

  -- Toggle command
  vim.api.nvim_create_user_command('PairupToggle', function()
    pairup.toggle()
  end, {
    desc = 'Toggle AI assistant window',
  })

  -- Stop command
  vim.api.nvim_create_user_command('PairupStop', function()
    pairup.stop()
  end, {
    desc = 'Stop AI assistant',
  })


  -- Send context command
  vim.api.nvim_create_user_command('PairupContext', function()
    pairup.send_context()
  end, {
    desc = 'Send current context to AI assistant',
  })

  -- Send message command with shell/vim command support
  vim.api.nvim_create_user_command('PairupSay', function(opts)
    local message = opts.args
    
    -- Check for shell command (starts with !)
    if message:sub(1, 1) == '!' then
      local cmd = message:sub(2)
      local output = vim.fn.system(cmd)
      local formatted_message = string.format("Shell command output for `%s`:\n```\n%s\n```", cmd, output)
      pairup.send_message(formatted_message)
      
    -- Check for vim command (starts with :)
    elseif message:sub(1, 1) == ':' then
      local cmd = message:sub(2)
      -- Capture vim command output
      local ok, output = pcall(function()
        return vim.fn.execute(cmd)
      end)
      
      if ok then
        local formatted_message = string.format("Vim command output for `:%s`:\n```\n%s\n```", cmd, output)
        pairup.send_message(formatted_message)
      else
        vim.notify("Error executing vim command: " .. tostring(output), vim.log.levels.ERROR)
      end
      
    -- Regular message
    else
      pairup.send_message(message)
    end
  end, {
    nargs = '+',
    desc = 'Send message to AI assistant (use ! for shell, : for vim commands)',
  })

  -- Toggle git diff sending
  vim.api.nvim_create_user_command('PairupToggleDiff', function()
    pairup.toggle_git_diff_send()
  end, {
    desc = 'Toggle automatic git diff sending',
  })

  -- Update intent command
  vim.api.nvim_create_user_command('PairupIntent', function(opts)
    local intent = opts.args
    if intent == '' then
      intent = vim.fn.input('Enter session intent: ', '')
    end

    if intent ~= '' then
      local current_session = sessions.get_current_session()
      if not current_session then
        sessions.create_session(intent, '')
      else
        current_session.intent = intent
        vim.g.pairup_current_intent = intent
        sessions.save_session(current_session)
      end

      -- Session intent updated
    end
  end, {
    nargs = '*',
    desc = 'Update or set the current session intent',
  })

  -- Resume session command - starts Claude with --resume for interactive session selection
  vim.api.nvim_create_user_command('PairupResume', function()
    -- Start Claude with --resume flag for interactive session picker
    pairup.start_with_resume()
  end, {
    desc = 'Start Claude with interactive session picker (--resume)',
  })

  -- Wipe sessions commands
  vim.api.nvim_create_user_command('PairupWipeSessions', function(opts)
    if opts.args == 'all' then
      local confirm = vim.fn.input('Wipe ALL sessions? (y/N): ')
      if confirm:lower() == 'y' then
        sessions.wipe_all_sessions()
      end
    else
      local days = tonumber(opts.args) or 30
      sessions.wipe_old_sessions(days)
    end
  end, {
    nargs = '?',
    complete = function()
      return { 'all', '7', '14', '30', '60', '90' }
    end,
    desc = 'Wipe sessions (all or older than N days)',
  })

  -- Legacy Claude-specific commands for backward compatibility
  vim.api.nvim_create_user_command('ClaudeStart', function()
    pairup.start()
  end, {
    desc = '[Deprecated] Use :PairupStart instead',
  })

  vim.api.nvim_create_user_command('ClaudeToggle', function()
    pairup.toggle()
  end, {
    desc = '[Deprecated] Use :PairupToggle instead',
  })

  vim.api.nvim_create_user_command('ClaudeStop', function()
    pairup.stop()
  end, {
    desc = '[Deprecated] Use :PairupStop instead',
  })
end

return M
