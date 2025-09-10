describe('pairup overlay editor', function()
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
      'function test() {',
      '  console.log("hello");',
      '  return true;',
      '}',
    })
  end)

  after_each(function()
    -- Clean up
    if test_bufnr and vim.api.nvim_buf_is_valid(test_bufnr) then
      overlay.clear_overlays(test_bufnr)
      vim.api.nvim_buf_delete(test_bufnr, { force = true })
    end
  end)

  describe('edit overlay functionality', function()
    it('should open editor for overlay at cursor', function()
      -- Create an overlay
      overlay.show_suggestion(
        test_bufnr,
        2,
        '  console.log("hello");',
        '  console.debug("hello");',
        'Use debug for development'
      )

      -- Set current buffer and cursor
      vim.api.nvim_set_current_buf(test_bufnr)
      vim.api.nvim_win_set_cursor(0, { 2, 0 })

      -- Open editor
      local result = overlay_editor.edit_overlay_at_cursor()
      assert.is_true(result, 'Should successfully open editor')

      -- Check that editor buffer was created
      local bufs = vim.api.nvim_list_bufs()
      local editor_buf = nil
      for _, buf in ipairs(bufs) do
        local name = vim.api.nvim_buf_get_name(buf)
        if name:match('overlay%-editor://') then
          editor_buf = buf
          break
        end
      end

      assert.is_not_nil(editor_buf, 'Editor buffer should be created')

      -- Clean up editor buffer
      if editor_buf then
        vim.api.nvim_buf_delete(editor_buf, { force = true })
      end
    end)

    it('should handle no overlay at cursor gracefully', function()
      -- Set current buffer and cursor to line without overlay
      vim.api.nvim_set_current_buf(test_bufnr)
      vim.api.nvim_win_set_cursor(0, { 1, 0 })

      -- Try to open editor
      local result = overlay_editor.edit_overlay_at_cursor()
      assert.is_false(result, 'Should return false when no overlay')
    end)

    it('should clear overlay at specific line', function()
      -- Create an overlay
      overlay.show_suggestion(test_bufnr, 2, '  console.log("hello");', '  console.debug("hello");')

      -- Verify overlay exists
      local suggestions = overlay.get_suggestions(test_bufnr)
      assert.is_not_nil(suggestions[2], 'Should have overlay at line 2')

      -- Clear it
      overlay.clear_overlay_at_line(test_bufnr, 2)

      -- Verify it's gone
      suggestions = overlay.get_suggestions(test_bufnr)
      assert.is_nil(suggestions[2], 'Should have cleared overlay at line 2')
    end)
  end)

  describe('multiline overlay editing', function()
    it('should handle multiline suggestions in editor', function()
      -- Create multiline overlay
      local old_lines = {
        '  console.log("hello");',
        '  return true;',
      }
      local new_lines = {
        '  console.debug("hello");',
        '  console.info("processing");',
        '  return false;',
      }

      overlay.show_multiline_suggestion(test_bufnr, 2, 3, old_lines, new_lines, 'Debug mode changes')

      -- Set current buffer and cursor
      vim.api.nvim_set_current_buf(test_bufnr)
      vim.api.nvim_win_set_cursor(0, { 2, 0 })

      -- Open editor
      local result = overlay_editor.edit_overlay_at_cursor()
      assert.is_true(result, 'Should open editor for multiline overlay')

      -- Clean up
      local bufs = vim.api.nvim_list_bufs()
      for _, buf in ipairs(bufs) do
        local name = vim.api.nvim_buf_get_name(buf)
        if name:match('overlay%-editor://') then
          vim.api.nvim_buf_delete(buf, { force = true })
          break
        end
      end
    end)
  end)
end)
