describe('pairup overlay edge cases', function()
  local overlay
  local test_bufnr

  before_each(function()
    overlay = require('pairup.overlay')
    overlay.setup()

    test_bufnr = vim.api.nvim_create_buf(false, true)
  end)

  after_each(function()
    if test_bufnr and vim.api.nvim_buf_is_valid(test_bufnr) then
      overlay.clear_overlays(test_bufnr)
      vim.api.nvim_buf_delete(test_bufnr, { force = true })
    end
  end)

  describe('empty lines handling', function()
    it('should handle suggestions with empty lines in the middle', function()
      vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, {
        'line 1',
        'line 2',
        'line 3',
        'line 4',
        'line 5',
      })

      local old_lines = {
        'line 2',
        'line 3',
        'line 4',
      }

      local variants = {
        {
          new_lines = {
            'modified line 2',
            '', -- Empty line in middle
            'modified line 4',
          },
          reasoning = 'Add spacing',
        },
        {
          new_lines = {
            '', -- Start with empty
            'centered',
            '', -- End with empty
          },
          reasoning = 'Centered with blanks',
        },
      }

      overlay.show_multiline_suggestion_variants(test_bufnr, 2, 4, old_lines, variants)

      -- Apply the first variant
      vim.api.nvim_set_current_buf(test_bufnr)
      vim.api.nvim_win_set_cursor(0, { 2, 0 })
      overlay.apply_at_cursor()

      local lines = vim.api.nvim_buf_get_lines(test_bufnr, 0, -1, false)
      assert.equals('line 1', lines[1])
      assert.equals('modified line 2', lines[2])
      assert.equals('', lines[3], 'Should have empty line')
      assert.equals('modified line 4', lines[4])
      assert.equals('line 5', lines[5])
    end)

    it('should handle trailing empty lines correctly', function()
      vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, {
        'header',
        'content',
        '',
        'footer',
      })

      local old_lines = { 'content', '' }
      local variants = {
        {
          new_lines = {
            'new content',
            '', -- Preserve trailing empty
            '', -- Add another empty
          },
          reasoning = 'Extra spacing',
        },
      }

      overlay.show_multiline_suggestion_variants(test_bufnr, 2, 3, old_lines, variants)

      vim.api.nvim_set_current_buf(test_bufnr)
      vim.api.nvim_win_set_cursor(0, { 2, 0 })
      overlay.apply_at_cursor()

      local lines = vim.api.nvim_buf_get_lines(test_bufnr, 0, -1, false)
      assert.equals('header', lines[1])
      assert.equals('new content', lines[2])
      assert.equals('', lines[3], 'Should have first empty line')
      assert.equals('', lines[4], 'Should have second empty line')
      assert.equals('footer', lines[5])
    end)

    it('should handle all empty lines replacement', function()
      vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, {
        'start',
        'old',
        'end',
      })

      local variants = {
        {
          new_lines = { '', '', '' }, -- Replace with all empty lines
          reasoning = 'Clear content',
        },
      }

      overlay.show_multiline_suggestion_variants(test_bufnr, 2, 2, { 'old' }, variants)

      vim.api.nvim_set_current_buf(test_bufnr)
      vim.api.nvim_win_set_cursor(0, { 2, 0 })
      overlay.apply_at_cursor()

      local lines = vim.api.nvim_buf_get_lines(test_bufnr, 0, -1, false)
      assert.equals('start', lines[1])
      assert.equals('', lines[2])
      assert.equals('', lines[3])
      assert.equals('', lines[4])
      assert.equals('end', lines[5])
    end)
  end)

  describe('special characters handling', function()
    it('should handle lines with quotes and escapes', function()
      vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, {
        'normal line',
      })

      local variants = {
        {
          new_text = 'const str = "Hello \\"World\\"";',
          reasoning = 'Escaped quotes',
        },
        {
          new_text = "const str = 'It\\'s working';",
          reasoning = 'Single quotes with apostrophe',
        },
        {
          new_text = 'const regex = /\\w+\\s*=\\s*["\'].*["\']/g;',
          reasoning = 'Complex regex',
        },
      }

      overlay.show_suggestion_variants(test_bufnr, 1, 'normal line', variants)

      -- Test cycling through variants
      local suggestions = overlay.get_suggestions(test_bufnr)
      assert.equals(3, #suggestions[1].variants)

      -- Cycle to second variant
      overlay.cycle_variant(test_bufnr, 1, 1)
      assert.equals(2, suggestions[1].current_variant)

      -- Apply second variant
      vim.api.nvim_set_current_buf(test_bufnr)
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      overlay.apply_at_cursor()

      local lines = vim.api.nvim_buf_get_lines(test_bufnr, 0, -1, false)
      assert.equals("const str = 'It\\'s working';", lines[1])
    end)

    it('should handle unicode and emoji characters', function()
      vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, {
        'plain text',
      })

      local variants = {
        {
          new_text = '// 🚀 Deployment ready! 部署就绪！',
          reasoning = 'Unicode and emoji',
        },
        {
          new_text = '// → ← ↑ ↓ ⚡ ✨ 🎯',
          reasoning = 'Various symbols',
        },
      }

      overlay.show_suggestion_variants(test_bufnr, 1, 'plain text', variants)

      vim.api.nvim_set_current_buf(test_bufnr)
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      overlay.apply_at_cursor()

      local lines = vim.api.nvim_buf_get_lines(test_bufnr, 0, -1, false)
      assert.equals('// 🚀 Deployment ready! 部署就绪！', lines[1])
    end)

    it('should handle very long lines', function()
      local long_line = string.rep('x', 500)
      vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, { long_line })

      local variants = {
        {
          new_text = string.rep('y', 600),
          reasoning = 'Even longer line',
        },
      }

      overlay.show_suggestion_variants(test_bufnr, 1, long_line, variants)

      vim.api.nvim_set_current_buf(test_bufnr)
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      overlay.apply_at_cursor()

      local lines = vim.api.nvim_buf_get_lines(test_bufnr, 0, -1, false)
      assert.equals(600, #lines[1])
      assert.equals(string.rep('y', 600), lines[1])
    end)
  end)

  describe('large multiline replacements', function()
    it('should handle replacing many lines with many lines', function()
      local content = {}
      for i = 1, 20 do
        table.insert(content, 'line ' .. i)
      end
      vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, content)

      local old_lines = {}
      for i = 5, 15 do
        table.insert(old_lines, 'line ' .. i)
      end

      local new_lines = {}
      for i = 1, 25 do
        table.insert(new_lines, 'new line ' .. i)
      end

      local variants = {
        {
          new_lines = new_lines,
          reasoning = 'Large replacement',
        },
      }

      overlay.show_multiline_suggestion_variants(test_bufnr, 5, 15, old_lines, variants)

      vim.api.nvim_set_current_buf(test_bufnr)
      vim.api.nvim_win_set_cursor(0, { 7, 0 }) -- Cursor in middle of range
      overlay.apply_at_cursor()

      local lines = vim.api.nvim_buf_get_lines(test_bufnr, 0, -1, false)
      assert.equals(34, #lines) -- 4 + 25 + 5 = 34 lines total
      assert.equals('line 4', lines[4])
      assert.equals('new line 1', lines[5])
      assert.equals('new line 25', lines[29])
      assert.equals('line 16', lines[30])
    end)

    it('should handle replacing many lines with single line', function()
      local content = {}
      for i = 1, 10 do
        table.insert(content, 'line ' .. i)
      end
      vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, content)

      local old_lines = {}
      for i = 3, 8 do
        table.insert(old_lines, 'line ' .. i)
      end

      local variants = {
        {
          new_lines = { '// collapsed' },
          reasoning = 'Collapse to single line',
        },
      }

      overlay.show_multiline_suggestion_variants(test_bufnr, 3, 8, old_lines, variants)

      vim.api.nvim_set_current_buf(test_bufnr)
      vim.api.nvim_win_set_cursor(0, { 5, 0 })
      overlay.apply_at_cursor()

      local lines = vim.api.nvim_buf_get_lines(test_bufnr, 0, -1, false)
      assert.equals(5, #lines) -- 2 + 1 + 2 = 5 lines total
      assert.equals('line 2', lines[2])
      assert.equals('// collapsed', lines[3])
      assert.equals('line 9', lines[4])
    end)
  end)

  describe('variant cycling edge cases', function()
    it('should handle cycling when cursor moves between applications', function()
      vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, {
        'line 1',
        'line 2',
      })

      local variants1 = {
        { new_text = 'variant 1a', reasoning = 'First' },
        { new_text = 'variant 1b', reasoning = 'Second' },
      }

      local variants2 = {
        { new_text = 'variant 2a', reasoning = 'First' },
        { new_text = 'variant 2b', reasoning = 'Second' },
      }

      overlay.show_suggestion_variants(test_bufnr, 1, 'line 1', variants1)
      overlay.show_suggestion_variants(test_bufnr, 2, 'line 2', variants2)

      -- Cycle first suggestion
      overlay.cycle_variant(test_bufnr, 1, 1)

      -- Cycle second suggestion
      overlay.cycle_variant(test_bufnr, 2, 1)

      local suggestions = overlay.get_suggestions(test_bufnr)
      assert.equals(2, suggestions[1].current_variant)
      assert.equals(2, suggestions[2].current_variant)

      -- Apply first
      vim.api.nvim_set_current_buf(test_bufnr)
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      overlay.apply_at_cursor()

      local lines = vim.api.nvim_buf_get_lines(test_bufnr, 0, -1, false)
      assert.equals('variant 1b', lines[1])
      assert.equals('line 2', lines[2])
    end)

    it('should handle mixed single and multiline variants', function()
      vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, {
        'header',
        'line 1',
        'line 2',
        'line 3',
        'footer',
      })

      -- Single line variant at line 1
      local single_variants = {
        { new_text = 'HEADER', reasoning = 'Uppercase' },
        { new_text = '# Header', reasoning = 'Markdown' },
      }
      overlay.show_suggestion_variants(test_bufnr, 1, 'header', single_variants)

      -- Multiline variant at lines 2-4
      local multi_variants = {
        {
          new_lines = { 'combined', '' },
          reasoning = 'Combine lines',
        },
        {
          new_lines = { '- item 1', '- item 2', '- item 3' },
          reasoning = 'List format',
        },
      }
      overlay.show_multiline_suggestion_variants(test_bufnr, 2, 4, { 'line 1', 'line 2', 'line 3' }, multi_variants)

      -- Both suggestions should coexist
      local suggestions = overlay.get_suggestions(test_bufnr)
      assert.is_not_nil(suggestions[1])
      assert.is_not_nil(suggestions[2])
      assert.is_false(suggestions[1].is_multiline or false)
      assert.is_true(suggestions[2].is_multiline)
    end)
  end)

  describe('apply/reject from any line in multiline', function()
    it('should apply from last line of multiline range', function()
      vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, {
        'start',
        'old1',
        'old2',
        'old3',
        'end',
      })

      local variants = {
        {
          new_lines = { 'new1', 'new2', 'new3' },
          reasoning = 'Replace all',
        },
      }

      overlay.show_multiline_suggestion_variants(test_bufnr, 2, 4, { 'old1', 'old2', 'old3' }, variants)

      vim.api.nvim_set_current_buf(test_bufnr)
      vim.api.nvim_win_set_cursor(0, { 4, 0 }) -- Cursor on LAST line of range
      overlay.apply_at_cursor()

      local lines = vim.api.nvim_buf_get_lines(test_bufnr, 0, -1, false)
      assert.equals('new1', lines[2])
      assert.equals('new2', lines[3])
      assert.equals('new3', lines[4])
    end)

    it('should reject from middle line of multiline range', function()
      vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, {
        'start',
        'old1',
        'old2',
        'old3',
        'end',
      })

      local variants = {
        {
          new_lines = { 'new1', 'new2', 'new3' },
          reasoning = 'Replace all',
        },
      }

      overlay.show_multiline_suggestion_variants(test_bufnr, 2, 4, { 'old1', 'old2', 'old3' }, variants)

      vim.api.nvim_set_current_buf(test_bufnr)
      vim.api.nvim_win_set_cursor(0, { 3, 0 }) -- Cursor on MIDDLE line of range
      overlay.reject_at_cursor()

      -- Check overlay was cleared
      local suggestions = overlay.get_suggestions(test_bufnr)
      assert.is_nil(suggestions[2])

      -- Check content unchanged
      local lines = vim.api.nvim_buf_get_lines(test_bufnr, 0, -1, false)
      assert.equals('old1', lines[2])
      assert.equals('old2', lines[3])
      assert.equals('old3', lines[4])
    end)
  end)

  describe('clear_overlays functionality', function()
    it('should clear all overlays and suggestions', function()
      vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, {
        'line 1',
        'line 2',
        'line 3',
      })

      -- Add multiple overlays
      overlay.show_suggestion(test_bufnr, 1, 'line 1', 'new 1')
      overlay.show_suggestion(test_bufnr, 2, 'line 2', 'new 2')
      overlay.show_suggestion(test_bufnr, 3, 'line 3', 'new 3')

      local suggestions = overlay.get_suggestions(test_bufnr)
      assert.is_not_nil(suggestions[1])
      assert.is_not_nil(suggestions[2])
      assert.is_not_nil(suggestions[3])

      -- Clear all
      overlay.clear_overlays(test_bufnr)

      suggestions = overlay.get_suggestions(test_bufnr)
      assert.equals(0, vim.tbl_count(suggestions))

      -- Check extmarks are gone
      local ns_id = vim.api.nvim_create_namespace('pairup_overlay')
      local marks = vim.api.nvim_buf_get_extmarks(test_bufnr, ns_id, 0, -1, {})
      assert.equals(0, #marks)
    end)
  end)
end)
