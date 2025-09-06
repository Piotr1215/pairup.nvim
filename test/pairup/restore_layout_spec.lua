local helpers = require('test.helpers')

describe('pairup restore layout', function()
  local pairup
  local config
  local claude_provider
  local original_columns

  before_each(function()
    -- Set test mode
    vim.g.pairup_test_mode = true

    -- Store original columns
    original_columns = vim.o.columns

    -- Set a fixed column width for testing
    vim.o.columns = 100

    -- Clear modules
    for k, _ in pairs(package.loaded) do
      if k:match('^pairup') then
        package.loaded[k] = nil
      end
    end

    -- Mock vim.fn.input to prevent blocking
    vim.fn.input = function()
      return ''
    end

    -- Load modules
    pairup = require('pairup')
    config = require('pairup.config')
    claude_provider = require('pairup.providers.claude')

    -- Setup with default config
    pairup.setup({
      terminal = {
        split_width = 0.4,
        split_position = 'left',
      },
    })
  end)

  after_each(function()
    -- Restore original columns
    vim.o.columns = original_columns

    -- Clean up any created buffers
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_valid(buf) and vim.b[buf].is_pairup_assistant then
        pcall(vim.api.nvim_buf_delete, buf, { force = true })
      end
    end

    -- Clean up test mode
    vim.g.pairup_test_mode = nil
  end)

  describe('restore_layout', function()
    it('should restore window to configured width', function()
      -- Create a mock Claude terminal window
      local buf = vim.api.nvim_create_buf(false, true)
      vim.b[buf].is_pairup_assistant = true
      vim.b[buf].provider = 'claude'
      vim.b[buf].terminal_job_id = 999

      -- Create a vertical split with the buffer
      vim.cmd('vsplit')
      local win = vim.api.nvim_get_current_win()
      vim.api.nvim_win_set_buf(win, buf)

      -- Manually resize to a different width
      vim.api.nvim_win_set_width(win, 20)
      assert.equals(20, vim.api.nvim_win_get_width(win))

      -- Switch to another window
      vim.cmd('wincmd p')

      -- Call restore layout
      local result = claude_provider.restore_layout()
      assert.is_true(result)

      -- Check that window is resized to 40% of 100 columns = 40
      assert.equals(40, vim.api.nvim_win_get_width(win))
    end)

    it('should handle missing Claude window gracefully', function()
      -- No Claude window exists
      local result = claude_provider.restore_layout()
      assert.is_false(result)
    end)

    it('should use default width if config not set', function()
      -- Reset config without terminal.split_width
      config.values.terminal.split_width = nil

      -- Create a mock Claude terminal window
      local buf = vim.api.nvim_create_buf(false, true)
      vim.b[buf].is_pairup_assistant = true
      vim.b[buf].provider = 'claude'
      vim.b[buf].terminal_job_id = 999

      -- Create a vertical split with the buffer
      vim.cmd('vsplit')
      local win = vim.api.nvim_get_current_win()
      vim.api.nvim_win_set_buf(win, buf)

      -- Manually resize to a different width
      vim.api.nvim_win_set_width(win, 20)

      -- Switch to another window
      vim.cmd('wincmd p')

      -- Call restore layout - should use default 0.4
      local result = claude_provider.restore_layout()
      assert.is_true(result)

      -- Check that window is resized to default 40% of 100 columns = 40
      assert.equals(40, vim.api.nvim_win_get_width(win))
    end)

    it('should not resize if already at correct width', function()
      -- Create a mock Claude terminal window
      local buf = vim.api.nvim_create_buf(false, true)
      vim.b[buf].is_pairup_assistant = true
      vim.b[buf].provider = 'claude'
      vim.b[buf].terminal_job_id = 999

      -- Create a vertical split with the buffer
      vim.cmd('vsplit')
      local win = vim.api.nvim_get_current_win()
      vim.api.nvim_win_set_buf(win, buf)

      -- Set to correct width
      vim.api.nvim_win_set_width(win, 40)

      -- Switch to another window
      vim.cmd('wincmd p')

      -- Call restore layout
      local result = claude_provider.restore_layout()
      assert.is_true(result)

      -- Width should remain unchanged
      assert.equals(40, vim.api.nvim_win_get_width(win))
    end)

    it('should handle custom split width from config', function()
      -- Set custom split width
      config.set('terminal.split_width', 0.6)

      -- Create a mock Claude terminal window
      local buf = vim.api.nvim_create_buf(false, true)
      vim.b[buf].is_pairup_assistant = true
      vim.b[buf].provider = 'claude'
      vim.b[buf].terminal_job_id = 999

      -- Create a vertical split with the buffer
      vim.cmd('vsplit')
      local win = vim.api.nvim_get_current_win()
      vim.api.nvim_win_set_buf(win, buf)

      -- Manually resize to a different width
      vim.api.nvim_win_set_width(win, 20)

      -- Switch to another window
      vim.cmd('wincmd p')

      -- Call restore layout
      local result = claude_provider.restore_layout()
      assert.is_true(result)

      -- Check that window is resized to 60% of 100 columns = 60
      assert.equals(60, vim.api.nvim_win_get_width(win))
    end)
  end)

  describe('PairupRestoreLayout command', function()
    it('should call restore_layout through main module', function()
      -- Create a mock Claude terminal window
      local buf = vim.api.nvim_create_buf(false, true)
      vim.b[buf].is_pairup_assistant = true
      vim.b[buf].provider = 'claude'
      vim.b[buf].terminal_job_id = 999

      -- Create a vertical split with the buffer
      vim.cmd('vsplit')
      local win = vim.api.nvim_get_current_win()
      vim.api.nvim_win_set_buf(win, buf)

      -- Set the current provider
      local providers = require('pairup.providers')
      providers.current = claude_provider

      -- Manually resize to a different width
      vim.api.nvim_win_set_width(win, 25)

      -- Switch to another window
      vim.cmd('wincmd p')

      -- Call through main module
      pairup.restore_layout()

      -- Check that window is resized to 40% of 100 columns = 40
      assert.equals(40, vim.api.nvim_win_get_width(win))
    end)

    it('should handle no active provider gracefully', function()
      -- Ensure no current provider
      local providers = require('pairup.providers')
      providers.current = nil

      -- Should not error
      assert.has_no.errors(function()
        pairup.restore_layout()
      end)
    end)
  end)
end)
