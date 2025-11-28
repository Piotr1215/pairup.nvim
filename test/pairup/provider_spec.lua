describe('pairup.providers.claude', function()
  local claude
  local config
  local stopinsert_called = false

  before_each(function()
    stopinsert_called = false

    -- Reset modules
    package.loaded['pairup.providers.claude'] = nil
    package.loaded['pairup.config'] = nil
    package.loaded['pairup.providers'] = nil
    package.loaded['pairup.utils.indicator'] = nil

    -- Mock indicator
    package.loaded['pairup.utils.indicator'] = {
      setup = function() end,
      update = function() end,
    }

    -- Store original vim.cmd
    local original_cmd = vim.cmd

    -- Mock vim.cmd to track stopinsert calls
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.cmd = function(cmd_str)
      if type(cmd_str) == 'string' then
        if cmd_str:match('^%s*stopinsert') then
          stopinsert_called = true
          return
        end
        if cmd_str:match('^%s*startinsert') then
          return
        end
        if cmd_str:match('^%s*wincmd') then
          return
        end
      end
      return original_cmd(cmd_str)
    end

    -- Mock vim.fn.termopen
    local original_fn = vim.fn
    vim.fn = setmetatable({
      termopen = function()
        return 999 -- fake job_id
      end,
      exepath = function(cmd)
        return cmd == 'claude' and '/mock/claude' or ''
      end,
    }, { __index = original_fn })
  end)

  describe('start', function()
    it('should call stopinsert when auto_insert is false', function()
      -- Setup config with auto_insert = false (default)
      config = require('pairup.config')
      config.setup({ terminal = { auto_insert = false } })

      -- Mock git
      package.loaded['pairup.utils.git'] = {
        get_root = function()
          return nil
        end,
      }

      claude = require('pairup.providers.claude')
      claude.start()

      assert.is_true(stopinsert_called, 'stopinsert should be called when auto_insert is false')
    end)

    it('should NOT call stopinsert when auto_insert is true', function()
      -- Setup config with auto_insert = true
      config = require('pairup.config')
      config.setup({ terminal = { auto_insert = true } })

      -- Mock git
      package.loaded['pairup.utils.git'] = {
        get_root = function()
          return nil
        end,
      }

      claude = require('pairup.providers.claude')
      claude.start()

      assert.is_false(stopinsert_called, 'stopinsert should NOT be called when auto_insert is true')
    end)
  end)

  describe('toggle', function()
    it('should call stopinsert when showing terminal with auto_insert false', function()
      -- Setup config with auto_insert = false
      config = require('pairup.config')
      config.setup({ terminal = { auto_insert = false, split_width = 0.4, split_position = 'left' } })

      -- Mock git
      package.loaded['pairup.utils.git'] = {
        get_root = function()
          return nil
        end,
      }

      claude = require('pairup.providers.claude')

      -- Create a mock terminal buffer (simulate existing but hidden terminal)
      local buf = vim.api.nvim_create_buf(true, false)
      vim.b[buf].is_pairup_assistant = true
      vim.b[buf].provider = 'claude'
      vim.b[buf].terminal_job_id = 999
      vim.g.pairup_terminal_buf = buf
      vim.g.pairup_terminal_job = 999

      -- Reset tracking
      stopinsert_called = false

      -- Toggle should show the terminal
      claude.toggle()

      assert.is_true(stopinsert_called, 'stopinsert should be called when toggling terminal with auto_insert false')

      -- Cleanup
      vim.api.nvim_buf_delete(buf, { force = true })
      vim.g.pairup_terminal_buf = nil
      vim.g.pairup_terminal_job = nil
    end)
  end)
end)
