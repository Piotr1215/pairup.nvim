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

  describe('highlight_changes', function()
    it('should return nil first_line when no snapshot exists', function()
      flash = require('pairup.utils.flash')

      local bufnr = vim.api.nvim_create_buf(true, false)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'line 1' })

      local count, first_line = flash.highlight_changes(bufnr)

      assert.is_nil(count)
      assert.is_nil(first_line)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('should return 0 count and nil first_line when no changes', function()
      flash = require('pairup.utils.flash')

      local bufnr = vim.api.nvim_create_buf(true, false)
      local tmpfile = vim.fn.tempname()
      vim.fn.writefile({ 'line 1', 'line 2' }, tmpfile)
      vim.api.nvim_buf_set_name(bufnr, tmpfile)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'line 1', 'line 2' })

      flash.snapshot(bufnr)

      -- No changes - same content
      local count, first_line = flash.highlight_changes(bufnr)

      assert.are.equal(0, count)
      assert.is_nil(first_line)

      vim.api.nvim_buf_delete(bufnr, { force = true })
      vim.fn.delete(tmpfile)
    end)

    it('should return first changed line number', function()
      flash = require('pairup.utils.flash')

      local bufnr = vim.api.nvim_create_buf(true, false)
      local tmpfile = vim.fn.tempname()
      vim.fn.writefile({ 'line 1', 'line 2', 'line 3' }, tmpfile)
      vim.api.nvim_buf_set_name(bufnr, tmpfile)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'line 1', 'line 2', 'line 3' })

      flash.snapshot(bufnr)

      -- Change line 2 and 3
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'line 1', 'modified 2', 'modified 3' })

      local count, first_line = flash.highlight_changes(bufnr)

      assert.is_true(count >= 1)
      assert.are.equal(2, first_line) -- First changed line is 2

      vim.api.nvim_buf_delete(bufnr, { force = true })
      vim.fn.delete(tmpfile)
    end)

    it('should return first line when change is at beginning', function()
      flash = require('pairup.utils.flash')

      local bufnr = vim.api.nvim_create_buf(true, false)
      local tmpfile = vim.fn.tempname()
      vim.fn.writefile({ 'line 1', 'line 2' }, tmpfile)
      vim.api.nvim_buf_set_name(bufnr, tmpfile)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'line 1', 'line 2' })

      flash.snapshot(bufnr)

      -- Change line 1
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'modified 1', 'line 2' })

      local count, first_line = flash.highlight_changes(bufnr)

      assert.is_true(count >= 1)
      assert.are.equal(1, first_line) -- First line changed

      vim.api.nvim_buf_delete(bufnr, { force = true })
      vim.fn.delete(tmpfile)
    end)
  end)
end)
