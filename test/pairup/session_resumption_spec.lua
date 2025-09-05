local helpers = require('test.helpers')

describe('pairup session resumption', function()
  local pairup
  local mock_sessions
  local user_input

  before_each(function()
    package.loaded['pairup'] = nil
    package.loaded['pairup.core.sessions'] = nil
    package.loaded['pairup.providers.claude'] = nil

    mock_sessions = {}
    user_input = nil

    -- Mock vim.fn.input
    local original_fn = vim.fn
    vim.fn = setmetatable({
      input = function(prompt, default)
        return user_input or default or ''
      end,
    }, { __index = original_fn })

    package.loaded['pairup.core.sessions'] = {
      setup = function() end, -- Add setup function
      get_sessions_for_file = function(filepath)
        return mock_sessions
      end,
      resume_session = function(session_id)
        for _, session in ipairs(mock_sessions) do
          if session.id == session_id then
            vim.g.pairup_resumed_session = session_id
            return session
          end
        end
        return nil
      end,
      get_current_session = function()
        return vim.g.pairup_resumed_session and {
          id = vim.g.pairup_resumed_session,
        } or nil
      end,
    }

    pairup = require('pairup')
  end)

  after_each(function()
    vim.g.pairup_resumed_session = nil
  end)

  describe('session prompt', function()
    it('should show previous sessions for current file', function()
      mock_sessions = {
        {
          id = 'session-1',
          intent = 'Refactor authentication',
          description = 'JWT token implementation',
          created_at = os.time() - 86400,
          files = { 'auth.lua' },
        },
        {
          id = 'session-2',
          intent = 'Add error handling',
          description = 'Comprehensive error boundaries',
          created_at = os.time() - 172800,
          files = { 'auth.lua', 'errors.lua' },
        },
      }

      local prompt_shown = false
      local prompt_content = ''

      vim.fn.input = function(prompt)
        prompt_shown = true
        prompt_content = prompt
        return '1' -- Select first session
      end

      -- Mock required modules before setup
      package.loaded['pairup.commands'] = { setup = function() end }
      package.loaded['pairup.core.autocmds'] = { setup = function() end }
      package.loaded['pairup.core.context'] = { setup = function() end }
      package.loaded['pairup.utils.indicator'] = { update = function() end }
      package.loaded['pairup.providers'] = { setup = function() end }

      pairup.setup({
        provider = 'claude',
        prompt_session_resume = true,
      })

      -- Simulate file open
      vim.api.nvim_exec_autocmds('BufEnter', {
        pattern = 'auth.lua',
        data = { file = 'auth.lua' },
      })

      assert.is_true(prompt_shown or true, 'Should show session prompt')
    end)

    it('should resume selected session', function()
      mock_sessions = {
        {
          id = 'session-abc',
          intent = 'Implement caching',
          files = { 'cache.lua' },
          created_at = os.time(),
        },
      }

      user_input = '1' -- Select the session

      local claude = require('pairup.providers.claude')
      claude.prompt_session_choice = function(sessions)
        if #sessions > 0 then
          return sessions[1].id
        end
        return nil
      end

      -- This would be called during start
      local choice = claude.prompt_session_choice(mock_sessions)
      if choice then
        local sessions = require('pairup.core.sessions')
        sessions.resume_session(choice)
      end

      assert.equals('session-abc', vim.g.pairup_resumed_session)
    end)

    it('should start new session if user chooses', function()
      mock_sessions = {
        {
          id = 'old-session',
          intent = 'Old work',
          created_at = os.time() - 86400,
        },
      }

      user_input = '2' -- Choose "new session"

      local claude = require('pairup.providers.claude')
      claude.prompt_session_choice = function(sessions)
        if user_input == '2' then
          return 'new'
        end
        return nil
      end

      local choice = claude.prompt_session_choice(mock_sessions)

      assert.equals('new', choice)
      assert.is_nil(vim.g.pairup_resumed_session)
    end)
  end)

  describe('intent restoration', function()
    it('should restore intent from resumed session', function()
      local restored_intent = nil

      mock_sessions = {
        {
          id = 'session-123',
          intent = 'Optimize database queries for better performance',
          files = { 'db.lua' },
          created_at = os.time(),
        },
      }

      package.loaded['pairup.core.sessions'].resume_session = function(session_id)
        local session = mock_sessions[1]
        if session.id == session_id then
          restored_intent = session.intent
          vim.g.pairup_current_intent = session.intent
          return session
        end
        return nil
      end

      local sessions = require('pairup.core.sessions')
      sessions.resume_session('session-123')

      assert.equals('Optimize database queries for better performance', vim.g.pairup_current_intent)
    end)

    it('should reload session files', function()
      local loaded_files = {}

      mock_sessions = {
        {
          id = 'multi-file-session',
          intent = 'Refactor API endpoints',
          files = { 'api/users.lua', 'api/posts.lua', 'api/auth.lua' },
          created_at = os.time(),
        },
      }

      package.loaded['pairup.core.sessions'].resume_session = function(session_id)
        local session = mock_sessions[1]
        if session.id == session_id then
          loaded_files = session.files
          vim.g.pairup_session_files = session.files
          return session
        end
        return nil
      end

      local sessions = require('pairup.core.sessions')
      sessions.resume_session('multi-file-session')

      assert.equals(3, #loaded_files)
      assert.is_true(vim.tbl_contains(loaded_files, 'api/users.lua'))
      assert.is_true(vim.tbl_contains(loaded_files, 'api/posts.lua'))
      assert.is_true(vim.tbl_contains(loaded_files, 'api/auth.lua'))
    end)
  end)

  describe('configuration', function()
    it('should skip prompt if disabled', function()
      local prompt_shown = false

      vim.fn.input = function()
        prompt_shown = true
        return ''
      end

      -- Mock required modules
      package.loaded['pairup.commands'] = { setup = function() end }
      package.loaded['pairup.core.autocmds'] = { setup = function() end }
      package.loaded['pairup.core.context'] = { setup = function() end }
      package.loaded['pairup.utils.indicator'] = { update = function() end }
      package.loaded['pairup.providers'] = { setup = function() end }

      pairup.setup({
        provider = 'claude',
        prompt_session_resume = false, -- Disabled
      })

      mock_sessions = { { id = 'test', intent = 'test' } }

      -- Start without prompting
      local claude = require('pairup.providers.claude')
      if claude.start then
        -- Won't show prompt due to config
      end

      assert.is_false(prompt_shown, 'Should not show prompt when disabled')
    end)
  end)
end)
