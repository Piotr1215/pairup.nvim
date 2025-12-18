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

    it('should handle file scope', function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'test line' })

      operator.insert_marker(1, nil, 'file')

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      assert.are.equal('cc: <file> ', lines[1])

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
    it('should insert marker without scope hint (motion type unknown)', function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'test line' })
      vim.api.nvim_buf_set_mark(bufnr, '[', 1, 0, {})
      vim.api.nvim_buf_set_mark(bufnr, ']', 1, 0, {})

      operator._marker_type = 'command'
      operator.operatorfunc('line')

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      assert.are.equal('cc: ', lines[1])
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe('setup', function()
    it('should create gC operator and gCC line mapping', function()
      operator.setup()

      local nmaps = vim.api.nvim_get_keymap('n')
      local found_gC, found_gCC = false, false
      for _, map in ipairs(nmaps) do
        if map.lhs == 'gC' then
          found_gC = true
        end
        if map.lhs == 'gCC' then
          found_gCC = true
        end
      end
      assert.is_true(found_gC, 'gC operator should exist')
      assert.is_true(found_gCC, 'gCC line mapping should exist')
    end)

    it('should create g! operator for constitution marker', function()
      operator.setup()

      local nmaps = vim.api.nvim_get_keymap('n')
      local found_g_bang, found_g_bang_bang = false, false
      for _, map in ipairs(nmaps) do
        if map.lhs == 'g!' then
          found_g_bang = true
        end
        if map.lhs == 'g!!' then
          found_g_bang_bang = true
        end
      end
      assert.is_true(found_g_bang, 'g! operator should exist')
      assert.is_true(found_g_bang_bang, 'g!! line mapping should exist')
    end)

    it('should create g? operator for plan marker', function()
      operator.setup()

      local nmaps = vim.api.nvim_get_keymap('n')
      local found_g_question, found_g_question_question = false, false
      for _, map in ipairs(nmaps) do
        if map.lhs == 'g?' then
          found_g_question = true
        end
        if map.lhs == 'g??' then
          found_g_question_question = true
        end
      end
      assert.is_true(found_g_question, 'g? operator should exist')
      assert.is_true(found_g_question_question, 'g?? line mapping should exist')
    end)

    it('should create text object mappings with scope hints', function()
      operator.setup()

      local nmaps = vim.api.nvim_get_keymap('n')
      local found_gCip, found_g_bang_ip, found_g_question_ip = false, false, false
      for _, map in ipairs(nmaps) do
        if map.lhs == 'gCip' then
          found_gCip = true
        end
        if map.lhs == 'g!ip' then
          found_g_bang_ip = true
        end
        if map.lhs == 'g?ip' then
          found_g_question_ip = true
        end
      end
      assert.is_true(found_gCip, 'gCip mapping should exist')
      assert.is_true(found_g_bang_ip, 'g!ip mapping should exist')
      assert.is_true(found_g_question_ip, 'g?ip mapping should exist')
    end)

    it('should create file scope mappings', function()
      operator.setup()

      local nmaps = vim.api.nvim_get_keymap('n')
      local found_gCF, found_g_bang_F = false, false
      for _, map in ipairs(nmaps) do
        if map.lhs == 'gCF' then
          found_gCF = true
        end
        if map.lhs == 'g!F' then
          found_g_bang_F = true
        end
      end
      assert.is_true(found_gCF, 'gCF mapping should exist')
      assert.is_true(found_g_bang_F, 'g!F mapping should exist')
    end)

    it('should allow custom key overrides', function()
      operator.setup({ command_key = 'gc', constitution_key = 'gK', plan_key = 'gP' })

      local nmaps = vim.api.nvim_get_keymap('n')
      local found_gc, found_gK, found_gP = false, false, false
      for _, map in ipairs(nmaps) do
        if map.lhs == 'gc' then
          found_gc = true
        end
        if map.lhs == 'gK' then
          found_gK = true
        end
        if map.lhs == 'gP' then
          found_gP = true
        end
      end
      assert.is_true(found_gc, 'Custom gc should exist')
      assert.is_true(found_gK, 'Custom gK should exist')
      assert.is_true(found_gP, 'Custom gP should exist')
    end)
  end)
end)
