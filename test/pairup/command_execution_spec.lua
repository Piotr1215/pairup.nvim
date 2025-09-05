local helpers = require('test.helpers')

describe('pairup command execution', function()
  local pairup
  local original_send_message
  local captured_messages

  before_each(function()
    package.loaded['pairup'] = nil
    package.loaded['pairup.commands'] = nil
    package.loaded['pairup.providers'] = nil

    pairup = require('pairup')
    pairup.setup()
    require('pairup.commands').setup()

    -- Mock send_message to capture output
    captured_messages = {}
    original_send_message = pairup.send_message
    pairup.send_message = function(msg)
      table.insert(captured_messages, msg)
    end
  end)

  after_each(function()
    if original_send_message then
      pairup.send_message = original_send_message
    end
    captured_messages = {}
  end)

  describe('shell command execution', function()
    it('should execute shell commands with ! prefix', function()
      vim.cmd('PairupSay !echo "test output"')

      assert.equals(1, #captured_messages)
      local msg = captured_messages[1]
      assert.is_not_nil(msg:match('Shell command output'))
      assert.is_not_nil(msg:match('echo "test output"'))
      assert.is_not_nil(msg:match('test output'))
    end)

    it('should handle shell command errors', function()
      vim.cmd('PairupSay !false_command_that_doesnt_exist')

      assert.equals(1, #captured_messages)
      local msg = captured_messages[1]
      assert.is_not_nil(msg:match('Shell command output'))
    end)

    it('should execute complex shell commands', function()
      vim.cmd([[PairupSay !echo "line1" && echo "line2"]])

      assert.equals(1, #captured_messages)
      local msg = captured_messages[1]
      assert.is_not_nil(msg:match('line1'))
      assert.is_not_nil(msg:match('line2'))
    end)

    it('should handle shell pipes', function()
      vim.cmd([[PairupSay !echo "hello world" | grep world]])

      assert.equals(1, #captured_messages)
      local msg = captured_messages[1]
      assert.is_not_nil(msg:match('world'))
      -- The full "hello world" should appear since grep matches the line
      assert.is_not_nil(msg:match('hello world'))
    end)

    it('should expand vim filename modifiers in shell commands', function()
      -- Create a test file
      local test_file = vim.fn.tempname() .. '.txt'
      vim.fn.writefile({ 'test content' }, test_file)

      -- Open the file
      vim.cmd('edit ' .. test_file)

      -- Use % to reference current file
      vim.cmd('PairupSay !echo %')

      assert.equals(1, #captured_messages)
      local msg = captured_messages[1]
      -- Check that the filename (not full path) is in the output
      local filename = vim.fn.fnamemodify(test_file, ':t')
      assert.is_not_nil(msg:match(filename))

      -- Cleanup
      vim.cmd('bdelete!')
      vim.fn.delete(test_file)
    end)

    it('should expand % in cat command', function()
      -- Create a test file with known content
      local test_file = vim.fn.tempname() .. '.txt'
      vim.fn.writefile({ 'line1', 'line2', 'line3' }, test_file)

      -- Open the file
      vim.cmd('edit ' .. test_file)

      -- Use cat % to read current file
      vim.cmd('PairupSay !cat %')

      assert.equals(1, #captured_messages)
      local msg = captured_messages[1]
      assert.is_not_nil(msg:match('line1'))
      assert.is_not_nil(msg:match('line2'))
      assert.is_not_nil(msg:match('line3'))

      -- Cleanup
      vim.cmd('bdelete!')
      vim.fn.delete(test_file)
    end)
  end)

  describe('vim command execution', function()
    it('should execute vim commands with : prefix', function()
      vim.cmd('PairupSay :version')

      assert.equals(1, #captured_messages)
      local msg = captured_messages[1]
      assert.is_not_nil(msg:match('Vim command output'))
      assert.is_not_nil(msg:match(':version'))
      assert.is_not_nil(msg:match('VIM')) -- Version output contains VIM
    end)

    it('should capture vim echo output', function()
      vim.cmd([[PairupSay :echo "hello from vim"]])

      assert.equals(1, #captured_messages)
      local msg = captured_messages[1]
      assert.is_not_nil(msg:match('hello from vim'))
    end)

    it('should handle vim command errors gracefully', function()
      -- Mock vim.notify to capture errors
      local original_notify = vim.notify
      local notify_called = false
      vim.notify = function(msg, level)
        if level == vim.log.levels.ERROR then
          notify_called = true
        end
      end

      -- This should not throw, but notify error
      vim.cmd('PairupSay :invalidcommand123')

      -- Restore original notify
      vim.notify = original_notify

      assert.is_true(notify_called)
      -- Error is handled via vim.notify, not sent as message
      assert.equals(0, #captured_messages)
    end)

    it('should execute vim list commands', function()
      -- Create some registers first
      vim.fn.setreg('a', 'test content')

      vim.cmd('PairupSay :registers a')

      assert.equals(1, #captured_messages)
      local msg = captured_messages[1]
      assert.is_not_nil(msg:match('test content'))
    end)

    it('should handle vim settings queries', function()
      vim.opt.tabstop = 8

      vim.cmd('PairupSay :set tabstop?')

      assert.equals(1, #captured_messages)
      local msg = captured_messages[1]
      assert.is_not_nil(msg:match('tabstop'))
    end)
  end)

  describe('regular message handling', function()
    it('should send regular messages without prefix', function()
      vim.cmd('PairupSay Hello world')

      assert.equals(1, #captured_messages)
      assert.equals('Hello world', captured_messages[1])
    end)

    it('should handle messages with spaces', function()
      vim.cmd('PairupSay This is a test message')

      assert.equals(1, #captured_messages)
      assert.equals('This is a test message', captured_messages[1])
    end)

    it('should not interpret escaped prefixes', function()
      vim.cmd([[PairupSay \!not a shell command]])

      assert.equals(1, #captured_messages)
      -- The backslash is processed by vim command parser
      assert.equals('\\!not a shell command', captured_messages[1])
    end)
  end)

  describe('edge cases', function()
    it('should handle empty shell command', function()
      vim.cmd('PairupSay !')

      assert.equals(1, #captured_messages)
      local msg = captured_messages[1]
      assert.is_not_nil(msg:match('Shell command output'))
    end)

    it('should handle empty vim command', function()
      vim.cmd('PairupSay :')

      assert.equals(1, #captured_messages)
      local msg = captured_messages[1]
      assert.is_not_nil(msg:match('Vim command output'))
    end)

    it('should handle multiline shell output', function()
      local cmd = [[PairupSay !printf "line1\nline2\nline3"]]
      vim.cmd(cmd)

      assert.equals(1, #captured_messages)
      local msg = captured_messages[1]
      assert.is_not_nil(msg:match('line1'))
      assert.is_not_nil(msg:match('line2'))
      assert.is_not_nil(msg:match('line3'))
    end)
  end)
end)
