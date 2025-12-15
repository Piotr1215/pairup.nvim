describe('pairup.config', function()
  local config

  before_each(function()
    -- Reset modules
    package.loaded['pairup.config'] = nil
    config = require('pairup.config')
  end)

  describe('defaults', function()
    it('should have auto_insert disabled by default', function()
      config.setup()
      assert.are.equal(false, config.get('terminal.auto_insert'))
    end)

    it('should have auto_scroll enabled by default', function()
      config.setup()
      assert.are.equal(true, config.get('terminal.auto_scroll'))
    end)

    it('should have default split_width of 0.4', function()
      config.setup()
      assert.are.equal(0.4, config.get('terminal.split_width'))
    end)

    it('should have default split_position of left', function()
      config.setup()
      assert.are.equal('left', config.get('terminal.split_position'))
    end)
  end)

  describe('setup', function()
    it('should allow enabling auto_insert', function()
      config.setup({
        terminal = {
          auto_insert = true,
        },
      })
      assert.are.equal(true, config.get('terminal.auto_insert'))
    end)

    it('should allow disabling auto_insert explicitly', function()
      config.setup({
        terminal = {
          auto_insert = false,
        },
      })
      assert.are.equal(false, config.get('terminal.auto_insert'))
    end)

    it('should merge with defaults', function()
      config.setup({
        terminal = {
          auto_insert = true,
        },
      })
      -- auto_insert should be overridden
      assert.are.equal(true, config.get('terminal.auto_insert'))
      -- auto_scroll should remain default
      assert.are.equal(true, config.get('terminal.auto_scroll'))
    end)
  end)

  describe('get', function()
    it('should return nil for non-existent keys', function()
      config.setup()
      assert.is_nil(config.get('nonexistent.key'))
    end)

    it('should support dot notation for nested keys', function()
      config.setup()
      assert.are.equal('claude', config.get('provider'))
      assert.are.equal(true, config.get('git.enabled'))
    end)
  end)

  describe('set', function()
    it('should allow setting values at runtime', function()
      config.setup()
      config.set('terminal.auto_insert', true)
      assert.are.equal(true, config.get('terminal.auto_insert'))
    end)
  end)

  describe('progress', function()
    it('should have progress disabled by default', function()
      config.setup()
      assert.are.equal(false, config.get('progress.enabled'))
    end)

    it('should have default progress file in /tmp', function()
      config.setup()
      local progress_file = config.get('progress.file')
      assert.are.equal('/tmp/claude_progress', progress_file)
    end)

    it('should allow enabling progress', function()
      config.setup({ progress = { enabled = true } })
      assert.are.equal(true, config.get('progress.enabled'))
    end)

    it('should allow custom progress file path', function()
      config.setup({ progress = { file = '/custom/path' } })
      assert.are.equal('/custom/path', config.get('progress.file'))
    end)
  end)

  describe('flash', function()
    it('should have scroll_to_changes disabled by default', function()
      config.setup()
      assert.are.equal(false, config.get('flash.scroll_to_changes'))
    end)

    it('should allow enabling scroll_to_changes', function()
      config.setup({ flash = { scroll_to_changes = true } })
      assert.are.equal(true, config.get('flash.scroll_to_changes'))
    end)
  end)

  describe('claude provider', function()
    it('should have default cmd with acceptEdits', function()
      config.setup()
      local claude_config = config.get_provider_config('claude')
      assert.is_not_nil(claude_config.cmd)
      assert.is_true(claude_config.cmd:match('acceptEdits') ~= nil)
    end)

    it('should allow custom cmd with flags', function()
      config.setup({
        providers = {
          claude = {
            cmd = 'claude --permission-mode plan',
          },
        },
      })
      local claude_config = config.get_provider_config('claude')
      assert.are.equal('claude --permission-mode plan', claude_config.cmd)
    end)
  end)
end)
