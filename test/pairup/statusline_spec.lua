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

      -- Need to wait for vim.schedule to inject pairup_indicator
      vim.wait(100, function()
        return vim.o.statusline:match('pairup_indicator') ~= nil
      end)

      assert.truthy(vim.o.statusline:match('pairup_indicator'))
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
      vim.g.pairup_indicator = '[C]'
      local instance = setmetatable({}, { __index = component_module })
      assert.equals('[C]', instance:update_status())
    end)

    it('should return indicator with progress', function()
      vim.g.pairup_indicator = '[C:██████████] ready'
      local instance = setmetatable({}, { __index = component_module })
      assert.equals('[C:██████████] ready', instance:update_status())
    end)
  end)
end)
