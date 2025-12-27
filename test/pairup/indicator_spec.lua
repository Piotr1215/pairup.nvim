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
    vim.g.pairup_peripheral_indicator = nil
    vim.g.pairup_peripheral_buf = nil
    vim.g.pairup_peripheral_pending = nil
    vim.g.pairup_peripheral_queued = nil
  end)

  describe('update', function()
    it('should set indicator to [CL] when terminal exists', function()
      indicator.update()
      assert.are.equal('[CL]', vim.g.pairup_indicator)
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

    it('should show [CL:processing] when file is processing', function()
      vim.g.pairup_pending = '/some/file.lua'
      vim.g.pairup_pending_time = os.time()

      indicator.update()
      assert.are.equal('[CL:processing]', vim.g.pairup_indicator)
    end)

    it('should show [CL:queued] when queued', function()
      vim.g.pairup_queued = true

      indicator.update()
      assert.are.equal('[CL:queued]', vim.g.pairup_indicator)
    end)
  end)

  describe('update_peripheral', function()
    it('should set indicator to [CP] when peripheral terminal exists', function()
      vim.g.pairup_peripheral_buf = 1

      indicator.update_peripheral()
      assert.are.equal('[CP]', vim.g.pairup_peripheral_indicator)
    end)

    it('should set indicator to empty when no peripheral terminal', function()
      vim.g.pairup_peripheral_buf = nil

      indicator.update_peripheral()
      assert.are.equal('', vim.g.pairup_peripheral_indicator)
    end)

    it('should show [CP:processing] when peripheral is processing', function()
      vim.g.pairup_peripheral_buf = 1
      vim.g.pairup_peripheral_pending = '/some/file.lua'

      indicator.update_peripheral()
      assert.are.equal('[CP:processing]', vim.g.pairup_peripheral_indicator)
    end)

    it('should show [CP:queued] when peripheral is queued', function()
      vim.g.pairup_peripheral_buf = 1
      vim.g.pairup_peripheral_queued = true

      indicator.update_peripheral()
      assert.are.equal('[CP:queued]', vim.g.pairup_peripheral_indicator)
    end)
  end)

  describe('get_display', function()
    it('should show only LOCAL when only LOCAL active', function()
      vim.g.pairup_indicator = '[CL:3/5]'
      vim.g.pairup_peripheral_indicator = ''

      assert.are.equal('[CL:3/5]', indicator.get_display())
    end)

    it('should show only PERIPHERAL when only PERIPHERAL active', function()
      vim.g.pairup_indicator = ''
      vim.g.pairup_peripheral_indicator = '[CP:ready]'

      assert.are.equal('[CP:ready]', indicator.get_display())
    end)

    it('should show both with separator when both active', function()
      vim.g.pairup_indicator = '[CL:processing]'
      vim.g.pairup_peripheral_indicator = '[CP:3/8]'

      assert.are.equal('[CL:processing] | [CP:3/8]', indicator.get_display())
    end)

    it('should use custom separator', function()
      vim.g.pairup_indicator = '[CL]'
      vim.g.pairup_peripheral_indicator = '[CP]'
      vim.g.pairup_statusline_separator = '•'

      assert.are.equal('[CL] • [CP]', indicator.get_display())
    end)

    it('should return empty when neither active', function()
      vim.g.pairup_indicator = ''
      vim.g.pairup_peripheral_indicator = ''

      assert.are.equal('', indicator.get_display())
    end)
  end)

  describe('get_colored_display', function()
    it('should use green highlight for LOCAL when not suspended', function()
      vim.g.pairup_indicator = '[CL]'
      vim.g.pairup_peripheral_indicator = ''
      vim.g.pairup_suspended = false

      assert.are.equal('%#PairLocalIndicator#[CL]%*', indicator.get_colored_display())
    end)

    it('should use red highlight for LOCAL when suspended', function()
      vim.g.pairup_indicator = '[CL]'
      vim.g.pairup_peripheral_indicator = ''
      vim.g.pairup_suspended = true

      assert.are.equal('%#PairSuspendedIndicator#[CL]%*', indicator.get_colored_display())
      vim.g.pairup_suspended = nil
    end)

    it('should use blue highlight for PERIPHERAL only', function()
      vim.g.pairup_indicator = ''
      vim.g.pairup_peripheral_indicator = '[CP:3/8]'

      assert.are.equal('%#PairPeripheralIndicator#[CP:3/8]%*', indicator.get_colored_display())
    end)

    it('should show both with suspended LOCAL', function()
      vim.g.pairup_indicator = '[CL:processing]'
      vim.g.pairup_peripheral_indicator = '[CP:ready]'
      vim.g.pairup_suspended = true
      vim.g.pairup_statusline_separator = '|'

      assert.are.equal(
        '%#PairSuspendedIndicator#[CL:processing]%* %#PairSeparator#|%* %#PairPeripheralIndicator#[CP:ready]%*',
        indicator.get_colored_display()
      )
      vim.g.pairup_suspended = nil
    end)

    it('should show both with active LOCAL', function()
      vim.g.pairup_indicator = '[CL:3/5]'
      vim.g.pairup_peripheral_indicator = '[CP:2/8]'
      vim.g.pairup_suspended = false
      vim.g.pairup_statusline_separator = '|'

      assert.are.equal(
        '%#PairLocalIndicator#[CL:3/5]%* %#PairSeparator#|%* %#PairPeripheralIndicator#[CP:2/8]%*',
        indicator.get_colored_display()
      )
    end)

    it('should return empty when neither active', function()
      vim.g.pairup_indicator = ''
      vim.g.pairup_peripheral_indicator = ''

      assert.are.equal('', indicator.get_colored_display())
    end)
  end)

  describe('get_peripheral', function()
    it('should return peripheral indicator value', function()
      vim.g.pairup_peripheral_indicator = '[CP:test]'

      assert.are.equal('[CP:test]', indicator.get_peripheral())
    end)

    it('should return empty string when not set', function()
      vim.g.pairup_peripheral_indicator = nil

      assert.are.equal('', indicator.get_peripheral())
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
      vim.g.pairup_indicator = '[CL:test]'

      assert.are.equal('[CL:test]', indicator.get())
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
      local display = '[CL:' .. data.completed .. '/' .. data.total .. ']'

      assert.are.equal('[CL:2/5]', display)
    end)

    it('should show ready when all tasks completed', function()
      local data = { total = 5, completed = 5, current = '' }
      local display = data.completed == data.total and '[CL:ready]'
        or '[CL:' .. data.completed .. '/' .. data.total .. ']'

      assert.are.equal('[CL:ready]', display)
    end)
  end)

  describe('peripheral hook mode', function()
    it('should format peripheral progress as completed/total', function()
      local data = { total = 8, completed = 3 }
      local display = '[CP:' .. data.completed .. '/' .. data.total .. ']'

      assert.are.equal('[CP:3/8]', display)
    end)

    it('should show peripheral ready when all tasks completed', function()
      local data = { total = 8, completed = 8 }
      local display = data.completed == data.total and '[CP:ready]'
        or '[CP:' .. data.completed .. '/' .. data.total .. ']'

      assert.are.equal('[CP:ready]', display)
    end)
  end)

  describe('set_peripheral_pending', function()
    it('should set peripheral pending state', function()
      vim.g.pairup_peripheral_buf = 1

      indicator.set_peripheral_pending('analyzing')

      assert.are.equal('analyzing', vim.g.pairup_peripheral_pending)
      assert.is_not_nil(vim.g.pairup_peripheral_pending_time)
      assert.are.equal('[CP:processing]', vim.g.pairup_peripheral_indicator)
    end)
  end)

  describe('clear_peripheral_pending', function()
    it('should clear peripheral pending state', function()
      vim.g.pairup_peripheral_buf = 1
      vim.g.pairup_peripheral_pending = 'analyzing'
      vim.g.pairup_peripheral_pending_time = os.time()
      vim.g.pairup_peripheral_queued = true

      indicator.clear_peripheral_pending()

      assert.is_nil(vim.g.pairup_peripheral_pending)
      assert.is_nil(vim.g.pairup_peripheral_pending_time)
      assert.is_false(vim.g.pairup_peripheral_queued)
      assert.are.equal('[CP]', vim.g.pairup_peripheral_indicator)
    end)
  end)

  describe('edge cases', function()
    it('should handle custom separator in display', function()
      vim.g.pairup_indicator = '[CL]'
      vim.g.pairup_peripheral_indicator = '[CP]'
      vim.g.pairup_statusline_separator = '•'

      assert.are.equal('[CL] • [CP]', indicator.get_display())
    end)

    it('should handle empty separator', function()
      vim.g.pairup_indicator = '[CL:3/5]'
      vim.g.pairup_peripheral_indicator = '[CP:ready]'
      vim.g.pairup_statusline_separator = ''

      assert.are.equal('[CL:3/5]  [CP:ready]', indicator.get_display())
    end)

    it('should handle nil values gracefully', function()
      vim.g.pairup_indicator = nil
      vim.g.pairup_peripheral_indicator = nil

      assert.are.equal('', indicator.get_display())
      assert.are.equal('', indicator.get())
      assert.are.equal('', indicator.get_peripheral())
    end)

    it('should prioritize queued over pending for LOCAL', function()
      package.loaded['pairup.providers'] = {
        find_terminal = function()
          return 1
        end,
      }
      package.loaded['pairup.utils.indicator'] = nil
      indicator = require('pairup.utils.indicator')

      vim.g.pairup_pending = '/test/file.lua'
      vim.g.pairup_queued = true

      indicator.update()
      assert.are.equal('[CL:queued]', vim.g.pairup_indicator)
    end)

    it('should prioritize queued over pending for PERIPHERAL', function()
      vim.g.pairup_peripheral_buf = 1
      vim.g.pairup_peripheral_pending = 'analyzing'
      vim.g.pairup_peripheral_queued = true

      indicator.update_peripheral()
      assert.are.equal('[CP:queued]', vim.g.pairup_peripheral_indicator)
    end)
  end)

  describe('state transitions', function()
    it('should timeout pending state after 60 seconds', function()
      indicator.set_pending('/test/file.lua')
      -- Simulate timeout by setting old timestamp
      vim.g.pairup_pending_time = os.time() - 61

      assert.is_false(indicator.is_pending('/test/file.lua'))
    end)

    it('should not timeout pending state within 60 seconds', function()
      indicator.set_pending('/test/file.lua')
      vim.g.pairup_pending_time = os.time() - 30

      assert.is_true(indicator.is_pending('/test/file.lua'))
    end)

    it('should clear all state on clear_pending', function()
      vim.g.pairup_pending = '/test/file.lua'
      vim.g.pairup_pending_time = os.time()
      vim.g.pairup_queued = true

      indicator.clear_pending()

      assert.is_nil(vim.g.pairup_pending)
      assert.is_nil(vim.g.pairup_pending_time)
      assert.is_false(vim.g.pairup_queued)
    end)
  end)

  describe('state machine behavior (data-driven)', function()
    -- Test state priority: queued > pending > idle (indicator.lua:224-230)
    local state_priority_cases = {
      {
        name = 'queued takes precedence over pending',
        setup = function()
          vim.g.pairup_pending = '/test.lua'
          vim.g.pairup_queued = true
        end,
        expected = '[CL:queued]',
      },
      {
        name = 'pending shows when queued is false',
        setup = function()
          vim.g.pairup_pending = '/test.lua'
          vim.g.pairup_queued = false
        end,
        expected = '[CL:processing]',
      },
      {
        name = 'idle when neither pending nor queued',
        setup = function()
          vim.g.pairup_pending = nil
          vim.g.pairup_queued = false
        end,
        expected = '[CL]',
      },
    }

    for _, case in ipairs(state_priority_cases) do
      it('LOCAL: ' .. case.name, function()
        -- Mock provider
        package.loaded['pairup.providers'] = {
          find_terminal = function()
            return 1
          end,
        }
        package.loaded['pairup.utils.indicator'] = nil
        indicator = require('pairup.utils.indicator')

        case.setup()
        indicator.update()

        assert.are.equal(case.expected, vim.g.pairup_indicator)
      end)
    end

    -- Test peripheral state priority (indicator.lua:241-248)
    local peripheral_state_cases = {
      {
        name = 'queued takes precedence',
        setup = function()
          vim.g.pairup_peripheral_buf = 1
          vim.g.pairup_peripheral_pending = 'analyzing'
          vim.g.pairup_peripheral_queued = true
        end,
        expected = '[CP:queued]',
      },
      {
        name = 'pending shows when not queued',
        setup = function()
          vim.g.pairup_peripheral_buf = 1
          vim.g.pairup_peripheral_pending = 'analyzing'
          vim.g.pairup_peripheral_queued = false
        end,
        expected = '[CP:processing]',
      },
      {
        name = 'idle when no state',
        setup = function()
          vim.g.pairup_peripheral_buf = 1
          vim.g.pairup_peripheral_pending = nil
          vim.g.pairup_peripheral_queued = false
        end,
        expected = '[CP]',
      },
    }

    for _, case in ipairs(peripheral_state_cases) do
      it('PERIPHERAL: ' .. case.name, function()
        case.setup()
        indicator.update_peripheral()

        assert.are.equal(case.expected, vim.g.pairup_peripheral_indicator)
      end)
    end
  end)

  describe('suspended state behavior (data-driven)', function()
    -- Test that suspended state changes color, not content (lualine component behavior)
    local suspended_display_cases = {
      {
        name = 'suspended LOCAL alone uses red',
        local_ind = '[CL]',
        periph_ind = '',
        suspended = true,
        expected = '%#PairSuspendedIndicator#[CL]%*',
      },
      {
        name = 'active LOCAL alone uses green',
        local_ind = '[CL]',
        periph_ind = '',
        suspended = false,
        expected = '%#PairLocalIndicator#[CL]%*',
      },
      {
        name = 'suspended LOCAL with PERIPHERAL uses red for LOCAL',
        local_ind = '[CL:3/5]',
        periph_ind = '[CP:ready]',
        suspended = true,
        expected = '%#PairSuspendedIndicator#[CL:3/5]%* %#PairSeparator#|%* %#PairPeripheralIndicator#[CP:ready]%*',
      },
      {
        name = 'active LOCAL with PERIPHERAL uses green for LOCAL',
        local_ind = '[CL:processing]',
        periph_ind = '[CP:2/8]',
        suspended = false,
        expected = '%#PairLocalIndicator#[CL:processing]%* %#PairSeparator#|%* %#PairPeripheralIndicator#[CP:2/8]%*',
      },
      {
        name = 'PERIPHERAL alone ignores suspended state',
        local_ind = '',
        periph_ind = '[CP:ready]',
        suspended = true,
        expected = '%#PairPeripheralIndicator#[CP:ready]%*',
      },
    }

    for _, case in ipairs(suspended_display_cases) do
      it(case.name, function()
        vim.g.pairup_indicator = case.local_ind
        vim.g.pairup_peripheral_indicator = case.periph_ind
        vim.g.pairup_suspended = case.suspended
        vim.g.pairup_statusline_separator = '|'

        local result = indicator.get_colored_display()

        assert.are.equal(case.expected, result)

        -- Cleanup
        vim.g.pairup_suspended = nil
      end)
    end
  end)

  describe('combined display behavior (data-driven)', function()
    -- Test all valid display combinations (indicator.lua:296-311)
    local display_cases = {
      { local_ind = '[CL]', periph_ind = '', sep = '|', expected = '[CL]' },
      { local_ind = '', periph_ind = '[CP]', sep = '|', expected = '[CP]' },
      { local_ind = '[CL]', periph_ind = '[CP]', sep = '|', expected = '[CL] | [CP]' },
      { local_ind = '[CL:3/5]', periph_ind = '[CP:ready]', sep = '•', expected = '[CL:3/5] • [CP:ready]' },
      { local_ind = '', periph_ind = '', sep = '|', expected = '' },
      { local_ind = '[CL:processing]', periph_ind = '[CP:2/8]', sep = '', expected = '[CL:processing]  [CP:2/8]' },
    }

    for _, case in ipairs(display_cases) do
      it(
        string.format('displays "%s" when LOCAL=%s, PERIPHERAL=%s', case.expected, case.local_ind, case.periph_ind),
        function()
          vim.g.pairup_indicator = case.local_ind
          vim.g.pairup_peripheral_indicator = case.periph_ind
          vim.g.pairup_statusline_separator = case.sep

          assert.are.equal(case.expected, indicator.get_display())
        end
      )
    end
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
