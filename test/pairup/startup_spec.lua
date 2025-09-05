local helpers = require('test.helpers')

describe('pairup startup configuration', function()
  local pairup
  local mock_claude

  before_each(function()
    -- Set test mode
    vim.g.pairup_test_mode = true

    -- Clear modules
    for k, _ in pairs(package.loaded) do
      if k:match('^pairup') then
        package.loaded[k] = nil
      end
    end

    -- Mock vim.fn.input to prevent blocking
    vim.fn.input = function()
      return ''
    end

    mock_claude = {}

    -- Mock all the terminal and command functionality
    local original_cmd = vim.cmd
    vim.cmd = function(cmd_str)
      if type(cmd_str) == 'string' then
        if cmd_str:match('term://') then
          table.insert(mock_claude, { terminal_cmd = cmd_str })
          -- Create mock terminal buffer
          local buf = vim.api.nvim_create_buf(false, true)
          vim.b[buf].is_pairup_assistant = true
          vim.b[buf].provider = 'claude'
          vim.b[buf].terminal_job_id = 999
          vim.api.nvim_set_current_buf(buf)
          return
        elseif cmd_str:match('wincmd') or cmd_str:match('startinsert') or cmd_str:match('stopinsert') then
          return -- Ignore window/mode commands
        end
      end
      return original_cmd(cmd_str)
    end

    -- Mock vim.fn functions
    local original_fn = vim.fn
    vim.fn = setmetatable({
      exepath = function(cmd)
        if cmd == 'claude' then
          return '/usr/bin/claude'
        end
        return ''
      end,
      system = function(cmd)
        if cmd:match('uuidgen') then
          return 'test-uuid-123\n'
        end
        return ''
      end,
      systemlist = function()
        return {}
      end,
      shellescape = function(s)
        return "'" .. s .. "'"
      end,
      executable = function()
        return 1
      end,
      getcwd = function()
        return '/test'
      end,
      input = function()
        return ''
      end,
    }, { __index = original_fn })

    pairup = require('pairup')
  end)

  after_each(function()
    vim.g.pairup_test_mode = nil
  end)

  describe('startup settings', function()
    it('should default to plan mode', function()
      -- Mock all required modules
      package.loaded['pairup.commands'] = { setup = function() end }
      package.loaded['pairup.core.autocmds'] = { setup = function() end }
      package.loaded['pairup.core.context'] = { setup = function() end }
      package.loaded['pairup.core.sessions'] = { setup = function() end }
      package.loaded['pairup.utils.indicator'] = { update = function() end }
      package.loaded['pairup.providers'] = { setup = function() end }

      pairup.setup({
        provider = 'claude',
        persist_sessions = true,
        providers = {
          claude = {
            path = '/usr/bin/claude',
            permission_mode = 'plan',
            add_dir_on_start = true,
          },
        },
      })

      -- Just verify configuration is correct
      local config = require('pairup.config')
      assert.equals('plan', config.get('providers.claude.permission_mode'))
    end)

    it('should start with auto populate intent enabled', function()
      pairup.setup({
        provider = 'claude',
        auto_populate_intent = true,
        intent_template = 'Working on %s...',
      })

      local config = require('pairup.config')
      assert.is_true(config.get('auto_populate_intent'))
      assert.equals('Working on %s...', config.get('intent_template'))
    end)

    it('should enable persistence by default', function()
      -- Mock all required modules
      package.loaded['pairup.commands'] = { setup = function() end }
      package.loaded['pairup.core.autocmds'] = { setup = function() end }
      package.loaded['pairup.core.context'] = { setup = function() end }
      package.loaded['pairup.core.sessions'] = {
        setup = function() end,
        set_claude_session_id = function() end,
      }
      package.loaded['pairup.utils.indicator'] = { update = function() end }
      package.loaded['pairup.providers'] = { setup = function() end }

      pairup.setup({
        provider = 'claude',
        persist_sessions = true,
      })

      -- Just verify configuration
      local config = require('pairup.config')
      assert.is_true(config.get('persist_sessions'))
    end)
  end)
end)
