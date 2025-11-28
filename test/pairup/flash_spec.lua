describe('pairup.utils.flash', function()
  local flash

  before_each(function()
    -- Reset modules
    package.loaded['pairup.utils.flash'] = nil

    -- Clear highlight before each test
    vim.api.nvim_set_hl(0, 'PairupFlash', {})
  end)

  describe('highlight setup', function()
    it('should set dark theme highlight when background is dark', function()
      vim.o.background = 'dark'

      flash = require('pairup.utils.flash')

      local hl = vim.api.nvim_get_hl(0, { name = 'PairupFlash' })
      assert.is_not_nil(hl.bg)
    end)

    it('should set light theme highlight when background is light', function()
      vim.o.background = 'light'

      flash = require('pairup.utils.flash')

      local hl = vim.api.nvim_get_hl(0, { name = 'PairupFlash' })
      assert.is_not_nil(hl.bg)

      -- Restore
      vim.o.background = 'dark'
    end)

    it('should not override user-defined highlight', function()
      -- User defines custom highlight before requiring module
      vim.api.nvim_set_hl(0, 'PairupFlash', { bg = '#00ff00' })

      flash = require('pairup.utils.flash')

      local hl = vim.api.nvim_get_hl(0, { name = 'PairupFlash' })
      -- Should preserve user's green color (0x00ff00 = 65280)
      assert.are.equal(65280, hl.bg)
    end)
  end)

  describe('snapshot', function()
    it('should store buffer content', function()
      flash = require('pairup.utils.flash')

      local bufnr = vim.api.nvim_create_buf(true, false)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'line 1', 'line 2' })

      -- Create a temp file to get mtime
      local tmpfile = vim.fn.tempname()
      vim.fn.writefile({ 'test' }, tmpfile)
      vim.api.nvim_buf_set_name(bufnr, tmpfile)

      flash.snapshot(bufnr)

      -- Snapshot should be stored (we can't directly access it, but clear should work)
      flash.clear(bufnr)

      vim.api.nvim_buf_delete(bufnr, { force = true })
      vim.fn.delete(tmpfile)
    end)
  end)

  describe('clear', function()
    it('should clear snapshot for buffer', function()
      flash = require('pairup.utils.flash')

      local bufnr = vim.api.nvim_create_buf(true, false)

      -- Should not error on clearing non-existent snapshot
      flash.clear(bufnr)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)
end)
