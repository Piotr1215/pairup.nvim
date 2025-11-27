describe('pairup.operator', function()
  local operator

  before_each(function()
    -- Reset modules
    package.loaded['pairup.operator'] = nil
    package.loaded['pairup.config'] = nil

    -- Mock config
    package.loaded['pairup.config'] = {
      get = function(key)
        if key == 'inline.cc_marker' then
          return 'cc:'
        end
        return nil
      end,
    }

    operator = require('pairup.operator')
  end)

  describe('insert_marker', function()
    it('should insert cc: marker above the line', function()
      -- Create a test buffer
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        'function hello()',
        '  print("world")',
        'end',
      })

      -- Insert marker at line 1 with context
      operator.insert_marker(1, 'refactor this')

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

      assert.are.equal(4, #lines)
      assert.are.equal('cc: refactor this', lines[1])
      assert.are.equal('function hello()', lines[2])

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('should use custom marker from config', function()
      -- Override config
      package.loaded['pairup.config'] = {
        get = function(key)
          if key == 'inline.cc_marker' then
            return 'CLAUDE:'
          end
          return nil
        end,
      }
      package.loaded['pairup.operator'] = nil
      operator = require('pairup.operator')

      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'test line' })

      operator.insert_marker(1, 'fix this')

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      assert.are.equal('CLAUDE: fix this', lines[1])

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('should insert marker without context', function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'single line' })

      operator.insert_marker(1, nil)

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      assert.are.equal(2, #lines)
      assert.are.equal('cc: ', lines[1])
      assert.are.equal('single line', lines[2])

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe('operatorfunc', function()
    it('should be callable with line type', function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'line 1', 'line 2' })

      -- Set marks for operatorfunc
      vim.api.nvim_buf_set_mark(bufnr, '[', 1, 0, {})
      vim.api.nvim_buf_set_mark(bufnr, ']', 2, 0, {})

      -- Should not error
      assert.has_no.errors(function()
        operator.operatorfunc('line')
      end)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe('setup', function()
    it('should create keymaps with default key', function()
      operator.setup()

      -- Check that keymaps exist
      local nmaps = vim.api.nvim_get_keymap('n')
      local found_gC = false
      for _, map in ipairs(nmaps) do
        if map.lhs == 'gC' then
          found_gC = true
          break
        end
      end
      assert.is_true(found_gC, 'gC keymap should exist in normal mode')
    end)

    it('should allow custom key override', function()
      operator.setup({ key = 'gP' })

      local nmaps = vim.api.nvim_get_keymap('n')
      local found_gP = false
      for _, map in ipairs(nmaps) do
        if map.lhs == 'gP' then
          found_gP = true
          break
        end
      end
      assert.is_true(found_gP, 'Custom gP keymap should exist')
    end)
  end)
end)
