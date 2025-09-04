-- Configuration tests
local config = require('pairup.config')

describe('pairup config', function()
  before_each(function()
    -- Reset config before each test
    config.values = {}
  end)

  describe('setup()', function()
    it('uses default values when no options provided', function()
      config.setup()
      assert.equals('claude', config.get('provider'))
      assert.equals(10, config.get('diff_context_lines'))
      assert.is_true(config.get('enabled'))
      assert.equals('left', config.get('terminal.split_position'))
      assert.equals(0.4, config.get('terminal.split_width'))
    end)

    it('merges user options with defaults', function()
      config.setup({
        provider = 'claude',
        diff_context_lines = 20,
        terminal = {
          split_width = 0.5,
        },
      })
      assert.equals('claude', config.get('provider'))
      assert.equals(20, config.get('diff_context_lines'))
      assert.equals(0.5, config.get('terminal.split_width'))
      assert.equals('left', config.get('terminal.split_position')) -- default preserved
    end)

    it('validates terminal split width', function()
      config.setup({
        terminal = {
          split_width = 2.0, -- invalid
        },
      })
      assert.equals(0.4, config.get('terminal.split_width')) -- should use default
    end)
  end)

  describe('get()', function()
    it('retrieves simple values', function()
      config.setup({
        enabled = false,
        diff_context_lines = 15,
      })
      assert.is_false(config.get('enabled'))
      assert.equals(15, config.get('diff_context_lines'))
    end)

    it('retrieves nested values with dot notation', function()
      config.setup()
      assert.equals('left', config.get('terminal.split_position'))
      assert.is_true(config.get('terminal.auto_insert'))
      assert.is_false(config.get('lsp.enabled'))
    end)

    it('returns nil for non-existent keys', function()
      config.setup()
      assert.is_nil(config.get('nonexistent'))
      assert.is_nil(config.get('terminal.nonexistent'))
    end)
  end)

  describe('set()', function()
    it('sets simple values', function()
      config.setup()
      config.set('enabled', false)
      assert.is_false(config.get('enabled'))
    end)

    it('sets nested values with dot notation', function()
      config.setup()
      config.set('terminal.split_width', 0.6)
      assert.equals(0.6, config.get('terminal.split_width'))
    end)

    it('creates nested structure if needed', function()
      config.setup()
      config.set('new.nested.value', 'test')
      assert.equals('test', config.get('new.nested.value'))
    end)
  end)

  describe('provider configuration', function()
    it('gets current provider', function()
      config.setup({ provider = 'claude' })
      assert.equals('claude', config.get_provider())
    end)

    it('gets provider-specific config', function()
      config.setup()
      local claude_config = config.get_provider_config('claude')
      assert.is_not_nil(claude_config)
      assert.is_not_nil(claude_config.path)
      assert.equals('acceptEdits', claude_config.permission_mode)
    end)

    it('validates unknown provider', function()
      -- Mock vim.notify to capture the warning
      local original_notify = vim.notify
      local notified = false
      vim.notify = function(msg, level)
        if level == vim.log.levels.WARN and msg:match('Unknown provider') then
          notified = true
        end
      end

      config.setup({ provider = 'unknown' })
      assert.is_true(notified)
      assert.equals('claude', config.get_provider()) -- should fall back to claude

      -- Restore original notify
      vim.notify = original_notify
    end)
  end)
end)
