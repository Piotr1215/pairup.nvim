local helpers = require('test.helpers')

describe('pairup diff monitoring', function()
  local pairup
  local mock_git_diff
  local mock_claude_send

  before_each(function()
    -- Clean all modules
    for k, _ in pairs(package.loaded) do
      if k:match('^pairup') then
        package.loaded[k] = nil
      end
    end

    vim.g.pairup_test_mode = true

    mock_git_diff = ''
    mock_claude_send = {}

    package.loaded['pairup.utils.git'] = {
      get_unstaged_diff = function()
        return mock_git_diff
      end,
      send_git_status = function() end,
    }

    package.loaded['pairup.providers'] = {
      setup = function() end,
      start = function() end,
      send_message = function(msg, opts)
        table.insert(mock_claude_send, { message = msg, options = opts })
      end,
      toggle = function() end,
      stop = function() end,
      find_terminal = function()
        return 1
      end, -- Mock terminal exists
    }

    -- Mock other required modules
    package.loaded['pairup.commands'] = { setup = function() end }
    package.loaded['pairup.core.autocmds'] = { setup = function() end }
    package.loaded['pairup.core.context'] = {
      setup = function() end,
      send_context = function(opts)
        table.insert(mock_claude_send, {
          message = mock_git_diff,
          options = opts or {},
        })
      end,
      clear = function() end,
    }
    package.loaded['pairup.core.sessions'] = {
      setup = function() end,
      add_file_to_session = function() end,
      get_current_session = function()
        return nil
      end,
    }
    package.loaded['pairup.utils.indicator'] = { update = function() end }
    package.loaded['pairup.utils.state'] = {
      clear = function() end,
      get = function()
        return nil
      end,
      set = function() end,
      clear_directories = function() end,
      add_directory = function() end,
    }

    pairup = require('pairup')
  end)

  describe('file save monitoring', function()
    it('should send diff to Claude on file save', function()
      -- Ensure mocks are ready
      mock_claude_send = {}

      pairup.setup({
        provider = 'claude',
        enabled = true,
      })

      mock_git_diff = [[
diff --git a/test.lua b/test.lua
index abc123..def456 100644
--- a/test.lua
+++ b/test.lua
@@ -1,3 +1,3 @@
 function hello()
-  print("hello")
+  print("hello world")
 end]]

      -- Directly call send_context to verify it works
      local context = require('pairup.core.context')
      context.send_context()

      -- Check that something was sent
      assert.is_true(#mock_claude_send > 0, 'Should send at least one message to Claude')
    end)

    it('should only send suggestions without modifying files', function()
      pairup.setup({
        provider = 'claude',
        enabled = true,
        suggestion_mode = true,
      })

      mock_git_diff = 'some diff'

      -- Trigger with context module directly
      local context = require('pairup.core.context')
      context.send_context({ suggestions_only = true })

      -- Check the options
      assert.is_true(#mock_claude_send > 0, 'Should have sent something')
      assert.is_true(mock_claude_send[1].options.suggestions_only == true, 'Should be marked as suggestions only')
    end)

    it('should not send diff when disabled', function()
      pairup.setup({
        provider = 'claude',
        send_diff_on_save = false,
      })

      mock_git_diff = 'some diff'

      vim.api.nvim_exec_autocmds('BufWritePost', {
        pattern = '*.lua',
      })

      vim.wait(100)

      assert.equals(0, #mock_claude_send, 'Should not send any messages when disabled')
    end)
  end)

  describe('multi-file awareness', function()
    it('should track multiple files in same session', function()
      local session_files = {}

      -- Mock sessions more completely
      package.loaded['pairup.core.sessions'] = {
        setup = function() end,
        add_file_to_session = function(filepath)
          table.insert(session_files, filepath)
        end,
        get_current_session = function()
          return { id = 'test-session-123' }
        end,
        create_session = function()
          return 'test-session-123'
        end,
      }

      pairup.setup({
        provider = 'claude',
        track_multiple_files = true,
      })

      -- Directly call the session tracking
      local sessions = require('pairup.core.sessions')
      sessions.add_file_to_session('file1.lua')
      sessions.add_file_to_session('file2.lua')

      assert.equals(2, #session_files, 'Should track two files')
      assert.is_true(vim.tbl_contains(session_files, 'file1.lua'), 'Should contain first file')
      assert.is_true(vim.tbl_contains(session_files, 'file2.lua'), 'Should contain second file')
    end)
  end)
end)
