-- Tests for multi-variant overlay functionality
local helpers = require('test.helpers')

describe('overlay variants', function()
  local overlay
  local bufnr

  before_each(function()
    -- Load the plugin
    require('pairup').setup({})
    overlay = require('pairup.overlay')

    -- Create a test buffer
    bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(bufnr)

    -- Add some test content
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      'function test() {',
      '  console.log("hello");',
      '  return true;',
      '}',
      '',
      'const data = getData();',
      'processData(data);',
    })
  end)

  after_each(function()
    -- Clean up
    overlay.clear_overlays()
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end)

  describe('single line variants', function()
    it('should create single line variant overlay', function()
      local variants = {
        { new_text = 'const result = await getData();', reasoning = 'Use async/await' },
        { new_text = 'const result = getData().then(process);', reasoning = 'Use promise chain' },
        { new_text = 'const result = fetchData();', reasoning = 'Use simpler name' },
      }

      overlay.show_suggestion_variants(bufnr, 6, nil, variants)

      local suggestions = overlay.get_suggestions(bufnr)
      assert.is_not_nil(suggestions[6])
      assert.is_not_nil(suggestions[6].variants)
      assert.equals(3, #suggestions[6].variants)
      assert.equals(1, suggestions[6].current_variant)
    end)

    it('should cycle through variants with Tab', function()
      local variants = {
        { new_text = 'Option 1', reasoning = 'First' },
        { new_text = 'Option 2', reasoning = 'Second' },
        { new_text = 'Option 3', reasoning = 'Third' },
      }

      overlay.show_suggestion_variants(bufnr, 2, nil, variants)

      local suggestions = overlay.get_suggestions(bufnr)
      assert.equals(1, suggestions[2].current_variant)

      -- Cycle forward
      overlay.cycle_variant(bufnr, 2, 1)
      assert.equals(2, suggestions[2].current_variant)

      overlay.cycle_variant(bufnr, 2, 1)
      assert.equals(3, suggestions[2].current_variant)

      -- Should wrap around
      overlay.cycle_variant(bufnr, 2, 1)
      assert.equals(1, suggestions[2].current_variant)
    end)

    it('should cycle backwards with Shift+Tab', function()
      local variants = {
        { new_text = 'Option 1', reasoning = 'First' },
        { new_text = 'Option 2', reasoning = 'Second' },
        { new_text = 'Option 3', reasoning = 'Third' },
      }

      overlay.show_suggestion_variants(bufnr, 2, nil, variants)

      local suggestions = overlay.get_suggestions(bufnr)
      assert.equals(1, suggestions[2].current_variant)

      -- Cycle backward (should wrap to end)
      overlay.cycle_variant(bufnr, 2, -1)
      assert.equals(3, suggestions[2].current_variant)

      overlay.cycle_variant(bufnr, 2, -1)
      assert.equals(2, suggestions[2].current_variant)

      overlay.cycle_variant(bufnr, 2, -1)
      assert.equals(1, suggestions[2].current_variant)
    end)

    it('should apply the current variant when accepted', function()
      local variants = {
        { new_text = 'const result = await getData();', reasoning = 'Use async/await' },
        { new_text = 'const result = getData().then(process);', reasoning = 'Use promise chain' },
      }

      overlay.show_suggestion_variants(bufnr, 6, nil, variants)

      -- Cycle to second variant
      overlay.cycle_variant(bufnr, 6, 1)

      -- Accept the overlay
      overlay.apply_at_line(bufnr, 6)

      -- Check that the second variant was applied
      local lines = vim.api.nvim_buf_get_lines(bufnr, 5, 6, false)
      assert.equals('const result = getData().then(process);', lines[1])
    end)
  end)

  describe('multiline variants', function()
    it('should create multiline variant overlay', function()
      local variants = {
        {
          new_lines = {
            'async function test() {',
            '  console.log("hello");',
            '  return await Promise.resolve(true);',
            '}',
          },
          reasoning = 'Convert to async function',
        },
        {
          new_lines = {
            'const test = () => {',
            '  console.log("hello");',
            '  return true;',
            '};',
          },
          reasoning = 'Convert to arrow function',
        },
      }

      overlay.show_multiline_suggestion_variants(bufnr, 1, 4, nil, variants)

      local suggestions = overlay.get_suggestions(bufnr)
      assert.is_not_nil(suggestions[1])
      assert.is_not_nil(suggestions[1].variants)
      assert.equals(2, #suggestions[1].variants)
      assert.equals(1, suggestions[1].current_variant)
      assert.is_true(suggestions[1].is_multiline)
    end)

    it('should apply multiline variant correctly', function()
      local variants = {
        {
          new_lines = {
            'const test = async () => {',
            '  await log("hello");',
            '  return true;',
            '};',
          },
          reasoning = 'Async arrow function',
        },
      }

      overlay.show_multiline_suggestion_variants(bufnr, 1, 4, nil, variants)
      overlay.apply_at_line(bufnr, 1)

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, 4, false)
      assert.equals('const test = async () => {', lines[1])
      assert.equals('  await log("hello");', lines[2])
      assert.equals('  return true;', lines[3])
      assert.equals('};', lines[4])
    end)

    it('should handle deletion variants', function()
      local variants = {
        { new_lines = {}, reasoning = 'Remove entire function' },
        { new_lines = { '// Function removed' }, reasoning = 'Replace with comment' },
      }

      overlay.show_multiline_suggestion_variants(bufnr, 1, 4, nil, variants)

      -- Apply first variant (deletion)
      overlay.apply_at_line(bufnr, 1)

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      -- Should have removed lines 1-4
      assert.equals('', lines[1])
      assert.equals('const data = getData();', lines[2])
    end)
  end)

  describe('variant persistence', function()
    it('should save and restore variants', function()
      local persist = require('pairup.overlay_persistence')

      -- Set buffer name first (required for persistence)
      vim.api.nvim_buf_set_name(bufnr, '/tmp/test_file.txt')

      -- Create variant overlay
      local variants = {
        { new_text = 'Option 1', reasoning = 'First' },
        { new_text = 'Option 2', reasoning = 'Second' },
      }

      overlay.show_suggestion_variants(bufnr, 2, nil, variants)

      -- Cycle to second variant
      overlay.cycle_variant(bufnr, 2, 1)

      -- Save overlays
      local ok, path = persist.save_overlays('/tmp/test_variants.json')
      assert.is_true(ok)

      -- Clear overlays
      overlay.clear_overlays()

      -- Restore overlays
      vim.api.nvim_buf_set_name(bufnr, '/tmp/test_file.txt')
      local restore_ok = persist.restore_overlays('/tmp/test_variants.json', { force = true })
      assert.is_true(restore_ok)

      -- Check that variants were restored
      local suggestions = overlay.get_suggestions(bufnr)
      assert.is_not_nil(suggestions[2])
      assert.is_not_nil(suggestions[2].variants)
      assert.equals(2, #suggestions[2].variants)
      -- Note: current_variant might reset to 1 on restore

      -- Clean up
      os.remove('/tmp/test_variants.json')
    end)
  end)

  describe('edge cases', function()
    it('should handle single variant gracefully', function()
      local variants = {
        { new_text = 'Only option', reasoning = 'Single choice' },
      }

      overlay.show_suggestion_variants(bufnr, 2, nil, variants)

      local suggestions = overlay.get_suggestions(bufnr)
      assert.equals(1, suggestions[2].current_variant)

      -- Cycling should do nothing with single variant
      overlay.cycle_variant(bufnr, 2, 1)
      assert.equals(1, suggestions[2].current_variant)

      overlay.cycle_variant(bufnr, 2, -1)
      assert.equals(1, suggestions[2].current_variant)
    end)

    it('should handle empty variants array', function()
      local variants = {}

      -- Should not create overlay with empty variants
      overlay.show_suggestion_variants(bufnr, 2, nil, variants)

      local suggestions = overlay.get_suggestions(bufnr)
      assert.is_nil(suggestions[2])
    end)

    it('should handle nil new_lines in multiline variant', function()
      local variants = {
        { reasoning = 'Missing new_lines' },
      }

      -- Should handle gracefully without crashing
      local ok = pcall(overlay.show_multiline_suggestion_variants, bufnr, 1, 4, nil, variants)
      assert.is_true(ok)
    end)

    it('should reject invalid variant at correct line', function()
      local variants = {
        { new_text = 'Option 1', reasoning = 'First' },
        { new_text = 'Option 2', reasoning = 'Second' },
      }

      overlay.show_suggestion_variants(bufnr, 2, nil, variants)

      -- Reject should remove the overlay
      overlay.reject_at_line(bufnr, 2)

      local suggestions = overlay.get_suggestions(bufnr)
      assert.is_nil(suggestions[2])
    end)
  end)
end)
