describe('pairup.peripheral', function()
  local peripheral

  before_each(function()
    -- Reset modules
    package.loaded['pairup.peripheral'] = nil
    package.loaded['pairup.config'] = nil
    package.loaded['pairup.utils.git'] = nil
    package.loaded['pairup.utils.indicator'] = nil

    -- Mock indicator
    package.loaded['pairup.utils.indicator'] = {
      setup = function() end,
      update = function() end,
    }

    -- Initialize config
    local config = require('pairup.config')
    config.setup({
      providers = {
        claude = { cmd = 'claude' },
      },
    })

    -- Mock git module
    package.loaded['pairup.utils.git'] = {
      get_root = function()
        return '/tmp/test-repo'
      end,
    }

    peripheral = require('pairup.peripheral')
  end)

  describe('module loading', function()
    it('loads successfully', function()
      assert.is_not_nil(peripheral)
    end)

    it('exports expected functions', function()
      assert.is_function(peripheral.setup_worktree)
      assert.is_function(peripheral.spawn)
      assert.is_function(peripheral.stop)
      assert.is_function(peripheral.toggle)
      assert.is_function(peripheral.send_message)
      assert.is_function(peripheral.send_diff)
      assert.is_function(peripheral.is_running)
      assert.is_function(peripheral.find_peripheral)
    end)
  end)

  describe('is_running', function()
    it('returns falsy when not spawned', function()
      vim.g.pairup_peripheral_buf = nil
      assert.is_falsy(peripheral.is_running())
    end)

    it('returns false when buffer is invalid', function()
      vim.g.pairup_peripheral_buf = 999999
      assert.is_false(peripheral.is_running())
    end)
  end)

  describe('find_peripheral', function()
    it('returns nil when not running', function()
      vim.g.pairup_peripheral_buf = nil
      vim.g.pairup_peripheral_job = nil

      local buf, win, job = peripheral.find_peripheral()
      assert.is_nil(buf)
      assert.is_nil(win)
      assert.is_nil(job)
    end)
  end)

  describe('send_message', function()
    it('returns false when not running', function()
      vim.g.pairup_peripheral_buf = nil
      local result = peripheral.send_message('test')
      assert.is_false(result)
    end)
  end)

  describe('send_diff', function()
    it('returns false when not running', function()
      vim.g.pairup_peripheral_buf = nil
      local result = peripheral.send_diff()
      assert.is_false(result)
    end)
  end)
end)
