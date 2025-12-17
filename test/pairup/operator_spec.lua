describe('pairup.operator', function()
  local operator

  before_each(function()
    -- Reset modules
    package.loaded['pairup.operator'] = nil
    package.loaded['pairup.config'] = nil

    -- Mock config
    package.loaded['pairup.config'] = {
      get = function(key)
        if key == 'inline.markers.command' then
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
      assert.are.equal('cc: refactor this <- ', lines[1])
      assert.are.equal('function hello()', lines[2])

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('should use custom marker from config', function()
      -- Override config
      package.loaded['pairup.config'] = {
        get = function(key)
          if key == 'inline.markers.command' then
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
      assert.are.equal('CLAUDE: fix this <- ', lines[1])

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

    it('should include scope hint when provided', function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'test line' })

      operator.insert_marker(1, nil, 'line')

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      assert.are.equal('cc: <line> ', lines[1])

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('should include scope hint with context', function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'test line' })

      operator.insert_marker(1, 'some text', 'paragraph')

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      assert.are.equal('cc: <paragraph> some text <- ', lines[1])

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('should handle selection scope', function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'test line' })

      operator.insert_marker(1, 'selected', 'selection')

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      assert.are.equal('cc: <selection> selected <- ', lines[1])

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('should insert constitution marker when marker_type is constitution', function()
      -- Override config to include constitution marker
      package.loaded['pairup.config'] = {
        get = function(key)
          if key == 'inline.markers.command' then
            return 'cc:'
          elseif key == 'inline.markers.constitution' then
            return 'cc!:'
          end
          return nil
        end,
      }
      package.loaded['pairup.operator'] = nil
      operator = require('pairup.operator')

      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'test line' })

      operator.insert_marker(1, nil, 'line', 'constitution')

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      assert.are.equal('cc!: <line> ', lines[1])

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('should insert plan marker when marker_type is plan', function()
      -- Override config to include plan marker
      package.loaded['pairup.config'] = {
        get = function(key)
          if key == 'inline.markers.command' then
            return 'cc:'
          elseif key == 'inline.markers.plan' then
            return 'ccp:'
          end
          return nil
        end,
      }
      package.loaded['pairup.operator'] = nil
      operator = require('pairup.operator')

      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'test line' })

      operator.insert_marker(1, nil, 'line', 'plan')

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      assert.are.equal('ccp: <line> ', lines[1])

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

    it('should detect paragraph scope from motion', function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'paragraph text' })

      vim.api.nvim_buf_set_mark(bufnr, '[', 1, 0, {})
      vim.api.nvim_buf_set_mark(bufnr, ']', 1, 0, {})

      -- Simulate ip motion
      operator._last_motion = 'ip'
      operator.operatorfunc('line')

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      assert.are.equal('cc: <paragraph> ', lines[1])

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('should detect word scope from motion', function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'word here' })

      vim.api.nvim_buf_set_mark(bufnr, '[', 1, 0, {})
      vim.api.nvim_buf_set_mark(bufnr, ']', 1, 0, {})

      operator._last_motion = 'iw'
      operator.operatorfunc('char')

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      assert.are.equal('cc: <word> ', lines[1])

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('should detect single line scope', function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'single line' })

      vim.api.nvim_buf_set_mark(bufnr, '[', 1, 0, {})
      vim.api.nvim_buf_set_mark(bufnr, ']', 1, 0, {})

      operator._last_motion = nil
      operator.operatorfunc('line')

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      assert.are.equal('cc: <line> ', lines[1])

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('should detect multiple lines scope', function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'line 1', 'line 2', 'line 3' })

      vim.api.nvim_buf_set_mark(bufnr, '[', 1, 0, {})
      vim.api.nvim_buf_set_mark(bufnr, ']', 3, 0, {})

      operator._last_motion = nil
      operator.operatorfunc('line')

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      assert.are.equal('cc: <lines> ', lines[1])

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('should clear last_motion after use', function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'test' })

      vim.api.nvim_buf_set_mark(bufnr, '[', 1, 0, {})
      vim.api.nvim_buf_set_mark(bufnr, ']', 1, 0, {})

      operator._last_motion = 'ap'
      operator.operatorfunc('line')

      assert.is_nil(operator._last_motion)

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

    it('should create gC! keymap for constitution marker', function()
      operator.setup()

      local nmaps = vim.api.nvim_get_keymap('n')
      local found_gC_bang = false
      for _, map in ipairs(nmaps) do
        if map.lhs == 'gC!' then
          found_gC_bang = true
          break
        end
      end
      assert.is_true(found_gC_bang, 'gC! keymap should exist for constitution marker')
    end)

    it('should create gC? keymap for plan marker', function()
      operator.setup()

      local nmaps = vim.api.nvim_get_keymap('n')
      local found_gC_question = false
      for _, map in ipairs(nmaps) do
        if map.lhs == 'gC?' then
          found_gC_question = true
          break
        end
      end
      assert.is_true(found_gC_question, 'gC? keymap should exist for plan marker')
    end)
  end)
end)
