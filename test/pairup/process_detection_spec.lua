describe('Process Detection', function()
  local claude
  local config
  local helpers = require('test.helpers')
  local mock = require('test.helpers.mock')

  before_each(function()
    -- Reset modules
    package.loaded['pairup.providers.claude'] = nil
    package.loaded['pairup.config'] = nil

    claude = require('pairup.providers.claude')
    config = require('pairup.config')
    config.setup({})

    -- Clear all buffers
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_valid(buf) then
        vim.api.nvim_buf_delete(buf, { force = true })
      end
    end
  end)

  describe('is_process_running', function()
    it('should return false for nil job_id', function()
      local result = claude.is_process_running(nil)
      assert.is_false(result)
    end)

    it('should return false for invalid job_id', function()
      local result = claude.is_process_running(999999)
      assert.is_false(result)
    end)

    it('should detect running process', function()
      -- Mock jobwait to return -1 (running)
      local original_jobwait = vim.fn.jobwait
      vim.fn.jobwait = function(jobs, timeout)
        return { -1 }
      end

      local result = claude.is_process_running(123)
      assert.is_true(result)

      -- Restore original
      vim.fn.jobwait = original_jobwait
    end)

    it('should detect stopped process', function()
      -- Mock jobwait to return 0 (stopped)
      local original_jobwait = vim.fn.jobwait
      vim.fn.jobwait = function(jobs, timeout)
        return { 0 }
      end

      local result = claude.is_process_running(123)
      assert.is_false(result)

      -- Restore original
      vim.fn.jobwait = original_jobwait
    end)
  end)

  describe('wait_for_process_ready', function()
    local original_defer_fn
    local deferred_callbacks

    before_each(function()
      -- Mock vim.defer_fn to capture callbacks
      original_defer_fn = vim.defer_fn
      deferred_callbacks = {}
      vim.defer_fn = function(callback, delay)
        table.insert(deferred_callbacks, { callback = callback, delay = delay })
      end
    end)

    after_each(function()
      vim.defer_fn = original_defer_fn
    end)

    it('should not wait if job_id is nil', function()
      local buf = vim.api.nvim_create_buf(false, true)
      local callback_called = false

      claude.wait_for_process_ready(buf, function()
        callback_called = true
      end)

      assert.equals(0, #deferred_callbacks)
      assert.is_false(callback_called)
    end)

    it('should wait for process and check for content', function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.b[buf].terminal_job_id = 123
      local callback_called = false

      -- Mock jobwait to indicate running
      local original_jobwait = vim.fn.jobwait
      vim.fn.jobwait = function(jobs, timeout)
        return { -1 }
      end

      claude.wait_for_process_ready(buf, function()
        callback_called = true
      end)

      -- Should have scheduled initial check
      assert.equals(1, #deferred_callbacks)
      assert.equals(2000, deferred_callbacks[1].delay) -- Initial 2 second delay

      -- Simulate no content yet
      deferred_callbacks[1].callback()

      -- Should schedule another check
      assert.equals(2, #deferred_callbacks)
      assert.equals(100, deferred_callbacks[2].delay)

      -- Add content to buffer
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'Claude output here' })

      -- Run the check again
      deferred_callbacks[2].callback()

      -- Should schedule the final callback
      assert.equals(3, #deferred_callbacks)
      assert.equals(500, deferred_callbacks[3].delay)

      -- Restore original
      vim.fn.jobwait = original_jobwait
    end)

    it('should timeout after max checks', function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.b[buf].terminal_job_id = 123
      local callback_called = false

      -- Mock jobwait to indicate not running
      local original_jobwait = vim.fn.jobwait
      vim.fn.jobwait = function(jobs, timeout)
        return { 0 }
      end

      -- Mock notify to capture timeout message
      local notify_called = false
      local original_notify = vim.notify
      vim.notify = function(msg, level)
        if msg:match('took too long to start') then
          notify_called = true
        end
      end

      claude.wait_for_process_ready(buf, function()
        callback_called = true
      end)

      -- Simulate initial check
      deferred_callbacks[1].callback()

      -- Simulate many checks (up to max)
      for i = 1, 300 do
        if deferred_callbacks[i] then
          deferred_callbacks[i].callback()
        end
      end

      assert.is_true(notify_called)
      assert.is_false(callback_called)

      -- Restore originals
      vim.fn.jobwait = original_jobwait
      vim.notify = original_notify
    end)
  end)

  describe('populate_intent with process detection', function()
    it('should wait for process before populating intent', function()
      -- Create a mock terminal buffer
      local buf = helpers.mock_terminal_buffer()
      vim.b[buf].terminal_job_id = 123

      -- Mock find_terminal to return nil initially (no terminal running)
      local original_find = claude.find_terminal
      local terminal_exists = false
      claude.find_terminal = function()
        if terminal_exists then
          return buf, nil, 123
        else
          return nil, nil, nil
        end
      end

      -- Mock the process as not ready initially
      local original_jobwait = vim.fn.jobwait
      local process_ready = false
      vim.fn.jobwait = function(jobs, timeout)
        if process_ready then
          return { -1 }
        else
          return { 0 }
        end
      end

      -- Mock defer_fn to capture callbacks
      local original_defer_fn = vim.defer_fn
      local deferred_callbacks = {}
      vim.defer_fn = function(callback, delay)
        table.insert(deferred_callbacks, { callback = callback, delay = delay })
      end

      -- Mock vim.cmd to prevent actual terminal creation
      local original_cmd = vim.cmd
      vim.cmd = function(cmd_str)
        if cmd_str:match('vsplit term://') then
          -- Simulate terminal creation
          terminal_exists = true
          vim.api.nvim_set_current_buf(buf)
          return
        elseif cmd_str == 'startinsert' or cmd_str == 'wincmd p' or cmd_str == 'stopinsert' then
          -- Ignore these commands
          return
        else
          -- Allow other commands
          original_cmd(cmd_str)
        end
      end

      -- Mock state module
      local state = require('pairup.utils.state')
      local original_set = state.set
      state.set = function(key, value)
        -- Just ignore state setting for this test
      end

      -- Mock indicator update
      package.loaded['pairup.utils.indicator'] = { update = function() end }

      -- Start Claude with intent mode
      claude.start(true) -- intent_mode = true

      -- Should have scheduled process check (wait_for_process_ready)
      assert.is_true(#deferred_callbacks > 0, 'Expected deferred callbacks to be scheduled')

      -- Find the initial check callback (2000ms delay)
      local found_callback = false
      for _, cb in ipairs(deferred_callbacks) do
        if cb.delay == 2000 then
          found_callback = true
          -- Simulate process becoming ready with content
          process_ready = true
          vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'Claude is ready' })
          cb.callback()
          break
        end
      end

      assert.is_true(found_callback, 'Expected to find 2000ms delay callback')

      -- Restore originals
      vim.fn.jobwait = original_jobwait
      vim.defer_fn = original_defer_fn
      vim.cmd = original_cmd
      claude.find_terminal = original_find
      state.set = original_set
    end)
  end)

  describe('add_current_directory with process detection', function()
    it('should wait for process before sending add-dir command', function()
      local context = require('pairup.core.context')
      local providers = require('pairup.providers')
      local state = require('pairup.utils.state')

      -- Create a mock terminal buffer
      local buf = helpers.mock_terminal_buffer()
      vim.b[buf].terminal_job_id = 123

      -- Mock find_terminal to return our buffer
      local original_find = providers.find_terminal
      providers.find_terminal = function()
        return buf, nil, 123
      end

      -- Mock is_process_running to return false initially
      local original_is_running = claude.is_process_running
      claude.is_process_running = function(job_id)
        return false
      end

      -- Mock state.has_directory to return false (not added yet)
      local original_has_dir = state.has_directory
      state.has_directory = function(dir)
        return false
      end

      -- Mock state.add_directory
      local original_add_dir = state.add_directory
      state.add_directory = function(dir)
        -- Just ignore
      end

      -- Mock wait_for_process_ready
      local wait_callback = nil
      local original_wait = claude.wait_for_process_ready
      claude.wait_for_process_ready = function(buf, callback)
        wait_callback = callback
      end

      -- Mock send_to_provider
      local sent_message = nil
      local original_send = providers.send_to_provider
      providers.send_to_provider = function(msg)
        sent_message = msg
        return true
      end

      -- Call add_current_directory
      context.add_current_directory()

      -- Should have captured the callback
      assert.is_not_nil(wait_callback)
      assert.is_nil(sent_message) -- Not sent yet

      -- Simulate process becoming ready
      wait_callback()

      -- Now the message should be sent
      assert.is_not_nil(sent_message)
      assert.truthy(sent_message:match('/add%-dir'))

      -- Restore originals
      providers.find_terminal = original_find
      claude.is_process_running = original_is_running
      claude.wait_for_process_ready = original_wait
      providers.send_to_provider = original_send
      state.has_directory = original_has_dir
      state.add_directory = original_add_dir
    end)

    it('should send immediately if process is already running', function()
      local context = require('pairup.core.context')
      local providers = require('pairup.providers')
      local state = require('pairup.utils.state')

      -- Create a mock terminal buffer
      local buf = helpers.mock_terminal_buffer()
      vim.b[buf].terminal_job_id = 123

      -- Mock find_terminal to return our buffer
      local original_find = providers.find_terminal
      providers.find_terminal = function()
        return buf, nil, 123
      end

      -- Mock is_process_running to return true (already running)
      local original_is_running = claude.is_process_running
      claude.is_process_running = function(job_id)
        return true
      end

      -- Mock state.has_directory to return false (not added yet)
      local original_has_dir = state.has_directory
      state.has_directory = function(dir)
        return false
      end

      -- Mock state.add_directory
      local original_add_dir = state.add_directory
      state.add_directory = function(dir)
        -- Just ignore
      end

      -- Mock send_to_provider
      local sent_message = nil
      local original_send = providers.send_to_provider
      providers.send_to_provider = function(msg)
        sent_message = msg
        return true
      end

      -- Call add_current_directory
      context.add_current_directory()

      -- Should send immediately
      assert.is_not_nil(sent_message, 'Expected message to be sent')
      assert.truthy(sent_message:match('/add%-dir'), 'Expected /add-dir command')

      -- Restore originals
      providers.find_terminal = original_find
      claude.is_process_running = original_is_running
      providers.send_to_provider = original_send
      state.has_directory = original_has_dir
      state.add_directory = original_add_dir
    end)
  end)
end)
