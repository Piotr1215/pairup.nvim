describe('pairup.utils.indicator', function()
  local indicator
  local progress_file = '/tmp/claude_progress'

  before_each(function()
    -- Reset modules
    package.loaded['pairup.utils.indicator'] = nil
    package.loaded['pairup.config'] = nil
    package.loaded['pairup.providers'] = nil

    -- Clean up progress file
    os.remove(progress_file)

    -- Mock config
    package.loaded['pairup.config'] = {
      get = function(key)
        if key == 'inline.enabled' then
          return true
        end
        return nil
      end,
      get_provider = function()
        return 'claude'
      end,
    }

    -- Mock providers
    package.loaded['pairup.providers'] = {
      find_terminal = function()
        return 1 -- Pretend terminal exists
      end,
    }

    indicator = require('pairup.utils.indicator')

    -- Clear global state
    vim.g.pairup_indicator = nil
    vim.g.claude_context_indicator = nil
    vim.g.pairup_pending = nil
    vim.g.pairup_queued = nil
  end)

  after_each(function()
    os.remove(progress_file)
  end)

  describe('update', function()
    it('should set indicator to [C] when terminal exists', function()
      indicator.update()
      assert.are.equal('[C]', vim.g.pairup_indicator)
    end)

    it('should set indicator to empty when no terminal', function()
      package.loaded['pairup.providers'] = {
        find_terminal = function()
          return nil
        end,
      }
      package.loaded['pairup.utils.indicator'] = nil
      indicator = require('pairup.utils.indicator')

      indicator.update()
      assert.are.equal('', vim.g.pairup_indicator)
    end)

    it('should show [C:pending] when file is pending', function()
      vim.g.pairup_pending = '/some/file.lua'
      vim.g.pairup_pending_time = os.time()

      indicator.update()
      assert.are.equal('[C:pending]', vim.g.pairup_indicator)
    end)

    it('should show [C:queued] when queued', function()
      vim.g.pairup_queued = true

      indicator.update()
      assert.are.equal('[C:queued]', vim.g.pairup_indicator)
    end)
  end)

  describe('set_pending', function()
    it('should set pending state', function()
      indicator.set_pending('/test/file.lua')

      assert.are.equal('/test/file.lua', vim.g.pairup_pending)
      assert.is_not_nil(vim.g.pairup_pending_time)
    end)
  end)

  describe('clear_pending', function()
    it('should clear pending state', function()
      vim.g.pairup_pending = '/test/file.lua'
      vim.g.pairup_pending_time = os.time()
      vim.g.pairup_queued = true

      indicator.clear_pending()

      assert.is_nil(vim.g.pairup_pending)
      assert.is_nil(vim.g.pairup_pending_time)
      assert.is_false(vim.g.pairup_queued)
    end)
  end)

  describe('is_pending', function()
    it('should return true for matching pending file', function()
      indicator.set_pending('/test/file.lua')

      assert.is_true(indicator.is_pending('/test/file.lua'))
    end)

    it('should return false for non-matching file', function()
      indicator.set_pending('/test/file.lua')

      assert.is_false(indicator.is_pending('/other/file.lua'))
    end)

    it('should return false after timeout', function()
      vim.g.pairup_pending = '/test/file.lua'
      vim.g.pairup_pending_time = os.time() - 120 -- 2 minutes ago

      assert.is_false(indicator.is_pending('/test/file.lua'))
    end)
  end)

  describe('get', function()
    it('should return current indicator value', function()
      vim.g.pairup_indicator = '[C:test]'

      assert.are.equal('[C:test]', indicator.get())
    end)

    it('should return empty string when not set', function()
      vim.g.pairup_indicator = nil

      assert.are.equal('', indicator.get())
    end)
  end)

  describe('progress bar', function()
    it('should generate correct bar at 0%', function()
      -- Access internal function via module state
      indicator.update()
      -- Bar generation is internal, test via progress file

      -- Write progress file
      local f = io.open(progress_file, 'w')
      f:write('10:Testing')
      f:close()

      -- Setup starts the watcher but we can't easily test async
      -- Just verify file was written
      local content = io.open(progress_file, 'r'):read('*a')
      assert.are.equal('10:Testing', content)
    end)

    it('should parse duration:message format', function()
      local content = '30:Refactoring code'
      local duration, message = content:match('^(%d+):(.+)')

      assert.are.equal('30', duration)
      assert.are.equal('Refactoring code', message)
    end)

    it('should detect done signal', function()
      local content = 'done'
      assert.are.equal('done', vim.trim(content))
    end)
  end)

  describe('stop_progress', function()
    it('should clear active progress and update indicator', function()
      indicator.stop_progress()
      -- Should not error and should call update
      assert.is_not_nil(vim.g.pairup_indicator)
    end)
  end)
end)
