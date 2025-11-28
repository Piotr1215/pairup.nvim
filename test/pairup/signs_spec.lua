describe('pairup.signs', function()
  local signs

  before_each(function()
    -- Reset modules
    package.loaded['pairup.signs'] = nil
    package.loaded['pairup.config'] = nil
    package.loaded['pairup.providers'] = nil

    -- Mock config
    package.loaded['pairup.config'] = {
      get = function(key)
        if key == 'inline.cc_marker' then
          return 'cc:'
        elseif key == 'inline.uu_marker' then
          return 'uu:'
        end
        return nil
      end,
    }

    -- Mock providers (tests call update() directly, autocmd checks terminal)
    package.loaded['pairup.providers'] = {
      find_terminal = function()
        return nil -- No terminal in tests, autocmd won't fire
      end,
    }

    signs = require('pairup.signs')
  end)

  describe('setup', function()
    it('should define PairupCC sign', function()
      signs.setup()

      local defined = vim.fn.sign_getdefined('PairupCC')
      assert.are.equal(1, #defined)
      assert.are.equal('PairupCC', defined[1].name)
    end)

    it('should define PairupUU sign', function()
      signs.setup()

      local defined = vim.fn.sign_getdefined('PairupUU')
      assert.are.equal(1, #defined)
      assert.are.equal('PairupUU', defined[1].name)
    end)
  end)

  describe('update', function()
    it('should place CC sign on lines with cc: marker', function()
      signs.setup()

      local bufnr = vim.api.nvim_create_buf(true, false)
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        'cc: fix this function',
        'function broken()',
        'end',
      })

      signs.update(bufnr)

      local placed = vim.fn.sign_getplaced(bufnr, { group = 'pairup_markers' })
      assert.are.equal(1, #placed)
      assert.are.equal(1, #placed[1].signs)
      assert.are.equal('PairupCC', placed[1].signs[1].name)
      assert.are.equal(1, placed[1].signs[1].lnum)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('should place UU sign on lines with uu: marker', function()
      signs.setup()

      local bufnr = vim.api.nvim_create_buf(true, false)
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        'some code',
        'uu: what should this return?',
        'more code',
      })

      signs.update(bufnr)

      local placed = vim.fn.sign_getplaced(bufnr, { group = 'pairup_markers' })
      assert.are.equal(1, #placed)
      assert.are.equal(1, #placed[1].signs)
      assert.are.equal('PairupUU', placed[1].signs[1].name)
      assert.are.equal(2, placed[1].signs[1].lnum)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('should handle multiple markers in same buffer', function()
      signs.setup()

      local bufnr = vim.api.nvim_create_buf(true, false)
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        'cc: refactor',
        'function one()',
        'end',
        'uu: is this correct?',
        'function two()',
        'end',
        'cc: optimize',
      })

      signs.update(bufnr)

      local placed = vim.fn.sign_getplaced(bufnr, { group = 'pairup_markers' })
      assert.are.equal(1, #placed)
      assert.are.equal(3, #placed[1].signs)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('should handle indented markers', function()
      signs.setup()

      local bufnr = vim.api.nvim_create_buf(true, false)
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        'function test()',
        '  cc: fix this',
        '  broken_code()',
        'end',
      })

      signs.update(bufnr)

      local placed = vim.fn.sign_getplaced(bufnr, { group = 'pairup_markers' })
      assert.are.equal(1, #placed)
      assert.are.equal(1, #placed[1].signs)
      assert.are.equal(2, placed[1].signs[1].lnum)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe('clear', function()
    it('should remove all signs from buffer', function()
      signs.setup()

      local bufnr = vim.api.nvim_create_buf(true, false)
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        'cc: marker 1',
        'cc: marker 2',
      })

      signs.update(bufnr)

      -- Verify signs are placed
      local placed = vim.fn.sign_getplaced(bufnr, { group = 'pairup_markers' })
      assert.are.equal(2, #placed[1].signs)

      -- Clear signs
      signs.clear(bufnr)

      -- Verify signs are removed
      placed = vim.fn.sign_getplaced(bufnr, { group = 'pairup_markers' })
      assert.are.equal(0, #placed[1].signs)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)
end)
