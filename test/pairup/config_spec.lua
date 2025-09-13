-- Simple configuration tests
describe('pairup configuration', function()
  local config

  before_each(function()
    package.loaded['pairup.config'] = nil
    config = require('pairup.config')
  end)

  describe('defaults', function()
    it('should have correct default values', function()
      config.setup({})

      assert.equals('claude', config.get('provider'))
      assert.equals('plan', config.get('providers.claude.permission_mode'))
      assert.is_true(config.get('sessions.persist'))
      assert.is_true(config.get('overlay.inject_instructions'))
      assert.is_true(config.get('sessions.auto_populate_intent'))
    end)

    it('should have correct intent template', function()
      config.setup({})
      local template = config.get('sessions.intent_template')
      assert.is_string(template)
      assert.is_truthy(template:match('intent declaration'))
    end)
  end)

  describe('user overrides', function()
    it('should accept user configuration', function()
      config.setup({
        persist_sessions = false,
        suggestion_mode = false,
        providers = {
          claude = {
            permission_mode = 'acceptEdits',
          },
        },
      })

      assert.is_false(config.get('persist_sessions'))
      assert.is_false(config.get('suggestion_mode'))
      assert.equals('acceptEdits', config.get('providers.claude.permission_mode'))
    end)
  end)

  describe('validation', function()
    it('should validate provider exists', function()
      config.setup({ provider = 'invalid' })
      -- Should fallback to claude
      assert.equals('claude', config.get('provider'))
    end)

    it('should validate terminal split width', function()
      config.setup({ terminal = { split_width = 2.0 } })
      -- Should fallback to default
      assert.equals(0.4, config.get('terminal.split_width'))
    end)
  end)
end)
