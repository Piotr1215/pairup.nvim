local helpers = require('test.helpers')

describe('pairup integration tests', function()
  local pairup
  local temp_file

  before_each(function()
    -- Clean state
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.b[buf] and vim.b[buf].is_pairup_assistant then
        pcall(vim.api.nvim_buf_delete, buf, { force = true })
      end
    end

    package.loaded['pairup'] = nil
    package.loaded['pairup.config'] = nil
    package.loaded['pairup.core.sessions'] = nil

    vim.g.pairup_test_mode = true

    -- Create temp test file
    temp_file = vim.fn.tempname() .. '.lua'
    helpers.create_test_file(
      temp_file,
      [[
function hello()
  print("hello world")
end
]]
    )

    pairup = require('pairup')
  end)

  after_each(function()
    if temp_file then
      helpers.cleanup_test_file(temp_file)
    end
  end)

  describe('full workflow', function()
    it('should handle complete session lifecycle', function()
      local sessions = require('pairup.core.sessions')

      -- Setup with all features
      pairup.setup({
        provider = 'claude',
        persist_sessions = true,
        auto_populate_intent = true,
        suggestion_mode = true,
        prompt_session_resume = true,
      })

      -- Create a session with intent
      local session_id = sessions.create_session('Refactor hello function to be more robust', 'Adding error handling')

      assert.is_not_nil(session_id)
      assert.equals('Refactor hello function to be more robust', vim.g.pairup_current_intent)

      -- Add file to session
      sessions.add_file_to_session(temp_file)

      local current = sessions.get_current_session()
      assert.is_not_nil(current)
      assert.equals(1, #current.files)

      -- Save and end session
      sessions.end_current_session()
      assert.is_nil(sessions.get_current_session())

      -- Verify session can be loaded
      local loaded_sessions = sessions.get_sessions_for_file(temp_file)
      assert.equals(1, #loaded_sessions)
      assert.equals(session_id, loaded_sessions[1].id)
    end)

    it('should track multiple files in one session', function()
      local sessions = require('pairup.core.sessions')

      pairup.setup({
        provider = 'claude',
        persist_sessions = true,
      })

      -- Create session
      sessions.create_session('Multi-file refactoring', '')

      -- Add multiple files
      local file1 = vim.fn.tempname() .. '1.lua'
      local file2 = vim.fn.tempname() .. '2.lua'
      local file3 = vim.fn.tempname() .. '3.lua'

      helpers.create_test_file(file1, '-- file 1')
      helpers.create_test_file(file2, '-- file 2')
      helpers.create_test_file(file3, '-- file 3')

      sessions.add_file_to_session(file1)
      sessions.add_file_to_session(file2)
      sessions.add_file_to_session(file3)

      -- Verify all files tracked
      local current = sessions.get_current_session()
      assert.equals(3, #current.files)

      -- Save session
      sessions.save_session(current)

      -- Each file should know about this session
      local sessions1 = sessions.get_sessions_for_file(file1)
      local sessions2 = sessions.get_sessions_for_file(file2)
      local sessions3 = sessions.get_sessions_for_file(file3)

      assert.equals(1, #sessions1)
      assert.equals(1, #sessions2)
      assert.equals(1, #sessions3)
      assert.equals(sessions1[1].id, sessions2[1].id)
      assert.equals(sessions2[1].id, sessions3[1].id)

      -- Cleanup
      helpers.cleanup_test_file(file1)
      helpers.cleanup_test_file(file2)
      helpers.cleanup_test_file(file3)
    end)
  end)

  describe('error handling', function()
    it('should handle missing session files gracefully', function()
      local sessions = require('pairup.core.sessions')

      -- Try to load non-existent session
      local result = sessions.load_session('non-existent-id')
      assert.is_nil(result)

      -- Try to resume non-existent session
      local resumed = sessions.resume_session('non-existent-id')
      assert.is_nil(resumed)
    end)

    it('should clean up invalid sessions from index', function()
      local sessions = require('pairup.core.sessions')

      -- Manually corrupt the index
      sessions.session_files['/fake/file.lua'] = { 'invalid-1', 'invalid-2', 'invalid-3' }
      sessions.save_file_index()

      -- Get sessions should clean up invalid entries
      local results = sessions.get_sessions_for_file('/fake/file.lua')
      assert.equals(0, #results)

      -- Index should be updated
      sessions.load_file_index()
      assert.equals(0, #(sessions.session_files['/fake/file.lua'] or {}))
    end)

    it('should handle corrupt session files', function()
      local sessions = require('pairup.core.sessions')
      local session_dir = vim.fn.stdpath('state') .. '/pairup/sessions'
      vim.fn.mkdir(session_dir, 'p')

      -- Create corrupt session file
      local corrupt_file = session_dir .. '/corrupt-session.json'
      local file = io.open(corrupt_file, 'w')
      file:write('{ invalid json }')
      file:close()

      -- Should return nil, not error
      local result = sessions.load_session('corrupt-session')
      assert.is_nil(result)

      -- Cleanup
      os.remove(corrupt_file)
    end)
  end)

  describe('session cleanup', function()
    it('should wipe old sessions', function()
      local sessions = require('pairup.core.sessions')

      -- Create old and new sessions
      local old_session = {
        id = 'old-session',
        intent = 'Old work',
        files = {},
        created_at = os.time() - (40 * 86400), -- 40 days old
      }

      local new_session = {
        id = 'new-session',
        intent = 'Recent work',
        files = {},
        created_at = os.time() - (5 * 86400), -- 5 days old
      }

      sessions.sessions[old_session.id] = old_session
      sessions.save_session(old_session)

      sessions.sessions[new_session.id] = new_session
      sessions.save_session(new_session)

      -- Wipe sessions older than 30 days
      sessions.wipe_old_sessions(30)

      -- Old should be gone, new should remain
      assert.is_nil(sessions.load_session('old-session'))
      assert.is_not_nil(sessions.load_session('new-session'))
    end)

    it('should wipe all sessions when requested', function()
      local sessions = require('pairup.core.sessions')

      -- Create some sessions
      for i = 1, 3 do
        sessions.create_session('Session ' .. i, '')
        sessions.save_session()
      end

      -- Wipe all
      sessions.wipe_all_sessions()

      -- Verify all gone
      assert.equals(0, vim.tbl_count(sessions.sessions))
      assert.is_nil(sessions.current_session)
    end)
  end)
end)
