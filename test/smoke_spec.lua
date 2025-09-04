-- Smoke tests using real Plenary busted
local pairup = require('pairup')

describe('pairup.nvim', function()
  describe('plugin loading', function()
    it('loads successfully', function()
      local ok = pcall(require, 'pairup')
      assert.is_true(ok)
    end)

    it('has correct version and name', function()
      assert.equals('0.1.0', pairup._version)
      assert.equals('pairup.nvim', pairup._name)
    end)
  end)

  describe('setup()', function()
    it('configures plugin with defaults', function()
      pairup.setup()
      local config = require('pairup.config')
      assert.equals('claude', config.get('provider'))
      assert.equals(10, config.get('diff_context_lines'))
      assert.is_true(config.get('enabled'))
    end)

    it('accepts custom configuration', function()
      pairup.setup({
        provider = 'claude',
        diff_context_lines = 15,
        enabled = false,
      })
      local config = require('pairup.config')
      assert.equals('claude', config.get('provider'))
      assert.equals(15, config.get('diff_context_lines'))
      assert.is_false(config.get('enabled'))
    end)
  end)

  describe('providers', function()
    it('registers Claude provider', function()
      local providers = require('pairup.providers')
      providers.setup()
      local claude = providers.get('claude')
      assert.is_not_nil(claude)
      assert.equals('claude', claude.name)
    end)

    it('has provider functions', function()
      local providers = require('pairup.providers')
      assert.is_function(providers.start)
      assert.is_function(providers.toggle)
      assert.is_function(providers.stop)
      assert.is_function(providers.send_message)
    end)
  end)

  -- Note: Command tests removed since plugin/pairup.lua isn't loaded in test environment
  -- Commands are tested manually in actual Neovim usage

  describe('health check', function()
    it('has health module', function()
      local ok, health = pcall(require, 'pairup.health')
      assert.is_true(ok)
      assert.is_function(health.check)
    end)
  end)
end)
