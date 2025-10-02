describe('pairup overlay', function()
  local overlay
  local test_bufnr

  before_each(function()
    -- Load the overlay module
    overlay = require('pairup.overlay')
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

  describe('extmark creation and detection', function()
    it('should create extmarks when showing suggestions', function()
      -- Show a suggestion
      overlay.show_suggestion(test_bufnr, 2, '  console.log("hello");', '  console.log("world");')

      -- Get the namespace ID
      local ns_id = vim.api.nvim_create_namespace('pairup_overlay')

      -- Get extmarks with details
      local marks = vim.api.nvim_buf_get_extmarks(test_bufnr, ns_id, 0, -1, { details = true })

      -- Should have at least one extmark
      assert.is_true(#marks > 0, 'Should have created extmarks')

      -- Check the extmark details
      local mark = marks[1]
      assert.equals(1, mark[2], 'Extmark should be on line 2 (0-indexed)')
    end)

    it('should store suggestions for later application', function()
      -- Show multiple suggestions
      overlay.show_suggestion(test_bufnr, 1, 'function test() {', 'function testUpdated() {')
      overlay.show_suggestion(test_bufnr, 2, '  console.log("hello");', '  console.log("world");')

      -- Move to line 2 and apply
      vim.api.nvim_set_current_buf(test_bufnr)
      vim.api.nvim_win_set_cursor(0, { 2, 0 })

      local result = overlay.apply_at_cursor()
      assert.is_true(result, 'Should successfully apply suggestion')

      -- Check that the line was changed
      local lines = vim.api.nvim_buf_get_lines(test_bufnr, 1, 2, false)
      assert.equals('  console.log("world");', lines[1])
    end)

    it('should find nearest overlay for navigation', function()
      -- Create multiple overlays
      overlay.show_suggestion(test_bufnr, 1, 'function test() {', 'function testNew() {')
      overlay.show_suggestion(test_bufnr, 3, '  return true;', '  return false;')

      -- Set cursor to line 2
      vim.api.nvim_set_current_buf(test_bufnr)
      vim.api.nvim_win_set_cursor(0, { 2, 0 })

      -- Navigate to next overlay
      overlay.next_overlay()

      -- Should be on line 3 now
      local cursor = vim.api.nvim_win_get_cursor(0)
      assert.equals(3, cursor[1])
    end)
  end)

  describe('multiline suggestions', function()
    it('should handle multiline suggestions correctly', function()
      local old_lines = {
        '  console.log("hello");',
        '  return true;',
      }
      local new_lines = {
        '  console.log("world");',
        '  console.log("updated");',
        '  return false;',
      }

      overlay.show_multiline_suggestion(test_bufnr, 2, 3, old_lines, new_lines)

      -- Check extmarks were created
      local ns_id = vim.api.nvim_create_namespace('pairup_overlay')
      local marks = vim.api.nvim_buf_get_extmarks(test_bufnr, ns_id, 0, -1, { details = true })
      assert.is_true(#marks > 0, 'Should have created extmarks for multiline')

      -- Apply the multiline suggestion
      vim.api.nvim_set_current_buf(test_bufnr)
      vim.api.nvim_win_set_cursor(0, { 2, 0 })

      local result = overlay.apply_at_cursor()
      assert.is_true(result, 'Should successfully apply multiline suggestion')

      -- Check buffer content
      local lines = vim.api.nvim_buf_get_lines(test_bufnr, 0, -1, false)
      assert.equals('function test() {', lines[1])
      assert.equals('  console.log("world");', lines[2])
      assert.equals('  console.log("updated");', lines[3])
      assert.equals('  return false;', lines[4])
      assert.equals('}', lines[5])
    end)
  end)

  describe('overlay visibility and toggle', function()
    pending('should toggle overlays on and off (v3.0: toggle simplified)', function()
      -- Create an overlay
      overlay.show_suggestion(test_bufnr, 2, '  console.log("hello");', '  console.log("world");')

      local ns_id = vim.api.nvim_create_namespace('pairup_overlay')

      -- Check overlay exists
      local marks = vim.api.nvim_buf_get_extmarks(test_bufnr, ns_id, 0, -1, {})
      assert.is_true(#marks > 0, 'Should have overlay')

      -- Toggle off
      vim.api.nvim_set_current_buf(test_bufnr)
      overlay.toggle()

      -- Check overlay is hidden
      marks = vim.api.nvim_buf_get_extmarks(test_bufnr, ns_id, 0, -1, {})
      assert.equals(0, #marks, 'Should have no visible overlays')

      -- Toggle on
      overlay.toggle()

      -- Check overlay is restored
      marks = vim.api.nvim_buf_get_extmarks(test_bufnr, ns_id, 0, -1, {})
      assert.is_true(#marks > 0, 'Should have restored overlay')
    end)
  end)

  describe('diff parsing', function()
    pending('should parse and show diff overlays (v3.0: diff parsing not yet implemented)', function()
      local diff = [[
@@ -1,2 +1,2 @@
-function test() {
+function testNew() {
   console.log("hello");
@@ -3,1 +3,1 @@
-  return true;
+  return false;
]]

      overlay.show_diff_overlay(test_bufnr, diff)

      -- Check that overlays were created
      local ns_id = vim.api.nvim_create_namespace('pairup_overlay')
      local marks = vim.api.nvim_buf_get_extmarks(test_bufnr, ns_id, 0, -1, {})
      assert.is_true(#marks > 0, 'Should have created overlays from diff')
    end)
  end)

  describe('accept/reject operations', function()
    it('should accept overlay at cursor position', function()
      -- Create overlay
      overlay.show_suggestion(test_bufnr, 2, '  console.log("hello");', '  console.log("accepted");')

      -- Accept it
      vim.api.nvim_set_current_buf(test_bufnr)
      vim.api.nvim_win_set_cursor(0, { 2, 0 })
      local result = overlay.apply_at_cursor()

      assert.is_true(result, 'Should successfully accept')

      -- Check line was changed
      local lines = vim.api.nvim_buf_get_lines(test_bufnr, 1, 2, false)
      assert.equals('  console.log("accepted");', lines[1])

      -- Check overlay was cleared
      local ns_id = vim.api.nvim_create_namespace('pairup_overlay')
      local marks = vim.api.nvim_buf_get_extmarks(test_bufnr, ns_id, 0, -1, {})
      assert.equals(0, #marks, 'Should have cleared overlay after accepting')
    end)

    it('should reject overlay at cursor position', function()
      -- Create overlay
      overlay.show_suggestion(test_bufnr, 2, '  console.log("hello");', '  console.log("rejected");')

      -- Reject it
      vim.api.nvim_set_current_buf(test_bufnr)
      vim.api.nvim_win_set_cursor(0, { 2, 0 })
      local result = overlay.reject_at_cursor()

      assert.is_true(result, 'Should successfully reject')

      -- Check line was NOT changed
      local lines = vim.api.nvim_buf_get_lines(test_bufnr, 1, 2, false)
      assert.equals('  console.log("hello");', lines[1])

      -- Check overlay was cleared
      local ns_id = vim.api.nvim_create_namespace('pairup_overlay')
      local marks = vim.api.nvim_buf_get_extmarks(test_bufnr, ns_id, 0, -1, {})
      assert.equals(0, #marks, 'Should have cleared overlay after rejecting')
    end)
  end)

  describe('accept_next_overlay function', function()
    it('should find and accept nearest overlay', function()
      -- Create multiple overlays
      overlay.show_suggestion(test_bufnr, 1, 'function test() {', 'function nearest() {')
      overlay.show_suggestion(test_bufnr, 3, '  return true;', '  return false;')

      -- Set cursor to line 2
      vim.api.nvim_set_current_buf(test_bufnr)
      vim.api.nvim_win_set_cursor(0, { 2, 0 })

      -- Accept nearest (should be line 1 or 3)
      local result = overlay.accept_next_overlay()
      assert.is_true(result, 'Should find and accept nearest overlay')

      -- Check that one of the suggestions was applied
      local lines = vim.api.nvim_buf_get_lines(test_bufnr, 0, -1, false)
      local applied = (lines[1] == 'function nearest() {') or (lines[3] == '  return false;')
      assert.is_true(applied, 'Should have applied one of the suggestions')
    end)

    it('should return false when no overlays exist', function()
      vim.api.nvim_set_current_buf(test_bufnr)
      local result = overlay.accept_next_overlay()
      assert.is_false(result, 'Should return false when no overlays')
    end)
  end)

  describe('follow mode', function()
    pending('should toggle follow mode (v3.0: follow mode removed)', function()
      local initial = overlay.is_follow_mode()
      local toggled = overlay.toggle_follow_mode()
      assert.are_not.equal(initial, toggled, 'Should toggle state')

      -- Toggle back
      local toggled_back = overlay.toggle_follow_mode()
      assert.equals(initial, toggled_back, 'Should toggle back to initial state')
    end)
  end)

  describe('reasoning support', function()
    it('should store and display reasoning with suggestions', function()
      -- Create overlay with reasoning
      overlay.show_suggestion(
        test_bufnr,
        2,
        '  console.log("hello");',
        '  console.debug("hello");',
        'Use debug for development logs'
      )

      -- Get stored suggestions
      local suggestions = overlay.get_suggestions(test_bufnr)
      assert.is_not_nil(suggestions[2], 'Should have stored suggestion')
      assert.equals('Use debug for development logs', suggestions[2].reasoning, 'Should store reasoning')

      -- Check that extmark was created (reasoning is displayed)
      local ns_id = vim.api.nvim_create_namespace('pairup_overlay')
      local marks = vim.api.nvim_buf_get_extmarks(test_bufnr, ns_id, 0, -1, { details = true })
      assert.is_true(#marks > 0, 'Should have created extmarks with reasoning')
    end)

    it('should handle suggestions without reasoning', function()
      -- Create overlay without reasoning (backward compatibility)
      overlay.show_suggestion(test_bufnr, 2, '  console.log("hello");', '  console.debug("hello");')

      -- Should work without reasoning
      local suggestions = overlay.get_suggestions(test_bufnr)
      assert.is_not_nil(suggestions[2], 'Should have stored suggestion')
      assert.is_nil(suggestions[2].reasoning, 'Reasoning should be nil when not provided')
    end)

    it('should support reasoning in multiline suggestions', function()
      local old_lines = {
        '  console.log("hello");',
        '  return true;',
      }
      local new_lines = {
        '  console.debug("hello");',
        '  return false;',
      }

      overlay.show_multiline_suggestion(test_bufnr, 2, 3, old_lines, new_lines, 'Debug mode and fail-safe return')

      -- Check stored suggestion has reasoning
      local suggestions = overlay.get_suggestions(test_bufnr)
      assert.is_not_nil(suggestions[2], 'Should have stored multiline suggestion')
      assert.equals('Debug mode and fail-safe return', suggestions[2].reasoning, 'Should store multiline reasoning')
    end)
  end)
end)
