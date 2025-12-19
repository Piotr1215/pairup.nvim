describe('pairup.conflict', function()
  local conflict

  before_each(function()
    package.loaded['pairup.conflict'] = nil
    conflict = require('pairup.conflict')
  end)

  describe('find_block', function()
    it('should extract reason from PROPOSED marker', function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
        '<<<<<<< CURRENT',
        'old code',
        '=======',
        'new code',
        '>>>>>>> PROPOSED: portable shebang',
      })
      vim.api.nvim_set_current_buf(buf)
      vim.api.nvim_win_set_cursor(0, { 2, 0 })

      local block = conflict.find_block()

      assert.is_not_nil(block)
      assert.equals('portable shebang', block.reason)
      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it('should return empty reason when no text after PROPOSED', function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
        '<<<<<<< CURRENT',
        'old code',
        '=======',
        'new code',
        '>>>>>>> PROPOSED',
      })
      vim.api.nvim_set_current_buf(buf)
      vim.api.nvim_win_set_cursor(0, { 2, 0 })

      local block = conflict.find_block()

      assert.is_not_nil(block)
      assert.equals('', block.reason)
      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it('should detect in_current based on cursor position', function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
        '<<<<<<< CURRENT',
        'old code',
        '=======',
        'new code',
        '>>>>>>> PROPOSED: reason',
      })
      vim.api.nvim_set_current_buf(buf)

      vim.api.nvim_win_set_cursor(0, { 2, 0 })
      local block = conflict.find_block()
      assert.is_true(block.in_current)

      vim.api.nvim_win_set_cursor(0, { 4, 0 })
      block = conflict.find_block()
      assert.is_false(block.in_current)

      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it('should return nil when not inside a conflict', function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'just normal code' })
      vim.api.nvim_set_current_buf(buf)
      vim.api.nvim_win_set_cursor(0, { 1, 0 })

      local block = conflict.find_block()

      assert.is_nil(block)
      vim.api.nvim_buf_delete(buf, { force = true })
    end)
  end)

  describe('find_all', function()
    it('should use reason as preview when available', function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
        '<<<<<<< CURRENT',
        'old code here',
        '=======',
        'new code',
        '>>>>>>> PROPOSED: use env shebang',
      })

      local conflicts = conflict.find_all(buf)

      assert.equals(1, #conflicts)
      assert.equals('use env shebang', conflicts[1].reason)
      assert.equals('use env shebang', conflicts[1].preview)
      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it('should fallback to first line when no reason', function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
        '<<<<<<< CURRENT',
        'old code here',
        '=======',
        'new code',
        '>>>>>>> PROPOSED',
      })

      local conflicts = conflict.find_all(buf)

      assert.equals(1, #conflicts)
      assert.equals('', conflicts[1].reason)
      assert.equals('old code here', conflicts[1].preview)
      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it('should find multiple conflicts', function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
        '<<<<<<< CURRENT',
        'first old',
        '=======',
        'first new',
        '>>>>>>> PROPOSED: first change',
        '',
        '<<<<<<< CURRENT',
        'second old',
        '=======',
        'second new',
        '>>>>>>> PROPOSED: second change',
      })

      local conflicts = conflict.find_all(buf)

      assert.equals(2, #conflicts)
      assert.equals('first change', conflicts[1].reason)
      assert.equals('second change', conflicts[2].reason)
      assert.equals(1, conflicts[1].start_marker)
      assert.equals(7, conflicts[2].start_marker)
      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it('should truncate long previews', function()
      local buf = vim.api.nvim_create_buf(false, true)
      local long_reason = string.rep('x', 60)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
        '<<<<<<< CURRENT',
        'old',
        '=======',
        'new',
        '>>>>>>> PROPOSED: ' .. long_reason,
      })

      local conflicts = conflict.find_all(buf)

      assert.equals(50, #conflicts[1].preview)
      assert.is_truthy(conflicts[1].preview:match('%.%.%.$'))
      vim.api.nvim_buf_delete(buf, { force = true })
    end)
  end)

  describe('navigation', function()
    it('should jump to next proposal', function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
        'line 1',
        '<<<<<<< CURRENT',
        'old',
        '=======',
        'new',
        '>>>>>>> PROPOSED: first',
        'line 7',
        '<<<<<<< CURRENT',
        'old2',
        '=======',
        'new2',
        '>>>>>>> PROPOSED: second',
      })
      vim.api.nvim_set_current_buf(buf)
      vim.api.nvim_win_set_cursor(0, { 1, 0 })

      conflict.next()

      local cursor = vim.api.nvim_win_get_cursor(0)
      assert.equals(2, cursor[1])
      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it('should wrap to first proposal when at end', function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
        '<<<<<<< CURRENT',
        'old',
        '=======',
        'new',
        '>>>>>>> PROPOSED: only',
        'after',
      })
      vim.api.nvim_set_current_buf(buf)
      vim.api.nvim_win_set_cursor(0, { 6, 0 })

      conflict.next()

      local cursor = vim.api.nvim_win_get_cursor(0)
      assert.equals(1, cursor[1])
      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it('should jump to previous proposal', function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
        '<<<<<<< CURRENT',
        'old',
        '=======',
        'new',
        '>>>>>>> PROPOSED: first',
        'line 6',
        '<<<<<<< CURRENT',
        'old2',
        '=======',
        'new2',
        '>>>>>>> PROPOSED: second',
        'line 12',
      })
      vim.api.nvim_set_current_buf(buf)
      vim.api.nvim_win_set_cursor(0, { 12, 0 })

      conflict.prev()

      local cursor = vim.api.nvim_win_get_cursor(0)
      assert.equals(7, cursor[1])
      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it('should wrap to last proposal when at start', function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
        'before',
        '<<<<<<< CURRENT',
        'old',
        '=======',
        'new',
        '>>>>>>> PROPOSED: only',
      })
      vim.api.nvim_set_current_buf(buf)
      vim.api.nvim_win_set_cursor(0, { 1, 0 })

      conflict.prev()

      local cursor = vim.api.nvim_win_get_cursor(0)
      assert.equals(2, cursor[1])
      vim.api.nvim_buf_delete(buf, { force = true })
    end)
  end)

  describe('diff context', function()
    it('should store diff context for accept_from_diff', function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
        '<<<<<<< CURRENT',
        'current line 1',
        'current line 2',
        '=======',
        'proposed line 1',
        '>>>>>>> PROPOSED: test reason',
      })
      vim.api.nvim_set_current_buf(buf)
      vim.api.nvim_win_set_cursor(0, { 2, 0 })

      local block = conflict.find_block()

      assert.equals(1, block.start_marker)
      assert.equals(4, block.separator)
      assert.equals(6, block.end_marker)
      assert.equals('test reason', block.reason)
      vim.api.nvim_buf_delete(buf, { force = true })
    end)
  end)

  describe('accept', function()
    it('should accept CURRENT when cursor in current section', function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
        'before',
        '<<<<<<< CURRENT',
        'keep this',
        '=======',
        'discard this',
        '>>>>>>> PROPOSED: reason',
        'after',
      })
      vim.api.nvim_set_current_buf(buf)
      vim.api.nvim_win_set_cursor(0, { 3, 0 })

      conflict.accept()

      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      assert.equals(3, #lines)
      assert.equals('before', lines[1])
      assert.equals('keep this', lines[2])
      assert.equals('after', lines[3])
      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it('should accept PROPOSED when cursor in proposed section', function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
        'before',
        '<<<<<<< CURRENT',
        'discard this',
        '=======',
        'keep this',
        '>>>>>>> PROPOSED: reason',
        'after',
      })
      vim.api.nvim_set_current_buf(buf)
      vim.api.nvim_win_set_cursor(0, { 5, 0 })

      conflict.accept()

      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      assert.equals(3, #lines)
      assert.equals('before', lines[1])
      assert.equals('keep this', lines[2])
      assert.equals('after', lines[3])
      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it('should handle multi-line sections', function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
        '<<<<<<< CURRENT',
        'line 1',
        'line 2',
        '=======',
        'new line 1',
        'new line 2',
        'new line 3',
        '>>>>>>> PROPOSED: multi-line',
      })
      vim.api.nvim_set_current_buf(buf)
      vim.api.nvim_win_set_cursor(0, { 5, 0 })

      conflict.accept()

      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      assert.equals(3, #lines)
      assert.equals('new line 1', lines[1])
      assert.equals('new line 2', lines[2])
      assert.equals('new line 3', lines[3])
      vim.api.nvim_buf_delete(buf, { force = true })
    end)
  end)
end)
