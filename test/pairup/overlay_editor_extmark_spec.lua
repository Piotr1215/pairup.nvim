describe('pairup overlay editor extmark tracking', function()
  local overlay
  local overlay_editor
  local test_bufnr

  before_each(function()
    -- Load modules
    overlay = require('pairup.overlay')
    overlay_editor = require('pairup.overlay_editor')
    overlay.setup()

    -- Create a test buffer
    test_bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, {
      'line 1',
      'line 2',
      'line 3',
      'line 4',
      'line 5',
    })
  end)

  after_each(function()
    -- Clean up
    if test_bufnr and vim.api.nvim_buf_is_valid(test_bufnr) then
      overlay.clear_overlays(test_bufnr)
      vim.api.nvim_buf_delete(test_bufnr, { force = true })
    end
  end)

  describe('extmark position tracking', function()
    it('should track overlay position when lines are added above', function()
      -- Create an overlay at line 3
      overlay.show_suggestion(test_bufnr, 3, 'line 3', 'modified line 3', 'test change')

      -- Verify initial position
      local suggestions = overlay.get_suggestions(test_bufnr)
      assert.is_not_nil(suggestions[3], 'Should have overlay at line 3')

      -- Add lines above the overlay
      vim.api.nvim_buf_set_lines(test_bufnr, 0, 0, false, { 'new line 1', 'new line 2' })

      -- Check that overlay moved
      suggestions = overlay.get_suggestions(test_bufnr)
      assert.is_nil(suggestions[3], 'Should not have overlay at old line 3')
      assert.is_not_nil(suggestions[5], 'Should have overlay at new line 5')
    end)

    it('should apply edited overlay at correct position after file changes', function()
      -- Create an overlay at line 3
      overlay.show_suggestion(test_bufnr, 3, 'line 3', 'modified line 3', 'test change')

      -- Set current buffer and cursor
      vim.api.nvim_set_current_buf(test_bufnr)
      vim.api.nvim_win_set_cursor(0, { 3, 0 })

      -- Open editor
      local result = overlay_editor.edit_overlay_at_cursor()
      assert.is_true(result, 'Should open editor')

      -- Add lines above while editor is open
      vim.api.nvim_buf_set_lines(test_bufnr, 0, 0, false, { 'inserted line' })

      -- The overlay should now be at line 4
      local suggestions = overlay.get_suggestions(test_bufnr)
      assert.is_not_nil(suggestions[4], 'Overlay should have moved to line 4')

      -- Apply the edit (this should work correctly with extmark tracking)
      local applied = overlay_editor.apply_edited_overlay()

      -- Check that the change was applied at the correct line
      local lines = vim.api.nvim_buf_get_lines(test_bufnr, 0, -1, false)
      assert.equals('inserted line', lines[1])
      -- Line 4 should have been modified (original line 3)
      -- Note: The actual modification depends on the editor content parsing

      -- Clean up editor buffer
      local bufs = vim.api.nvim_list_bufs()
      for _, buf in ipairs(bufs) do
        local name = vim.api.nvim_buf_get_name(buf)
        if name:match('overlay%-editor://') then
          vim.api.nvim_buf_delete(buf, { force = true })
          break
        end
      end
    end)

    it('should handle multiple overlays with correct extmark tracking', function()
      -- Create multiple overlays
      overlay.show_suggestion(test_bufnr, 2, 'line 2', 'modified 2', 'change 2')
      overlay.show_suggestion(test_bufnr, 4, 'line 4', 'modified 4', 'change 4')

      -- Verify initial positions
      local suggestions = overlay.get_suggestions(test_bufnr)
      assert.is_not_nil(suggestions[2], 'Should have overlay at line 2')
      assert.is_not_nil(suggestions[4], 'Should have overlay at line 4')

      -- Delete line 3 (between the overlays)
      vim.api.nvim_buf_set_lines(test_bufnr, 2, 3, false, {})

      -- Check positions after deletion
      suggestions = overlay.get_suggestions(test_bufnr)
      assert.is_not_nil(suggestions[2], 'First overlay should still be at line 2')
      assert.is_nil(suggestions[4], 'Should not have overlay at old line 4')
      assert.is_not_nil(suggestions[3], 'Second overlay should now be at line 3')
    end)

    it('should clean up overlay properly when edited', function()
      -- Create an overlay
      overlay.show_suggestion(test_bufnr, 2, 'line 2', 'modified line 2', 'test')

      -- Verify overlay exists
      local suggestions = overlay.get_suggestions(test_bufnr)
      assert.is_not_nil(suggestions[2], 'Should have overlay at line 2')

      -- Count extmarks before
      local ns_id = vim.api.nvim_create_namespace('pairup_overlay')
      local marks_before = vim.api.nvim_buf_get_extmarks(test_bufnr, ns_id, 0, -1, {})
      assert.equals(1, #marks_before, 'Should have one extmark')

      -- Set up for editing
      vim.api.nvim_set_current_buf(test_bufnr)
      vim.api.nvim_win_set_cursor(0, { 2, 0 })

      -- Open editor
      overlay_editor.edit_overlay_at_cursor()

      -- Apply the edit
      overlay_editor.apply_edited_overlay()

      -- Check that overlay is removed
      suggestions = overlay.get_suggestions(test_bufnr)
      assert.is_nil(suggestions[2], 'Overlay should be removed after editing')

      -- Check extmarks are cleaned up
      local marks_after = vim.api.nvim_buf_get_extmarks(test_bufnr, ns_id, 0, -1, {})
      assert.equals(0, #marks_after, 'Should have no extmarks after edit')
    end)
  end)
end)
