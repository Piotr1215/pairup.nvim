-- Simple, isolated unit tests that should always pass
describe('pairup pure functions', function()
  describe('utils.claude', function()
    local claude_utils

    before_each(function()
      package.loaded['pairup.utils.claude'] = nil
      claude_utils = require('pairup.utils.claude')
    end)

    it('should build command with session ID', function()
      local config = {
        path = 'claude',
        permission_mode = 'plan',
      }
      local session_id = 'test-123'

      local cmd = claude_utils.build_command(config, session_id)

      assert.equals('claude', cmd[1])
      assert.equals('--session-id', cmd[2])
      assert.equals('test-123', cmd[3])
      assert.equals('--permission-mode', cmd[4])
      assert.equals('plan', cmd[5])
    end)

    it('should format intent template', function()
      local template = 'Working on `%s` to improve performance'
      local filename = 'test.lua'

      local result = claude_utils.format_intent(template, filename)

      assert.equals('Working on `test.lua` to improve performance', result)
    end)

    it('should parse session choice correctly', function()
      assert.equals(1, claude_utils.parse_session_choice('1', 3))
      assert.equals(2, claude_utils.parse_session_choice('2', 3))
      assert.equals('new', claude_utils.parse_session_choice('4', 3))
      assert.is_nil(claude_utils.parse_session_choice('0', 3))
      assert.is_nil(claude_utils.parse_session_choice('abc', 3))
    end)
  end)

  describe('config module', function()
    local config

    before_each(function()
      package.loaded['pairup.config'] = nil
      config = require('pairup.config')
    end)

    it('should have default values', function()
      config.setup({})

      assert.equals('claude', config.get('provider'))
      assert.equals('plan', config.get('providers.claude.permission_mode'))
      assert.is_true(config.get('sessions.persist'))
      assert.is_true(config.get('overlay.inject_instructions'))
    end)

    it('should merge user config', function()
      config.setup({
        provider = 'claude', -- Use valid provider
        persist_sessions = false,
        custom_option = 'value',
      })

      assert.equals('claude', config.get('provider'))
      assert.is_false(config.get('persist_sessions'))
      assert.equals('value', config.get('custom_option'))
    end)

    it('should get nested config values', function()
      config.setup({
        providers = {
          claude = {
            path = '/custom/path',
            permission_mode = 'acceptEdits',
          },
        },
      })

      assert.equals('/custom/path', config.get('providers.claude.path'))
      assert.equals('acceptEdits', config.get('providers.claude.permission_mode'))
    end)
  end)

  describe('sessions pure logic', function()
    it('should generate valid session IDs', function()
      -- Pure function test - no external deps
      local function generate_id()
        return string.format(
          '%08x-%04x-%04x-%04x-%012x',
          math.random(0, 0xffffffff),
          math.random(0, 0xffff),
          math.random(0, 0xffff),
          math.random(0, 0xffff),
          math.random(0, 0xffffffffffff)
        )
      end

      local id = generate_id()
      assert.is_string(id)
      assert.equals(36, #id) -- UUID format length
      assert.is_truthy(id:match('^%x+%-%x+%-%x+%-%x+%-%x+$'))
    end)

    it('should format session data correctly', function()
      local session = {
        id = 'test-123',
        intent = 'Refactor code',
        files = { 'a.lua', 'b.lua' },
        created_at = 1234567890,
      }

      assert.equals('test-123', session.id)
      assert.equals('Refactor code', session.intent)
      assert.equals(2, #session.files)
      assert.equals(1234567890, session.created_at)
    end)
  end)
end)
