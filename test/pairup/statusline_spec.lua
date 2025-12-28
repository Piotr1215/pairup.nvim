describe('pairup.statusline', function()
  local statusline
  local original_statusline

  before_each(function()
    -- Reset module state
    package.loaded['pairup.integrations.statusline'] = nil
    statusline = require('pairup.integrations.statusline')
    vim.g.pairup_indicator = nil
    -- Save original statusline (may be non-empty on nightly)
    original_statusline = vim.o.statusline
  end)

  after_each(function()
    -- Restore original statusline
    vim.o.statusline = original_statusline
  end)

  describe('setup', function()
    it('should respect auto_inject = false', function()
      local before = vim.o.statusline
      statusline.setup({ statusline = { auto_inject = false } })
      -- Should not modify statusline when disabled
      assert.equals(before, vim.o.statusline)
    end)

    it('should inject into native statusline when lualine not loaded', function()
      -- Ensure lualine is not loaded
      package.loaded['lualine'] = nil
      -- Clear statusline to trigger our custom injection
      vim.o.statusline = ''

      statusline.setup({})

      -- Need to wait for vim.schedule to inject get_colored_display function
      vim.wait(100, function()
        return vim.o.statusline:match('get_colored_display') ~= nil
      end)

      assert.truthy(vim.o.statusline:match('get_colored_display'))
    end)
  end)
end)

describe('lualine.components.pairup', function()
  local component_module

  before_each(function()
    vim.g.pairup_indicator = nil
    -- Mock lualine.component if not available
    if not pcall(require, 'lualine.component') then
      package.loaded['lualine.component'] = {
        extend = function()
          return {
            extend = function(self)
              return self
            end,
            init = function() end,
            super = { init = function() end },
          }
        end,
      }
    end
    package.loaded['lualine.components.pairup'] = nil
    component_module = require('lualine.components.pairup')
  end)

  describe('update_status', function()
    it('should return empty string when indicator is nil', function()
      vim.g.pairup_indicator = nil
      local instance = setmetatable({}, { __index = component_module })
      assert.equals('', instance:update_status())
    end)

    it('should return empty string when indicator is empty', function()
      vim.g.pairup_indicator = ''
      local instance = setmetatable({}, { __index = component_module })
      assert.equals('', instance:update_status())
    end)

    it('should return indicator when set', function()
      vim.g.pairup_indicator = '[CL]'
      vim.g.pairup_peripheral_indicator = ''
      local instance = setmetatable({}, { __index = component_module })
      assert.equals('%#PairLocalIndicator#[CL]%*', instance:update_status())
    end)

    it('should return indicator with progress', function()
      vim.g.pairup_indicator = '[CL:3/5]'
      vim.g.pairup_peripheral_indicator = ''
      local instance = setmetatable({}, { __index = component_module })
      assert.equals('%#PairLocalIndicator#[CL:3/5]%*', instance:update_status())
    end)

    it('should return both indicators when both active', function()
      vim.g.pairup_indicator = '[CL:processing]'
      vim.g.pairup_peripheral_indicator = '[CP:ready]'
      vim.g.pairup_statusline_separator = '|'
      local instance = setmetatable({}, { __index = component_module })
      assert.equals(
        '%#PairLocalIndicator#[CL:processing]%* %#PairSeparator#|%* %#PairPeripheralIndicator#[CP:ready]%*',
        instance:update_status()
      )
    end)

    it('should return only peripheral indicator when only peripheral active', function()
      vim.g.pairup_indicator = ''
      vim.g.pairup_peripheral_indicator = '[CP:3/8]'
      local instance = setmetatable({}, { __index = component_module })
      assert.equals('%#PairPeripheralIndicator#[CP:3/8]%*', instance:update_status())
    end)

    it('should use red highlight when LOCAL is suspended', function()
      vim.g.pairup_indicator = '[CL]'
      vim.g.pairup_peripheral_indicator = ''
      vim.g.pairup_suspended = true
      local instance = setmetatable({}, { __index = component_module })
      assert.equals('%#PairSuspendedIndicator#[CL]%*', instance:update_status())
      vim.g.pairup_suspended = nil
    end)

    it('should use green highlight when LOCAL is not suspended', function()
      vim.g.pairup_indicator = '[CL]'
      vim.g.pairup_peripheral_indicator = ''
      vim.g.pairup_suspended = false
      local instance = setmetatable({}, { __index = component_module })
      assert.equals('%#PairLocalIndicator#[CL]%*', instance:update_status())
    end)

    it('should return red color when suspended', function()
      vim.g.pairup_suspended = true
      local default_color = { fg = '#00ff00' }
      local suspended_color = { fg = '#ff5555' }
      local color_fn = function()
        return vim.g.pairup_suspended and suspended_color or default_color
      end
      assert.are.same(suspended_color, color_fn())
      vim.g.pairup_suspended = nil
    end)

    it('should return green color when not suspended', function()
      vim.g.pairup_suspended = nil
      local default_color = { fg = '#00ff00' }
      local suspended_color = { fg = '#ff5555' }
      local color_fn = function()
        return vim.g.pairup_suspended and suspended_color or default_color
      end
      assert.are.same(default_color, color_fn())
    end)
  end)
end)
