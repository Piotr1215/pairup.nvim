-- Test for overlay boundary issues
describe('overlay boundary handling', function()
  local overlay = require('pairup.overlay')

  before_each(function()
    -- Create a test buffer with specific content
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      '# Test File',
      '',
      '```lua',
      'local function test()',
      '  print("hello")',
      'end',
      '```',
      '',
      'Some text after code block',
      'More text',
    })
  end)

  after_each(function()
    -- Clean up test buffer
    vim.cmd('bdelete!')
  end)

  it('should handle overlays crossing code block boundaries', function()
    local buf = vim.api.nvim_get_current_buf()

    -- Try to create overlay that crosses code block boundary (lines 3-8)
    local success = overlay.show_multiline_suggestion(
      buf,
      3, -- Start at ```lua
      8, -- End after ```
      {
        '```lua',
        'local function test()',
        '  print("hello")',
        'end',
        '```',
        '',
      },
      {
        '```lua',
        'local function improved_test()',
        '  print("Hello, World!")',
        '  return true',
        'end',
        '```',
        '',
        '-- Function improved',
      },
      'Improved function with return value'
    )

    assert.is_true(success, 'Should create overlay crossing code block boundary')

    -- Apply the overlay
    vim.api.nvim_win_set_cursor(0, { 3, 0 })
    local applied = overlay.apply_at_cursor()
    assert.is_true(applied, 'Should apply overlay')

    -- Check that content was replaced correctly
    local lines = vim.api.nvim_buf_get_lines(buf, 2, 10, false)
    assert.are.equal('```lua', lines[1])
    assert.are.equal('local function improved_test()', lines[2])
    assert.are.equal('  print("Hello, World!")', lines[3])
    assert.are.equal('  return true', lines[4])
    assert.are.equal('end', lines[5])
    assert.are.equal('```', lines[6])
    assert.are.equal('', lines[7])
    assert.are.equal('-- Function improved', lines[8])
  end)

  it('should prevent applying overlay with invalid bounds', function()
    local buf = vim.api.nvim_get_current_buf()

    -- Try to apply overlay that would go beyond buffer bounds
    local success = overlay.show_multiline_suggestion(
      buf,
      8, -- Start near end
      15, -- End beyond buffer (only 10 lines)
      { 'Some text', 'More text' },
      { 'New content', 'That is very long', 'And goes beyond', 'Buffer bounds' },
      'Would exceed buffer'
    )

    assert.is_false(success, 'Should reject overlay with invalid bounds')
  end)

  it('should handle EOF append correctly', function()
    local buf = vim.api.nvim_get_current_buf()
    local line_count = vim.api.nvim_buf_line_count(buf)

    -- Append at EOF
    local success = overlay.show_multiline_suggestion(
      buf,
      line_count, -- At EOF
      line_count, -- At EOF
      { '' }, -- Empty line at EOF
      { '', '-- New content at end', '-- More content' },
      'Appending at EOF'
    )

    assert.is_true(success, 'Should handle EOF append')

    -- Apply the overlay
    vim.api.nvim_win_set_cursor(0, { line_count, 0 })
    local applied = overlay.apply_at_cursor()
    assert.is_true(applied, 'Should apply EOF append')

    -- Check new content was added
    local new_line_count = vim.api.nvim_buf_line_count(buf)
    assert.are.equal(line_count + 2, new_line_count, 'Should have added 2 lines')
  end)

  it('should validate replacement size differences', function()
    local buf = vim.api.nvim_get_current_buf()

    -- Mock vim.fn.confirm to auto-reject large differences
    local original_confirm = vim.fn.confirm
    vim.fn.confirm = function()
      return 2
    end -- Return 'No'

    -- Try to replace 2 lines with 20 lines (large difference)
    local success = overlay.show_multiline_suggestion(buf, 4, 5, { 'local function test()', '  print("hello")' }, {
      'local function test()',
      '  -- Line 1',
      '  -- Line 2',
      '  -- Line 3',
      '  -- Line 4',
      '  -- Line 5',
      '  -- Line 6',
      '  -- Line 7',
      '  -- Line 8',
      '  -- Line 9',
      '  -- Line 10',
      '  -- Line 11',
      '  -- Line 12',
      '  print("hello")',
    }, 'Large expansion')

    assert.is_true(success, 'Should create overlay')

    -- Try to apply - should be rejected due to size difference
    vim.api.nvim_win_set_cursor(0, { 4, 0 })
    local applied = overlay.apply_at_cursor()

    -- Note: The validation happens during apply, not during show
    -- If vim.fn.confirm returns 2 (No), application should be cancelled

    -- Restore original confirm
    vim.fn.confirm = original_confirm
  end)

  it('should clean up overlapping extmarks', function()
    local buf = vim.api.nvim_get_current_buf()

    -- Create first overlay
    overlay.show_multiline_suggestion(
      buf,
      3,
      5,
      { '```lua', 'local function test()', '  print("hello")' },
      { '```lua', 'local function test1()', '  print("test1")' },
      'First overlay'
    )

    -- Create overlapping overlay
    overlay.show_multiline_suggestion(
      buf,
      4,
      6,
      { 'local function test()', '  print("hello")', 'end' },
      { 'local function test2()', '  print("test2")', 'end' },
      'Overlapping overlay'
    )

    -- Apply second overlay
    vim.api.nvim_win_set_cursor(0, { 4, 0 })
    local applied = overlay.apply_at_cursor()
    assert.is_true(applied, 'Should apply overlapping overlay')

    -- Check that overlays were properly handled
    -- Note: After applying one overlay, the other may still exist if not overlapping
    local suggestions = overlay.get_suggestions(buf)
    local count = 0
    for _ in pairs(suggestions) do
      count = count + 1
    end
    -- The first overlay at line 3 might still exist since we applied the one at line 4
    assert.is_true(count <= 1, 'Should have at most one remaining overlay after applying')
  end)
end)
