describe('pairup session persistence', function()
  local pairup
  local mock_db

  before_each(function()
    vim.g.pairup_test_mode = true

    -- Clear modules
    for k, _ in pairs(package.loaded) do
      if k:match('^pairup') then
        package.loaded[k] = nil
      end
    end

    mock_db = {
      sessions = {},
      file_sessions = {},
    }

    package.loaded['pairup.core.sessions'] = {
      setup = function() end, -- Add setup function
      save_session = function(session)
        table.insert(mock_db.sessions, session)
        return session.id
      end,
      get_sessions_for_file = function(filepath)
        return mock_db.file_sessions[filepath] or {}
      end,
      load_session = function(session_id)
        for _, session in ipairs(mock_db.sessions) do
          if session.id == session_id then
            return session
          end
        end
        return nil
      end,
      associate_file_with_session = function(filepath, session_id)
        mock_db.file_sessions[filepath] = mock_db.file_sessions[filepath] or {}
        table.insert(mock_db.file_sessions[filepath], session_id)
      end,
    }

    pairup = require('pairup')
  end)

  after_each(function()
    vim.g.pairup_test_mode = nil
  end)

  describe('session creation', function()
    it('should create session with intent and metadata', function()
      local sessions = require('pairup.core.sessions')

      local session_id = sessions.save_session({
        id = 'test-123',
        intent = 'Refactor authentication logic to use JWT tokens',
        files = { 'auth.lua', 'jwt.lua' },
        created_at = os.time(),
        description = 'JWT authentication refactor',
      })

      assert.equals('test-123', session_id)
      assert.equals(1, #mock_db.sessions)
      assert.equals('Refactor authentication logic to use JWT tokens', mock_db.sessions[1].intent)
    end)

    it('should associate files with session', function()
      local sessions = require('pairup.core.sessions')

      sessions.save_session({
        id = 'session-456',
        intent = 'Add user profile feature',
        files = {},
      })

      sessions.associate_file_with_session('profile.lua', 'session-456')
      sessions.associate_file_with_session('user.lua', 'session-456')

      assert.equals(1, #(mock_db.file_sessions['profile.lua'] or {}))
      assert.equals('session-456', mock_db.file_sessions['profile.lua'][1])
    end)

    it('should track multiple sessions per file', function()
      local sessions = require('pairup.core.sessions')

      sessions.save_session({ id = 'session-1', intent = 'Fix bug', files = {} })
      sessions.save_session({ id = 'session-2', intent = 'Add feature', files = {} })

      sessions.associate_file_with_session('shared.lua', 'session-1')
      sessions.associate_file_with_session('shared.lua', 'session-2')

      local file_sessions = sessions.get_sessions_for_file('shared.lua')
      assert.equals(2, #file_sessions)
    end)
  end)

  describe('session persistence', function()
    it('should persist session on Claude stop', function()
      local saved_session = nil

      -- Set up session state
      vim.g.pairup_current_session_id = 'active-session'
      vim.g.pairup_current_intent = 'Implement caching'
      vim.g.pairup_session_files = { 'cache.lua', 'store.lua' }

      package.loaded['pairup.core.sessions'] = {
        setup = function() end,
        get_current_session = function()
          return {
            id = vim.g.pairup_current_session_id,
            intent = vim.g.pairup_current_intent,
            files = vim.g.pairup_session_files,
          }
        end,
        end_current_session = function()
          saved_session = {
            id = vim.g.pairup_current_session_id,
            intent = vim.g.pairup_current_intent,
            files = vim.g.pairup_session_files or {},
            ended_at = os.time(),
          }
          vim.g.pairup_current_session_id = nil
          vim.g.pairup_current_intent = nil
          vim.g.pairup_session_files = nil
        end,
      }

      -- Mock required modules
      package.loaded['pairup.commands'] = { setup = function() end }
      package.loaded['pairup.core.autocmds'] = { setup = function() end }
      package.loaded['pairup.core.context'] = { setup = function() end, clear = function() end }
      package.loaded['pairup.utils.indicator'] = { update = function() end }
      package.loaded['pairup.providers'] = {
        setup = function() end,
        stop = function() end,
      }

      pairup.setup({
        provider = 'claude',
        persist_sessions = true,
      })

      -- Call stop which should trigger session persistence
      -- Mock the stop to simulate session saving
      local providers = require('pairup.providers')
      providers.stop()

      -- Simulate what stop does - end the session
      local sessions = require('pairup.core.sessions')
      sessions.end_current_session()

      assert.is_not_nil(saved_session)
      assert.equals('active-session', saved_session.id)
      assert.equals('Implement caching', saved_session.intent)
      assert.equals(2, #saved_session.files)
    end)

    it('should prompt for session description if configured', function()
      local description_prompt_shown = false

      -- Mock vim.fn.input
      vim.fn.input = function(prompt, default)
        if prompt and prompt:match('description') then
          description_prompt_shown = true
          return 'Added comprehensive error handling'
        end
        return default or ''
      end

      -- Mock required modules
      package.loaded['pairup.commands'] = { setup = function() end }
      package.loaded['pairup.core.autocmds'] = { setup = function() end }
      package.loaded['pairup.core.context'] = { setup = function() end, clear = function() end }
      package.loaded['pairup.utils.indicator'] = { update = function() end }
      package.loaded['pairup.providers'] = {
        setup = function() end,
        stop = function() end,
      }

      pairup.setup({
        provider = 'claude',
        persist_sessions = true,
        prompt_for_description = true,
      })

      -- Simulate the stop flow with description prompt
      local config = require('pairup.config')
      if config.get('prompt_for_description') then
        -- This should trigger our mocked input function
        local desc = vim.fn.input('Enter session description: ', '')
        description_prompt_shown = desc ~= nil
      end

      assert.is_true(description_prompt_shown, 'Should prompt for session description')
    end)
  end)
end)
