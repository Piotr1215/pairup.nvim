-- Test for overlay tracking when lines move (extmark stability)
describe('overlay line tracking bug', function()
  local overlay
  local bufnr

  before_each(function()
    -- Load overlay module
    package.loaded['pairup.overlay'] = nil
    overlay = require('pairup.overlay')

    -- Create test buffer
    bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(bufnr)

    -- Add initial content
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      'line 1',
      'line 2',
      'line 3',
      'line 4',
      'line 5',
    })
  end)

  after_each(function()
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end)

  it('should track overlays correctly when lines are inserted above', function()
    -- Create overlay on line 3
    overlay.show_suggestion(bufnr, 3, 'line 3', 'modified line 3', 'Test change')

    -- Verify overlay exists at line 3
    local suggestions = overlay.get_suggestions(bufnr)
    assert.is_not_nil(suggestions[3], 'Overlay should exist at line 3')
    assert.equals('modified line 3', suggestions[3].new_text)

    -- Insert new lines at the beginning (this will shift everything down)
    vim.api.nvim_buf_set_lines(bufnr, 0, 0, false, { 'new line 1', 'new line 2' })

    -- The overlay should now be at line 5 (3 + 2 new lines)
    suggestions = overlay.get_suggestions(bufnr)

    -- This is the key test - overlay should have moved with the text
    assert.is_nil(suggestions[3], 'Overlay should not be at original line 3')
    assert.is_not_nil(suggestions[5], 'Overlay should have moved to line 5')
    assert.equals('modified line 3', suggestions[5].new_text)

    -- Verify we can still apply the overlay at its new position
    vim.api.nvim_win_set_cursor(0, { 5, 0 })
    local result = overlay.apply_at_cursor()
    assert.is_true(result, 'Should be able to apply overlay at new position')

    -- Check the buffer content
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    assert.equals('modified line 3', lines[5])
  end)

  it('should track overlays when lines are deleted above', function()
    -- Create overlay on line 5
    overlay.show_suggestion(bufnr, 5, 'line 5', 'modified line 5', 'Test change')

    -- Delete lines 2 and 3
    vim.api.nvim_buf_set_lines(bufnr, 1, 3, false, {})

    -- The overlay should now be at line 3 (5 - 2 deleted lines)
    local suggestions = overlay.get_suggestions(bufnr)
    assert.is_nil(suggestions[5], 'Overlay should not be at original line 5')
    assert.is_not_nil(suggestions[3], 'Overlay should have moved to line 3')
    assert.equals('modified line 5', suggestions[3].new_text)
  end)

  it('should handle multiple overlays moving together', function()
    -- Create overlays on lines 2 and 4
    overlay.show_suggestion(bufnr, 2, 'line 2', 'modified line 2', 'Change 1')
    overlay.show_suggestion(bufnr, 4, 'line 4', 'modified line 4', 'Change 2')

    -- Insert a line at the beginning
    vim.api.nvim_buf_set_lines(bufnr, 0, 0, false, { 'inserted line' })

    -- Both overlays should have moved down by 1
    local suggestions = overlay.get_suggestions(bufnr)
    assert.is_not_nil(suggestions[3], 'First overlay should be at line 3')
    assert.is_not_nil(suggestions[5], 'Second overlay should be at line 5')
    assert.equals('modified line 2', suggestions[3].new_text)
    assert.equals('modified line 4', suggestions[5].new_text)
  end)
end)
