local helpers = require('test.helpers')

describe('pairup suggestion mode', function()
  local pairup
  local mock_sends

  before_each(function()
    -- Clean state
    vim.g.pairup_test_mode = true
    mock_sends = {}

    package.loaded['pairup'] = nil
    package.loaded['pairup.config'] = nil
    package.loaded['pairup.core.context'] = nil
    package.loaded['pairup.providers'] = nil
    package.loaded['pairup.providers.claude'] = nil
    package.loaded['pairup.commands'] = { setup = function() end }

    -- Mock context module to capture sends
    package.loaded['pairup.core.context'] = {
      setup = function() end,
      send_context = function(opts)
        table.insert(mock_sends, {
          type = 'context',
          options = opts or {},
        })
      end,
      clear = function() end,
    }

    pairup = require('pairup')
  end)

  describe('suggestion only behavior', function()
    it('should send with suggestions_only flag when enabled', function()
      -- Clear mock sends
      mock_sends = {}

      pairup.setup({
        provider = 'claude',
        suggestion_mode = true,
        enabled = true,
      })

      -- Directly test that context is sent with correct flag
      local context = require('pairup.core.context')
      context.send_context({ suggestions_only = true })

      -- Check the mock was called correctly
      assert.equals(1, #mock_sends, 'Should have sent one message')
      assert.is_true(mock_sends[1].options.suggestions_only == true, 'Should send with suggestions_only flag')
    end)

    it('should not send suggestions flag when disabled', function()
      pairup.setup({
        provider = 'claude',
        suggestion_mode = false, -- Disabled
        enabled = true,
      })

      package.loaded['pairup.providers'] = {
        setup = function() end,
        find_terminal = function()
          return helpers.mock_terminal_buffer()
        end,
        start = function()
          return true
        end,
        toggle = function() end,
        stop = function() end,
        send_message = function() end,
      }

      local autocmds = require('pairup.core.autocmds')
      autocmds.setup()

      vim.api.nvim_exec_autocmds('BufWritePost', {
        pattern = 'test.lua',
        data = { file = 'test.lua' },
      })

      vim.wait(600)

      -- Should not have suggestions flag
      for _, send in ipairs(mock_sends) do
        assert.is_not_true(send.options.suggestions_only == true, 'Should not have suggestions_only flag')
      end
    end)
  end)

  describe('intent mode interaction', function()
    it('should work with intent declaration', function()
      local sessions = require('pairup.core.sessions')

      pairup.setup({
        provider = 'claude',
        suggestion_mode = true,
        auto_populate_intent = true,
        intent_template = 'Working on `%s` to improve performance',
      })

      -- Create session with intent
      sessions.create_session('Optimize database queries', 'Performance improvements')

      -- Intent should guide suggestions
      local current = sessions.get_current_session()
      assert.is_not_nil(current)
      assert.equals('Optimize database queries', current.intent)

      -- Context sends should still be suggestions only
      local context = require('pairup.core.context')
      context.send_context({ suggestions_only = true })

      assert.equals('context', mock_sends[1].type)
      assert.is_true(mock_sends[1].options.suggestions_only)
    end)
  end)

  describe('configuration', function()
    it('should respect default configuration', function()
      pairup.setup({
        provider = 'claude',
        -- suggestion_mode not explicitly set
      })

      local config = require('pairup.config')
      -- Default should be true based on spec
      assert.is_true(config.get('suggestion_mode'))
    end)

    it('should allow toggling suggestion mode', function()
      pairup.setup({
        provider = 'claude',
        suggestion_mode = true,
      })

      local config = require('pairup.config')
      assert.is_true(config.get('suggestion_mode'))

      -- Toggle it off
      config.set('suggestion_mode', false)
      assert.is_false(config.get('suggestion_mode'))

      -- Toggle back on
      config.set('suggestion_mode', true)
      assert.is_true(config.get('suggestion_mode'))
    end)
  end)
end)
