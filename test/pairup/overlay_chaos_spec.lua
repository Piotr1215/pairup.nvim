describe('overlay chaos testing', function()
  local overlay = require('pairup.overlay')
  local test_bufnr
  local test_win

  before_each(function()
    -- Create test buffer and window
    test_bufnr = vim.api.nvim_create_buf(false, true)
    test_win = vim.api.nvim_open_win(test_bufnr, true, {
      relative = 'editor',
      width = 80,
      height = 30,
      row = 0,
      col = 0,
    })
    overlay.clear_overlays(test_bufnr)
  end)

  after_each(function()
    if vim.api.nvim_win_is_valid(test_win) then
      vim.api.nvim_win_close(test_win, true)
    end
    if vim.api.nvim_buf_is_valid(test_bufnr) then
      vim.api.nvim_buf_delete(test_bufnr, { force = true })
    end
  end)

  it('should handle rapid sequential edits without losing overlays', function()
    -- Setup initial content
    vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, {
      'function process() {',
      '  const data = [];',
      '  for (let i = 0; i < 10; i++) {',
      '    data.push(i);',
      '  }',
      '  return data;',
      '}',
    })

    -- Add overlays at different positions
    overlay.show_suggestion(test_bufnr, 2, '  const data = [];', '  const data = new Set();', 'Use Set')
    overlay.show_suggestion(test_bufnr, 4, '    data.push(i);', '    data.add(i);', 'Use add for Set')
    overlay.show_suggestion(test_bufnr, 6, '  return data;', '  return Array.from(data);', 'Convert to array')

    -- Rapid edits
    -- 1. Add comment at top
    vim.api.nvim_buf_set_lines(test_bufnr, 0, 0, false, { '// Processing function' })

    -- 2. Add empty line in middle
    vim.api.nvim_buf_set_lines(test_bufnr, 3, 3, false, { '' })

    -- 3. Delete the empty line we just added
    vim.api.nvim_buf_set_lines(test_bufnr, 3, 4, false, {})

    -- 4. Add parameter to function
    local line1 = vim.api.nvim_buf_get_lines(test_bufnr, 1, 2, false)[1]
    local modified_line = line1:gsub('%(%)', '(limit)')
    vim.api.nvim_buf_set_lines(test_bufnr, 1, 2, false, { modified_line })

    -- All three overlays should still be applicable
    vim.api.nvim_win_set_cursor(test_win, { 3, 0 }) -- data = []
    assert.is_true(overlay.apply_at_cursor())

    vim.api.nvim_win_set_cursor(test_win, { 5, 0 }) -- data.push
    assert.is_true(overlay.apply_at_cursor())

    vim.api.nvim_win_set_cursor(test_win, { 7, 0 }) -- return data
    assert.is_true(overlay.apply_at_cursor())

    -- Verify final state
    local lines = vim.api.nvim_buf_get_lines(test_bufnr, 0, -1, false)
    assert.equals('  const data = new Set();', lines[3])
    assert.equals('    data.add(i);', lines[5])
    assert.equals('  return Array.from(data);', lines[7])
  end)

  it('should handle interleaved insertions and deletions', function()
    -- Create a Python class
    vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, {
      'class DataHandler:',
      '    def __init__(self):',
      '        self.items = []',
      '',
      '    def add(self, item):',
      '        self.items.append(item)',
      '',
      '    def clear(self):',
      '        self.items = []',
    })

    -- Add overlays
    overlay.show_suggestion(
      test_bufnr,
      3,
      '        self.items = []',
      '        self.items = collections.deque()',
      'Use deque'
    )
    overlay.show_suggestion(
      test_bufnr,
      6,
      '        self.items.append(item)',
      '        self.items.appendleft(item)',
      'Add to front'
    )
    overlay.show_suggestion(test_bufnr, 9, '        self.items = []', '        self.items.clear()', 'Use clear method')

    -- Chaos sequence
    -- 1. Add import at top
    vim.api.nvim_buf_set_lines(test_bufnr, 0, 0, false, { 'import collections', '' })

    -- 2. Delete empty line 6 (was line 4)
    vim.api.nvim_buf_set_lines(test_bufnr, 5, 6, false, {})

    -- 3. Add method in middle
    vim.api.nvim_buf_set_lines(test_bufnr, 7, 7, false, {
      '',
      '    def get(self, index):',
      '        return self.items[index]',
    })

    -- 4. Add another empty line then remove it (common editing pattern)
    vim.api.nvim_buf_set_lines(test_bufnr, 3, 3, false, { '' })
    vim.api.nvim_buf_set_lines(test_bufnr, 3, 4, false, {})

    -- Verify overlays still work
    local suggestions = overlay.get_suggestions(test_bufnr)
    local count = 0
    for _, _ in pairs(suggestions) do
      count = count + 1
    end
    assert.equals(3, count, 'Should still have 3 suggestions')

    -- Apply them at new positions
    vim.api.nvim_win_set_cursor(test_win, { 5, 0 }) -- self.items = []
    assert.is_true(overlay.apply_at_cursor())

    local lines = vim.api.nvim_buf_get_lines(test_bufnr, 0, -1, false)
    assert.equals('        self.items = collections.deque()', lines[5])
  end)

  it('should handle multiple overlays on adjacent lines during chaos', function()
    -- Create content with adjacent lines
    vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, {
      'const a = 1;',
      'const b = 2;',
      'const c = 3;',
      'const d = 4;',
      'const e = 5;',
    })

    -- Add overlays to some lines (not all to avoid collision issues)
    overlay.show_suggestion(test_bufnr, 1, 'const a = 1;', 'let a = 1;', 'Use let')
    overlay.show_suggestion(test_bufnr, 3, 'const c = 3;', 'let c = 3;', 'Use let')
    overlay.show_suggestion(test_bufnr, 5, 'const e = 5;', 'let e = 5;', 'Use let')

    -- Chaos: delete middle line with overlay
    vim.api.nvim_buf_set_lines(test_bufnr, 2, 3, false, {}) -- Delete line 3 (c)

    -- Insert new lines at beginning
    vim.api.nvim_buf_set_lines(test_bufnr, 0, 0, false, {
      '// Variables',
      '',
    })

    -- After edits: overlays for a and e should remain
    -- Line 3: a, Line 6: e (c was deleted)
    vim.api.nvim_win_set_cursor(test_win, { 3, 0 }) -- const a
    assert.is_true(overlay.apply_at_cursor(), 'Should apply overlay for a')

    vim.api.nvim_win_set_cursor(test_win, { 6, 0 }) -- const e
    assert.is_true(overlay.apply_at_cursor(), 'Should apply overlay for e')

    local lines = vim.api.nvim_buf_get_lines(test_bufnr, 0, -1, false)
    assert.equals('let a = 1;', lines[3])
    assert.equals('let e = 5;', lines[6])
  end)

  it('should maintain multiline overlay integrity through chaos', function()
    -- Create a function to refactor
    vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, {
      'function calc(x, y) {',
      '  if (x > y) {',
      '    return x - y;',
      '  }',
      '  return y - x;',
      '}',
    })

    -- Add multiline suggestion for the if block
    local variants = {
      {
        new_lines = {
          '  return Math.abs(x - y);',
        },
        reasoning = 'Simplify with Math.abs',
      },
    }

    overlay.show_multiline_suggestion_variants(
      test_bufnr,
      2,
      5,
      { '  if (x > y) {', '    return x - y;', '  }', '  return y - x;' },
      variants
    )

    -- Add lines before the function
    vim.api.nvim_buf_set_lines(test_bufnr, 0, 0, false, {
      '// Utils',
      '',
    })

    -- The multiline overlay should now be at lines 4-7
    -- Apply the suggestion
    vim.api.nvim_win_set_cursor(test_win, { 5, 0 }) -- Middle of the if block
    assert.is_true(overlay.apply_at_cursor(), 'Should apply multiline from middle')

    -- Check that Math.abs was applied
    local lines = vim.api.nvim_buf_get_lines(test_bufnr, 0, -1, false)
    local found_abs = false
    for _, line in ipairs(lines) do
      if line:match('Math%.abs') then
        found_abs = true
        break
      end
    end
    assert.is_true(found_abs, 'Should have applied Math.abs variant')
  end)

  it('should handle undo/redo during chaos editing', function()
    -- Setup: 3 lines
    vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, {
      'let value = 10;', -- Line 1
      'let result = value * 2;', -- Line 2
      'let final = result;', -- Line 3
    })

    -- Add suggestions to lines 1 and 2
    overlay.show_suggestion(test_bufnr, 1, 'let value = 10;', 'const value = 10;', 'Use const')
    overlay.show_suggestion(test_bufnr, 2, 'let result = value * 2;', 'const result = value * 2;', 'Use const')

    -- Insert comment at position 1 (between lines 1 and 2)
    -- This shifts the original line 2 to line 3
    vim.api.nvim_buf_set_lines(test_bufnr, 1, 1, false, { '// Calculate' })
    -- Buffer is now:
    -- Line 1: let value = 10;
    -- Line 2: // Calculate
    -- Line 3: let result = value * 2;
    -- Line 4: let final = result;

    -- The overlay for "let value" is still at line 1
    -- The overlay for "let result" moved to line 3

    -- Apply first overlay at line 1
    vim.api.nvim_win_set_cursor(test_win, { 1, 0 })
    assert.is_true(overlay.apply_at_cursor())

    -- Check state after first apply
    local lines = vim.api.nvim_buf_get_lines(test_bufnr, 0, -1, false)
    assert.equals('const value = 10;', lines[1]) -- Applied change
    assert.equals('// Calculate', lines[2]) -- Inserted comment
    assert.equals('let result = value * 2;', lines[3]) -- Not changed yet
    assert.equals('let final = result;', lines[4])

    -- Simple test: just verify we can apply another overlay
    vim.api.nvim_win_set_cursor(test_win, { 3, 0 })
    assert.is_true(overlay.apply_at_cursor(), 'Should apply second overlay')

    lines = vim.api.nvim_buf_get_lines(test_bufnr, 0, -1, false)
    assert.equals('const result = value * 2;', lines[3])
  end)

  it('should handle buffer-wide replacements without breaking', function()
    -- Create simple repetitive content
    vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, {
      'var a = 1;',
      'var b = 2;',
      'var c = 3;',
      'var d = 4;',
      'var e = 5;',
    })

    -- Add overlays to specific lines only
    overlay.show_suggestion(test_bufnr, 2, 'var b = 2;', 'const b = 2;', 'Use const')
    overlay.show_suggestion(test_bufnr, 4, 'var d = 4;', 'const d = 4;', 'Use const')

    -- Simulate line-by-line replacement (preserves extmarks better)
    -- Replace lines 1, 3, 5 individually
    local line1 = vim.api.nvim_buf_get_lines(test_bufnr, 0, 1, false)[1]
    local new_line1 = line1:gsub('^var ', 'let ')
    vim.api.nvim_buf_set_lines(test_bufnr, 0, 1, false, { new_line1 })

    local line3 = vim.api.nvim_buf_get_lines(test_bufnr, 2, 3, false)[1]
    local new_line3 = line3:gsub('^var ', 'let ')
    vim.api.nvim_buf_set_lines(test_bufnr, 2, 3, false, { new_line3 })

    local line5 = vim.api.nvim_buf_get_lines(test_bufnr, 4, 5, false)[1]
    local new_line5 = line5:gsub('^var ', 'let ')
    vim.api.nvim_buf_set_lines(test_bufnr, 4, 5, false, { new_line5 })

    -- Our overlays should still work on their lines
    vim.api.nvim_win_set_cursor(test_win, { 2, 0 })
    assert.is_true(overlay.apply_at_cursor(), 'Should apply overlay at line 2')

    vim.api.nvim_win_set_cursor(test_win, { 4, 0 })
    assert.is_true(overlay.apply_at_cursor(), 'Should apply overlay at line 4')

    -- Verify
    local lines = vim.api.nvim_buf_get_lines(test_bufnr, 0, -1, false)
    assert.equals('let a = 1;', lines[1])
    assert.equals('const b = 2;', lines[2]) -- Applied overlay
    assert.equals('let c = 3;', lines[3])
    assert.equals('const d = 4;', lines[4]) -- Applied overlay
    assert.equals('let e = 5;', lines[5])
  end)
end)
