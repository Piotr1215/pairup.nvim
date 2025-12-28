-- Tests for session module (core terminal session abstraction)

describe('session', function()
  local session_factory

  before_each(function()
    session_factory = require('pairup.core.session')
  end)

  after_each(function()
    -- Clean up any created buffers
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_valid(buf) then
        pcall(vim.api.nvim_buf_delete, buf, { force = true })
      end
    end
    -- Clear all vim.g cache
    vim.g.test_session_buf = nil
    vim.g.test_session_job = nil
  end)

  describe('new', function()
    it('creates session instance with config', function()
      local session = session_factory.new({
        type = 'test',
        buffer_name = 'test-terminal',
        cache_prefix = 'test_session',
        buffer_marker = function(buf)
          return vim.b[buf].is_test_session
        end,
        terminal_cmd = function()
          return "echo 'test'"
        end,
      })

      assert.is_not_nil(session)
      assert.equals('test', session.type)
    end)

    it('validates required config fields', function()
      assert.has_error(function()
        session_factory.new({})
      end)

      assert.has_error(function()
        session_factory.new({ type = 'test' })
      end)
    end)
  end)

  describe('is_running', function()
    it('returns false when no session exists', function()
      local session = session_factory.new({
        type = 'test',
        buffer_name = 'test-terminal',
        cache_prefix = 'test_session',
        buffer_marker = function(buf)
          return vim.b[buf].is_test_session
        end,
        terminal_cmd = function()
          return "echo 'test'"
        end,
      })

      assert.is_false(session:is_running())
    end)

    it('returns true when cached buffer is valid', function()
      local buf = vim.api.nvim_create_buf(true, false)
      vim.b[buf].is_test_session = true
      vim.g.test_session_buf = buf

      local session = session_factory.new({
        type = 'test',
        buffer_name = 'test-terminal',
        cache_prefix = 'test_session',
        buffer_marker = function(b)
          return vim.b[b].is_test_session
        end,
        terminal_cmd = function()
          return "echo 'test'"
        end,
      })

      assert.is_true(session:is_running())
    end)

    it('returns false when cached buffer is invalid', function()
      vim.g.test_session_buf = 9999 -- invalid buffer

      local session = session_factory.new({
        type = 'test',
        buffer_name = 'test-terminal',
        cache_prefix = 'test_session',
        buffer_marker = function(buf)
          return vim.b[buf].is_test_session
        end,
        terminal_cmd = function()
          return "echo 'test'"
        end,
      })

      assert.is_false(session:is_running())
    end)
  end)

  describe('find', function()
    it('returns nil when no session buffer exists', function()
      local session = session_factory.new({
        type = 'test',
        buffer_name = 'test-terminal',
        cache_prefix = 'test_session',
        buffer_marker = function(buf)
          return vim.b[buf].is_test_session
        end,
        terminal_cmd = function()
          return "echo 'test'"
        end,
      })

      local buf, win, job = session:find()
      assert.is_nil(buf)
      assert.is_nil(win)
      assert.is_nil(job)
    end)

    it('finds buffer from cache when valid', function()
      local buf = vim.api.nvim_create_buf(true, false)
      vim.b[buf].is_test_session = true
      vim.b[buf].terminal_job_id = 123
      vim.g.test_session_buf = buf
      vim.g.test_session_job = 123

      local session = session_factory.new({
        type = 'test',
        buffer_name = 'test-terminal',
        cache_prefix = 'test_session',
        buffer_marker = function(b)
          return vim.b[b].is_test_session
        end,
        terminal_cmd = function()
          return "echo 'test'"
        end,
      })

      local found_buf, found_win, found_job = session:find()
      assert.equals(buf, found_buf)
      assert.is_nil(found_win) -- no window created
      assert.equals(123, found_job)
    end)

    it('searches all buffers when cache miss', function()
      local buf = vim.api.nvim_create_buf(true, false)
      vim.b[buf].is_test_session = true
      vim.b[buf].terminal_job_id = 456

      local session = session_factory.new({
        type = 'test',
        buffer_name = 'test-terminal',
        cache_prefix = 'test_session',
        buffer_marker = function(b)
          return vim.b[b].is_test_session
        end,
        terminal_cmd = function()
          return "echo 'test'"
        end,
      })

      local found_buf, _, found_job = session:find()
      assert.equals(buf, found_buf)
      assert.equals(456, found_job)
      -- Cache should be updated
      assert.equals(buf, vim.g.test_session_buf)
      assert.equals(456, vim.g.test_session_job)
    end)
  end)

  describe('send_message', function()
    it('returns false when session not running', function()
      local session = session_factory.new({
        type = 'test',
        buffer_name = 'test-terminal',
        cache_prefix = 'test_session',
        buffer_marker = function(buf)
          return vim.b[buf].is_test_session
        end,
        terminal_cmd = function()
          return "echo 'test'"
        end,
      })

      assert.is_false(session:send_message('hello'))
    end)

    it('clears cache when chansend fails', function()
      local buf = vim.api.nvim_create_buf(true, false)
      vim.b[buf].is_test_session = true
      vim.b[buf].terminal_job_id = 9999 -- invalid job
      vim.g.test_session_buf = buf
      vim.g.test_session_job = 9999

      local session = session_factory.new({
        type = 'test',
        buffer_name = 'test-terminal',
        cache_prefix = 'test_session',
        buffer_marker = function(b)
          return vim.b[b].is_test_session
        end,
        terminal_cmd = function()
          return "echo 'test'"
        end,
      })

      assert.is_false(session:send_message('hello'))
      -- Cache should be cleared
      assert.is_nil(vim.g.test_session_buf)
      assert.is_nil(vim.g.test_session_job)
    end)
  end)

  describe('stop', function()
    it('does nothing when session not running', function()
      local session = session_factory.new({
        type = 'test',
        buffer_name = 'test-terminal',
        cache_prefix = 'test_session',
        buffer_marker = function(buf)
          return vim.b[buf].is_test_session
        end,
        terminal_cmd = function()
          return "echo 'test'"
        end,
      })

      -- Should not error
      session:stop()
    end)

    it('cleans up buffer, job, and cache', function()
      local buf = vim.api.nvim_create_buf(true, false)
      vim.b[buf].is_test_session = true
      vim.b[buf].terminal_job_id = 123
      vim.g.test_session_buf = buf
      vim.g.test_session_job = 123

      local on_stop_called = false
      local session = session_factory.new({
        type = 'test',
        buffer_name = 'test-terminal',
        cache_prefix = 'test_session',
        buffer_marker = function(b)
          return vim.b[b].is_test_session
        end,
        terminal_cmd = function()
          return "echo 'test'"
        end,
        on_stop = function()
          on_stop_called = true
        end,
      })

      session:stop()

      assert.is_true(on_stop_called)
      assert.is_false(vim.api.nvim_buf_is_valid(buf))
      assert.is_nil(vim.g.test_session_buf)
      assert.is_nil(vim.g.test_session_job)
    end)
  end)
end)
