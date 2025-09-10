describe('overlay line shifting', function()
  local overlay = require('pairup.overlay')
  local test_bufnr
  local test_win

  before_each(function()
    -- Create a test buffer
    test_bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, {
      'line 1',
      'line 2',
      'line 3',
      'line 4',
      'line 5',
    })

    -- Create a window for the buffer
    test_win = vim.api.nvim_open_win(test_bufnr, true, {
      relative = 'editor',
      width = 80,
      height = 20,
      row = 0,
      col = 0,
    })

    -- Clear any existing overlays
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

  it('should track overlays when lines are inserted above', function()
    -- Create overlays at lines 2 and 4
    overlay.show_suggestion(test_bufnr, 2, 'line 2', 'changed line 2', 'Update line 2')
    overlay.show_suggestion(test_bufnr, 4, 'line 4', 'changed line 4', 'Update line 4')

    -- Insert lines at position 2 (will shift everything down)
    vim.api.nvim_buf_set_lines(test_bufnr, 1, 1, false, {
      'inserted A',
      'inserted B',
    })

    -- Lines should now be:
    -- 1: line 1
    -- 2: inserted A
    -- 3: inserted B
    -- 4: line 2 (was line 2, overlay should be here)
    -- 5: line 3
    -- 6: line 4 (was line 4, overlay should be here)
    -- 7: line 5

    -- Move cursor to line 4 (where old line 2 is now)
    vim.api.nvim_win_set_cursor(test_win, { 4, 0 })

    -- Should be able to apply the overlay that was on line 2
    local success = overlay.apply_at_cursor()
    assert.is_true(success)

    local lines = vim.api.nvim_buf_get_lines(test_bufnr, 0, -1, false)
    assert.are.equal('changed line 2', lines[4])

    -- Move cursor to line 6 (where old line 4 is now)
    vim.api.nvim_win_set_cursor(test_win, { 6, 0 })

    -- Should be able to apply the overlay that was on line 4
    success = overlay.apply_at_cursor()
    assert.is_true(success)

    lines = vim.api.nvim_buf_get_lines(test_bufnr, 0, -1, false)
    assert.are.equal('changed line 4', lines[6])
  end)

  it('should track multiline overlays when lines shift', function()
    -- Create a multiline overlay at lines 2-3
    local variants = {
      {
        new_lines = {
          'expanded line 2',
          'additional line A',
          'additional line B',
        },
        reasoning = 'Expand content',
      },
    }
    overlay.show_multiline_suggestion_variants(test_bufnr, 2, 3, { 'line 2', 'line 3' }, variants)

    -- Insert a line at the beginning
    vim.api.nvim_buf_set_lines(test_bufnr, 0, 0, false, { 'inserted at top' })

    -- Lines should now be:
    -- 1: inserted at top
    -- 2: line 1
    -- 3: line 2 (multiline overlay should be here)
    -- 4: line 3
    -- 5: line 4
    -- 6: line 5

    -- Move cursor to line 3 (where the multiline overlay should be)
    vim.api.nvim_win_set_cursor(test_win, { 3, 0 })

    -- Should be able to apply the multiline overlay
    local success = overlay.apply_at_cursor()
    assert.is_true(success)

    local lines = vim.api.nvim_buf_get_lines(test_bufnr, 0, -1, false)
    assert.are.equal('inserted at top', lines[1])
    assert.are.equal('line 1', lines[2])
    assert.are.equal('expanded line 2', lines[3])
    assert.are.equal('additional line A', lines[4])
    assert.are.equal('additional line B', lines[5])
    assert.are.equal('line 4', lines[6])
  end)

  it('should handle deletion of lines between overlays', function()
    -- Create overlays at lines 2 and 5
    overlay.show_suggestion(test_bufnr, 2, 'line 2', 'modified 2')
    overlay.show_suggestion(test_bufnr, 5, 'line 5', 'modified 5')

    -- Delete line 3 and 4
    vim.api.nvim_buf_set_lines(test_bufnr, 2, 4, false, {})

    -- Lines should now be:
    -- 1: line 1
    -- 2: line 2 (overlay should still be here)
    -- 3: line 5 (was line 5, overlay should be here)

    -- Check line 2 overlay
    vim.api.nvim_win_set_cursor(test_win, { 2, 0 })
    local success = overlay.apply_at_cursor()
    assert.is_true(success)

    local lines = vim.api.nvim_buf_get_lines(test_bufnr, 0, -1, false)
    assert.are.equal('modified 2', lines[2])

    -- Check that the overlay that was on line 5 is now on line 3
    vim.api.nvim_win_set_cursor(test_win, { 3, 0 })
    success = overlay.apply_at_cursor()
    assert.is_true(success)

    lines = vim.api.nvim_buf_get_lines(test_bufnr, 0, -1, false)
    assert.are.equal('modified 5', lines[3])
  end)

  it('should handle complex line shifting with variants', function()
    -- Create overlays with variants
    local variants1 = {
      { new_text = 'variant 1a', reasoning = 'Option A' },
      { new_text = 'variant 1b', reasoning = 'Option B' },
      { new_text = 'variant 1c', reasoning = 'Option C' },
    }
    overlay.show_suggestion_variants(test_bufnr, 2, 'line 2', variants1)

    local variants2 = {
      { new_text = 'variant 2a', reasoning = 'Choice A' },
      { new_text = 'variant 2b', reasoning = 'Choice B' },
    }
    overlay.show_suggestion_variants(test_bufnr, 4, 'line 4', variants2)

    -- Cycle to 3rd variant on line 2
    overlay.cycle_variant(test_bufnr, 2, 1)
    overlay.cycle_variant(test_bufnr, 2, 1)

    -- Insert multiple lines at position 3
    vim.api.nvim_buf_set_lines(test_bufnr, 2, 2, false, {
      'new A',
      'new B',
      'new C',
    })

    -- Lines are now:
    -- 1: line 1
    -- 2: line 2 (variant overlay with 3rd variant selected)
    -- 3: new A
    -- 4: new B
    -- 5: new C
    -- 6: line 3
    -- 7: line 4 (variant overlay)
    -- 8: line 5

    -- Apply the variant at line 2 (should apply 3rd variant)
    vim.api.nvim_win_set_cursor(test_win, { 2, 0 })
    local success = overlay.apply_at_cursor()
    assert.is_true(success)

    local lines = vim.api.nvim_buf_get_lines(test_bufnr, 0, -1, false)
    assert.are.equal('variant 1c', lines[2])

    -- Apply variant at line 7 (was line 4)
    vim.api.nvim_win_set_cursor(test_win, { 7, 0 })
    success = overlay.apply_at_cursor()
    assert.is_true(success)

    lines = vim.api.nvim_buf_get_lines(test_bufnr, 0, -1, false)
    assert.are.equal('variant 2a', lines[7])
  end)
end)
