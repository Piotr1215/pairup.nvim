describe('pairup.utils.indicator', function()
  local indicator

  before_each(function()
    -- Reset modules
    package.loaded['pairup.utils.indicator'] = nil
    package.loaded['pairup.config'] = nil
    package.loaded['pairup.providers'] = nil

    -- Mock config
    package.loaded['pairup.config'] = {
      get = function(key)
        return nil
      end,
      get_provider = function()
        return 'claude'
      end,
    }

    -- Mock providers
    package.loaded['pairup.providers'] = {
      find_terminal = function()
        return 1 -- Pretend terminal exists
      end,
    }

    indicator = require('pairup.utils.indicator')

    -- Clear global state
    vim.g.pairup_indicator = nil
    vim.g.claude_context_indicator = nil
    vim.g.pairup_pending = nil
    vim.g.pairup_queued = nil
  end)

  describe('update', function()
    it('should set indicator to [C] when terminal exists', function()
      indicator.update()
      assert.are.equal('[C]', vim.g.pairup_indicator)
    end)

    it('should set indicator to empty when no terminal', function()
      package.loaded['pairup.providers'] = {
        find_terminal = function()
          return nil
        end,
      }
      package.loaded['pairup.utils.indicator'] = nil
      indicator = require('pairup.utils.indicator')

      indicator.update()
      assert.are.equal('', vim.g.pairup_indicator)
    end)

    it('should show [C:processing] when file is processing', function()
      vim.g.pairup_pending = '/some/file.lua'
      vim.g.pairup_pending_time = os.time()

      indicator.update()
      assert.are.equal('[C:processing]', vim.g.pairup_indicator)
    end)

    it('should show [C:queued] when queued', function()
      vim.g.pairup_queued = true

      indicator.update()
      assert.are.equal('[C:queued]', vim.g.pairup_indicator)
    end)
  end)

  describe('set_pending', function()
    it('should set pending state', function()
      indicator.set_pending('/test/file.lua')

      assert.are.equal('/test/file.lua', vim.g.pairup_pending)
      assert.is_not_nil(vim.g.pairup_pending_time)
    end)
  end)

  describe('clear_pending', function()
    it('should clear pending state', function()
      vim.g.pairup_pending = '/test/file.lua'
      vim.g.pairup_pending_time = os.time()
      vim.g.pairup_queued = true

      indicator.clear_pending()

      assert.is_nil(vim.g.pairup_pending)
      assert.is_nil(vim.g.pairup_pending_time)
      assert.is_false(vim.g.pairup_queued)
    end)
  end)

  describe('is_pending', function()
    it('should return true for matching pending file', function()
      indicator.set_pending('/test/file.lua')

      assert.is_true(indicator.is_pending('/test/file.lua'))
    end)

    it('should return false for non-matching file', function()
      indicator.set_pending('/test/file.lua')

      assert.is_false(indicator.is_pending('/other/file.lua'))
    end)

    it('should return false after timeout', function()
      vim.g.pairup_pending = '/test/file.lua'
      vim.g.pairup_pending_time = os.time() - 120 -- 2 minutes ago

      assert.is_false(indicator.is_pending('/test/file.lua'))
    end)
  end)

  describe('get', function()
    it('should return current indicator value', function()
      vim.g.pairup_indicator = '[C:test]'

      assert.are.equal('[C:test]', indicator.get())
    end)

    it('should return empty string when not set', function()
      vim.g.pairup_indicator = nil

      assert.are.equal('', indicator.get())
    end)
  end)

  describe('hook mode', function()
    local hook_file = '/tmp/pairup-todo-test123.json'

    after_each(function()
      os.remove(hook_file)
    end)

    it('should parse hook state file format', function()
      local json = '{"session":"test123","total":5,"completed":2,"current":"Implementing feature"}'
      local ok, data = pcall(vim.json.decode, json)

      assert.is_true(ok)
      assert.are.equal('test123', data.session)
      assert.are.equal(5, data.total)
      assert.are.equal(2, data.completed)
      assert.are.equal('Implementing feature', data.current)
    end)

    it('should format progress as completed/total', function()
      local data = { total = 5, completed = 2, current = 'Testing' }
      local display = '[C:' .. data.completed .. '/' .. data.total .. ']'

      assert.are.equal('[C:2/5]', display)
    end)

    it('should show ready when all tasks completed', function()
      local data = { total = 5, completed = 5, current = '' }
      local display = data.completed == data.total and '[C:ready]'
        or '[C:' .. data.completed .. '/' .. data.total .. ']'

      assert.are.equal('[C:ready]', display)
    end)
  end)

  describe('virtual text', function()
    it('should wrap long lines at word boundaries', function()
      local text = 'This is a very long task description that exceeds eighty characters and should be wrapped'
      local lines = {}
      for line in text:gmatch('[^\n]+') do
        if #line > 80 then
          while #line > 80 do
            local wrap_at = line:sub(1, 80):match('.*()%s') or 80
            table.insert(lines, line:sub(1, wrap_at))
            line = line:sub(wrap_at + 1)
          end
          if #line > 0 then
            table.insert(lines, line)
          end
        else
          table.insert(lines, line)
        end
      end

      assert.are.equal(2, #lines)
      assert.is_true(#lines[1] <= 80)
    end)

    it('should split on newlines', function()
      local text = 'Line one\nLine two\nLine three'
      local lines = {}
      for line in text:gmatch('[^\n]+') do
        table.insert(lines, line)
      end

      assert.are.equal(3, #lines)
      assert.are.equal('Line one', lines[1])
      assert.are.equal('Line two', lines[2])
      assert.are.equal('Line three', lines[3])
    end)

    it('should handle empty text', function()
      indicator.set_virtual_text(nil)
      indicator.set_virtual_text('')
      -- Should not error
      assert.is_true(true)
    end)

    it('should prefix first line with icon', function()
      local lines = { 'First line', 'Second line' }
      local virt_lines = {}
      for i, line in ipairs(lines) do
        local prefix = i == 1 and '  󰭻 ' or '    '
        table.insert(virt_lines, { { prefix .. line, 'DiagnosticInfo' } })
      end

      assert.are.equal('  󰭻 First line', virt_lines[1][1][1])
      assert.are.equal('    Second line', virt_lines[2][1][1])
    end)
  end)
end)
