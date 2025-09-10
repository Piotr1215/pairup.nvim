describe('pairup overlay variants', function()
  local overlay
  local test_bufnr

  before_each(function()
    overlay = require('pairup.overlay')
    overlay.setup()

    test_bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, {
      'function calculate(x, y) {',
      '  const result = x + y;',
      '  console.log(result);',
      '  return result;',
      '}',
    })
  end)

  after_each(function()
    if test_bufnr and vim.api.nvim_buf_is_valid(test_bufnr) then
      overlay.clear_overlays(test_bufnr)
      vim.api.nvim_buf_delete(test_bufnr, { force = true })
    end
  end)

  describe('multi-variant suggestions', function()
    it('should store multiple variants for a single line', function()
      local variants = {
        {
          new_text = '  const sum = x + y;',
          reasoning = 'More descriptive variable name',
        },
        {
          new_text = '  const total = x + y;',
          reasoning = 'Alternative descriptive name',
        },
        {
          new_text = '  const addition = x + y;',
          reasoning = 'Explicit operation name',
        },
      }

      overlay.show_suggestion_variants(test_bufnr, 2, '  const result = x + y;', variants)

      local suggestions = overlay.get_suggestions(test_bufnr)
      assert.is_not_nil(suggestions[2], 'Should have stored suggestion')
      assert.is_not_nil(suggestions[2].variants, 'Should have variants array')
      assert.equals(3, #suggestions[2].variants, 'Should have 3 variants')
      assert.equals(1, suggestions[2].current_variant, 'Should default to first variant')
    end)

    it('should display current variant indicator', function()
      local variants = {
        { new_text = 'option1', reasoning = 'First option' },
        { new_text = 'option2', reasoning = 'Second option' },
      }

      overlay.show_suggestion_variants(test_bufnr, 2, '  const result = x + y;', variants)

      local ns_id = vim.api.nvim_create_namespace('pairup_overlay')
      local marks = vim.api.nvim_buf_get_extmarks(test_bufnr, ns_id, 0, -1, { details = true })

      assert.is_true(#marks > 0, 'Should have created extmarks')
      -- The display should include variant indicator like [1/2]
    end)

    it('should cycle through variants', function()
      local variants = {
        { new_text = 'variant1', reasoning = 'First' },
        { new_text = 'variant2', reasoning = 'Second' },
        { new_text = 'variant3', reasoning = 'Third' },
      }

      overlay.show_suggestion_variants(test_bufnr, 2, 'original', variants)

      local suggestions = overlay.get_suggestions(test_bufnr)
      assert.equals(1, suggestions[2].current_variant)

      overlay.cycle_variant(test_bufnr, 2)
      assert.equals(2, suggestions[2].current_variant, 'Should move to second variant')

      overlay.cycle_variant(test_bufnr, 2)
      assert.equals(3, suggestions[2].current_variant, 'Should move to third variant')

      overlay.cycle_variant(test_bufnr, 2)
      assert.equals(1, suggestions[2].current_variant, 'Should cycle back to first')
    end)

    it('should cycle backwards through variants', function()
      local variants = {
        { new_text = 'variant1', reasoning = 'First' },
        { new_text = 'variant2', reasoning = 'Second' },
        { new_text = 'variant3', reasoning = 'Third' },
      }

      overlay.show_suggestion_variants(test_bufnr, 2, 'original', variants)

      overlay.cycle_variant(test_bufnr, 2, -1) -- cycle backwards
      local suggestions = overlay.get_suggestions(test_bufnr)
      assert.equals(3, suggestions[2].current_variant, 'Should move to last variant')

      overlay.cycle_variant(test_bufnr, 2, -1)
      assert.equals(2, suggestions[2].current_variant, 'Should move to second variant')
    end)

    it('should apply the currently selected variant', function()
      local variants = {
        { new_text = '  const sum = x + y;', reasoning = 'First' },
        { new_text = '  const total = x + y;', reasoning = 'Second' },
      }

      overlay.show_suggestion_variants(test_bufnr, 2, '  const result = x + y;', variants)

      -- Cycle to second variant
      overlay.cycle_variant(test_bufnr, 2)

      -- Apply at cursor
      vim.api.nvim_set_current_buf(test_bufnr)
      vim.api.nvim_win_set_cursor(0, { 2, 0 })
      overlay.apply_at_cursor()

      local lines = vim.api.nvim_buf_get_lines(test_bufnr, 1, 2, false)
      assert.equals('  const total = x + y;', lines[1], 'Should apply second variant')
    end)

    it('should handle single variant gracefully', function()
      local variants = {
        { new_text = 'only option', reasoning = 'Single choice' },
      }

      overlay.show_suggestion_variants(test_bufnr, 2, 'original', variants)

      local suggestions = overlay.get_suggestions(test_bufnr)
      assert.equals(1, #suggestions[2].variants)

      -- Cycling should do nothing
      overlay.cycle_variant(test_bufnr, 2)
      assert.equals(1, suggestions[2].current_variant, 'Should stay at 1')
    end)

    it('should update display when cycling variants', function()
      local variants = {
        { new_text = 'first', reasoning = 'Reason 1' },
        { new_text = 'second', reasoning = 'Reason 2' },
      }

      overlay.show_suggestion_variants(test_bufnr, 2, 'original', variants)

      -- Spy on display update function
      local update_called = false
      local original_update = overlay.update_variant_display
      overlay.update_variant_display = function(...)
        update_called = true
        if original_update then
          return original_update(...)
        end
      end

      overlay.cycle_variant(test_bufnr, 2)
      assert.is_true(update_called, 'Should update display when cycling')

      -- Restore original function
      overlay.update_variant_display = original_update
    end)
  end)

  describe('multiline variants', function()
    it('should support variants for multiline suggestions', function()
      local old_lines = {
        '  const result = x + y;',
        '  console.log(result);',
      }

      local variants = {
        {
          new_lines = {
            '  const sum = x + y;',
            '  console.log("Sum:", sum);',
          },
          reasoning = 'Better logging',
        },
        {
          new_lines = {
            '  const total = x + y;',
            '  console.debug(total);',
          },
          reasoning = 'Debug mode',
        },
      }

      overlay.show_multiline_suggestion_variants(test_bufnr, 2, 3, old_lines, variants)

      local suggestions = overlay.get_suggestions(test_bufnr)
      assert.is_not_nil(suggestions[2], 'Should have stored multiline suggestion')
      assert.is_not_nil(suggestions[2].variants, 'Should have variants')
      assert.equals(2, #suggestions[2].variants, 'Should have 2 variants')
      assert.is_true(suggestions[2].is_multiline, 'Should be marked as multiline')
    end)

    it('should apply selected multiline variant', function()
      local old_lines = {
        '  const result = x + y;',
        '  console.log(result);',
      }

      local variants = {
        {
          new_lines = {
            '  const sum = x + y;',
            '  console.log("Sum:", sum);',
          },
          reasoning = 'First variant',
        },
        {
          new_lines = {
            '  const total = x + y;',
            '  console.debug("Total:", total);',
          },
          reasoning = 'Second variant',
        },
      }

      overlay.show_multiline_suggestion_variants(test_bufnr, 2, 3, old_lines, variants)

      -- Select second variant
      overlay.cycle_variant(test_bufnr, 2)

      -- Apply
      vim.api.nvim_set_current_buf(test_bufnr)
      vim.api.nvim_win_set_cursor(0, { 2, 0 })
      overlay.apply_at_cursor()

      local lines = vim.api.nvim_buf_get_lines(test_bufnr, 1, 3, false)
      assert.equals('  const total = x + y;', lines[1])
      assert.equals('  console.debug("Total:", total);', lines[2])
    end)
  end)

  describe('backwards compatibility', function()
    it('should still work with old single-suggestion API', function()
      -- Old API should create a single variant internally
      overlay.show_suggestion(test_bufnr, 2, 'old text', 'new text', 'reasoning')

      local suggestions = overlay.get_suggestions(test_bufnr)
      assert.is_not_nil(suggestions[2])

      -- Should be converted to variant structure internally
      if suggestions[2].variants then
        assert.equals(1, #suggestions[2].variants, 'Should have one variant')
        assert.equals('new text', suggestions[2].variants[1].new_text)
      else
        -- Or maintain backward compatibility
        assert.equals('new text', suggestions[2].new_text)
      end
    end)
  end)
end)
