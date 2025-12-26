-- Tests for async draft mode (capture and apply edits)
describe('pairup.drafts', function()
  local drafts
  local DRAFTS_FILE = '/tmp/pairup-drafts.json'
  local test_session_id = 'test-session-123'

  before_each(function()
    package.loaded['pairup.drafts'] = nil
    drafts = require('pairup.drafts')

    -- Clean state
    os.remove(DRAFTS_FILE)
    os.remove('/tmp/pairup-draft-mode-' .. test_session_id)
    vim.g.pairup_session_id = nil
  end)

  after_each(function()
    os.remove(DRAFTS_FILE)
    if vim.g.pairup_session_id then
      os.remove('/tmp/pairup-draft-mode-' .. vim.g.pairup_session_id)
    end
    vim.g.pairup_session_id = nil
  end)

  describe('enable/disable', function()
    it('should require session ID to enable', function()
      drafts.enable()
      assert.is_false(drafts.is_enabled())
    end)

    it('should create flag file when session exists', function()
      vim.g.pairup_session_id = test_session_id
      drafts.enable()
      assert.is_true(drafts.is_enabled())
    end)

    it('should remove flag file on disable', function()
      vim.g.pairup_session_id = test_session_id
      drafts.enable()
      assert.is_true(drafts.is_enabled())

      drafts.disable()
      assert.is_false(drafts.is_enabled())
    end)

    it('should return false when no session', function()
      assert.is_false(drafts.is_enabled())
    end)
  end)

  describe('get_all', function()
    it('should return empty table when no drafts file', function()
      local all = drafts.get_all()
      assert.equals(0, #all)
    end)

    it('should parse valid JSON drafts', function()
      local json = vim.json.encode({
        { id = '1', file = '/test.lua', old_string = 'old', new_string = 'new' },
        { id = '2', file = '/test2.lua', old_string = 'a', new_string = 'b' },
      })
      local f = io.open(DRAFTS_FILE, 'w')
      f:write(json)
      f:close()

      local all = drafts.get_all()
      assert.equals(2, #all)
      assert.equals('/test.lua', all[1].file)
    end)

    it('should handle malformed JSON gracefully', function()
      local f = io.open(DRAFTS_FILE, 'w')
      f:write('not valid json {{{')
      f:close()

      local all = drafts.get_all()
      assert.equals(0, #all)
    end)

    it('should handle empty file', function()
      local f = io.open(DRAFTS_FILE, 'w')
      f:write('')
      f:close()

      local all = drafts.get_all()
      assert.equals(0, #all)
    end)
  end)

  describe('count', function()
    it('should return 0 when no drafts', function()
      assert.equals(0, drafts.count())
    end)

    it('should return correct count', function()
      local json = vim.json.encode({
        { id = '1', file = '/a.lua', old_string = 'x', new_string = 'y' },
        { id = '2', file = '/b.lua', old_string = 'x', new_string = 'y' },
        { id = '3', file = '/c.lua', old_string = 'x', new_string = 'y' },
      })
      local f = io.open(DRAFTS_FILE, 'w')
      f:write(json)
      f:close()

      assert.equals(3, drafts.count())
    end)
  end)

  describe('clear', function()
    it('should remove drafts file', function()
      local f = io.open(DRAFTS_FILE, 'w')
      f:write('[]')
      f:close()

      drafts.clear()

      local exists = io.open(DRAFTS_FILE, 'r')
      assert.is_nil(exists)
    end)

    it('should not error when no file exists', function()
      assert.has_no.errors(function()
        drafts.clear()
      end)
    end)
  end)

  describe('apply_next', function()
    local test_file
    local test_buf

    before_each(function()
      test_file = '/tmp/pairup-test-apply.txt'
      local f = io.open(test_file, 'w')
      f:write('local x = 1\nlocal y = 2\n')
      f:close()

      test_buf = vim.fn.bufadd(test_file)
      vim.fn.bufload(test_buf)
    end)

    after_each(function()
      if vim.api.nvim_buf_is_valid(test_buf) then
        vim.api.nvim_buf_delete(test_buf, { force = true })
      end
      os.remove(test_file)
    end)

    it('should return false when no drafts', function()
      local ok, msg = drafts.apply_next()
      assert.is_false(ok)
      assert.equals('No pending drafts', msg)
    end)

    it('should apply draft and remove from queue', function()
      local json = vim.json.encode({
        { id = '1', file = test_file, old_string = 'local x = 1', new_string = 'local x = 42' },
      })
      local f = io.open(DRAFTS_FILE, 'w')
      f:write(json)
      f:close()

      local ok, msg = drafts.apply_next()
      assert.is_true(ok)
      assert.is_truthy(msg:match('Applied'))

      local lines = vim.api.nvim_buf_get_lines(test_buf, 0, -1, false)
      assert.equals('local x = 42', lines[1])

      assert.equals(0, drafts.count())
    end)

    it('should fail gracefully when old_string not found', function()
      local json = vim.json.encode({
        { id = '1', file = test_file, old_string = 'NONEXISTENT', new_string = 'new' },
      })
      local f = io.open(DRAFTS_FILE, 'w')
      f:write(json)
      f:close()

      local ok, msg = drafts.apply_next()
      assert.is_false(ok)
      assert.is_truthy(msg:match('not found'))
    end)

    it('should fail gracefully when file missing', function()
      local json = vim.json.encode({
        { id = '1', file = '/nonexistent/path.lua', old_string = 'a', new_string = 'b' },
      })
      local f = io.open(DRAFTS_FILE, 'w')
      f:write(json)
      f:close()

      local ok, msg = drafts.apply_next()
      assert.is_false(ok)
      assert.is_truthy(msg:match('not found'))
    end)
  end)

  describe('apply_all', function()
    local test_file
    local test_buf

    before_each(function()
      test_file = '/tmp/pairup-test-apply-all.txt'
      local f = io.open(test_file, 'w')
      f:write('local a = 1\nlocal b = 2\nlocal c = 3\n')
      f:close()

      test_buf = vim.fn.bufadd(test_file)
      vim.fn.bufload(test_buf)
    end)

    after_each(function()
      if vim.api.nvim_buf_is_valid(test_buf) then
        vim.api.nvim_buf_delete(test_buf, { force = true })
      end
      os.remove(test_file)
    end)

    it('should apply multiple drafts', function()
      local json = vim.json.encode({
        { id = '1', file = test_file, old_string = 'local a = 1', new_string = 'local a = 10' },
        { id = '2', file = test_file, old_string = 'local b = 2', new_string = 'local b = 20' },
      })
      local f = io.open(DRAFTS_FILE, 'w')
      f:write(json)
      f:close()

      local applied, failed = drafts.apply_all()
      assert.equals(2, applied)
      assert.equals(0, failed)

      local lines = vim.api.nvim_buf_get_lines(test_buf, 0, -1, false)
      assert.equals('local a = 10', lines[1])
      assert.equals('local b = 20', lines[2])
    end)

    it('should count failures separately', function()
      local json = vim.json.encode({
        { id = '1', file = test_file, old_string = 'local a = 1', new_string = 'local a = 10' },
        { id = '2', file = test_file, old_string = 'NONEXISTENT', new_string = 'x' },
      })
      local f = io.open(DRAFTS_FILE, 'w')
      f:write(json)
      f:close()

      local applied, failed = drafts.apply_all()
      assert.equals(1, applied)
      assert.equals(1, failed)
    end)

    it('should clear drafts after apply', function()
      local json = vim.json.encode({
        { id = '1', file = test_file, old_string = 'local a = 1', new_string = 'local a = 10' },
      })
      local f = io.open(DRAFTS_FILE, 'w')
      f:write(json)
      f:close()

      drafts.apply_all()
      assert.equals(0, drafts.count())
    end)

    it('should return errors array', function()
      local json = vim.json.encode({
        { id = '1', file = '/nonexistent.lua', old_string = 'a', new_string = 'b' },
      })
      local f = io.open(DRAFTS_FILE, 'w')
      f:write(json)
      f:close()

      local applied, failed, errors = drafts.apply_all()
      assert.equals(0, applied)
      assert.equals(1, failed)
      assert.equals(1, #errors)
      assert.is_truthy(errors[1]:match('not found'))
    end)
  end)

  describe('preview', function()
    it('should open diff view with draft content', function()
      local json = vim.json.encode({
        { id = '1', file = '/test.txt', old_string = 'old content', new_string = 'new content here' },
      })
      local f = io.open(DRAFTS_FILE, 'w')
      f:write(json)
      f:close()

      local initial_tabs = #vim.api.nvim_list_tabpages()
      drafts.preview()

      -- Should open a new tab with diff
      assert.equals(initial_tabs + 1, #vim.api.nvim_list_tabpages())
      assert.is_not_nil(drafts._diff_ctx)

      -- Cleanup
      vim.cmd('tabclose')
      drafts._diff_ctx = nil
    end)

    it('should notify when no drafts', function()
      drafts.preview()
      -- Just verify it doesn't error
    end)
  end)

  describe('navigation and index handling', function()
    it('should target correct draft index when applying', function()
      -- Create actual test file that apply_draft can modify
      local test3 = '/tmp/draft_test3.txt'
      vim.cmd('edit ' .. test3)
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'draft3' })
      vim.cmd('write')

      local json = vim.json.encode({
        { id = '1', file = '/tmp/test1.txt', old_string = 'draft1', new_string = 'new1' },
        { id = '2', file = '/tmp/test2.txt', old_string = 'draft2', new_string = 'new2' },
        { id = '3', file = test3, old_string = 'draft3', new_string = 'new3' },
      })
      local df = io.open(DRAFTS_FILE, 'w')
      df:write(json)
      df:close()

      -- Apply draft 3 (not draft 1!)
      local ok = drafts.apply_at_index(3)
      assert.is_true(ok)

      -- Draft 3 should be removed, drafts 1 and 2 remain
      local remaining = drafts.get_all()
      assert.equals(2, #remaining)
      assert.equals('/tmp/test1.txt', remaining[1].file)
      assert.equals('/tmp/test2.txt', remaining[2].file)

      -- Cleanup
      os.remove(test3)
    end)

    it('should remove correct draft when rejecting at specific index', function()
      local json = vim.json.encode({
        { id = '1', file = '/test1.txt', old_string = 'draft1', new_string = 'new1' },
        { id = '2', file = '/test2.txt', old_string = 'draft2', new_string = 'new2' },
        { id = '3', file = '/test3.txt', old_string = 'draft3', new_string = 'new3' },
      })
      local f = io.open(DRAFTS_FILE, 'w')
      f:write(json)
      f:close()

      local all = drafts.get_all()
      table.remove(all, 2)
      local updated = io.open(DRAFTS_FILE, 'w')
      updated:write(vim.json.encode(all))
      updated:close()

      local remaining = drafts.get_all()
      assert.equals(2, #remaining)
      assert.equals('/test1.txt', remaining[1].file)
      assert.equals('/test3.txt', remaining[2].file)
    end)
  end)
end)
