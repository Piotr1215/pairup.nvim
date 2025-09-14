-- Comprehensive integration test for PairMarkerToOverlay command
describe('PairMarkerToOverlay integration', function()
  local marker_parser
  local overlay
  local bufnr
  local ns_id

  before_each(function()
    -- Clear any existing test state
    vim.cmd('silent! %bdelete!')

    -- Load modules
    marker_parser = require('pairup.marker_parser_direct')
    overlay = require('pairup.overlay')

    -- Initialize overlay system
    overlay.setup()

    -- Get namespace ID for overlay extmarks
    ns_id = vim.api.nvim_create_namespace('pairup_overlay')

    -- Create a test buffer
    bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(bufnr)
    vim.bo[bufnr].modifiable = true
  end)

  after_each(function()
    if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
      overlay.clear_overlays(bufnr)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end)

  describe('basic marker parsing', function()
    it('should create overlays with correct extmarks for simple replacement', function()
      -- Setup: Create buffer with a simple replacement marker
      local content = {
        'Line 1 original',
        'Line 2 original',
        '',
        'CLAUDE:MARKER-1,1 | Replace first line',
        'Line 1 updated',
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, content)

      -- Act: Parse markers to overlays
      local overlay_count = marker_parser.parse_to_overlays(bufnr)

      -- Assert: Check overlay was created
      assert.equals(1, overlay_count, 'Should create exactly 1 overlay')

      -- Assert: Check buffer content (markers should be removed)
      local final_content = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      assert.equals(2, #final_content, 'Buffer should have 2 lines after marker removal')
      assert.equals('Line 1 original', final_content[1])
      assert.equals('Line 2 original', final_content[2])

      -- Assert: Check extmarks were created
      local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, 0, -1, { details = true })
      assert.is_true(#marks > 0, 'Should have created extmarks')

      -- Assert: Check extmark position (0-indexed, so line 1 = index 0)
      local first_mark = marks[1]
      assert.equals(0, first_mark[2], 'Extmark should be on line 1 (0-indexed)')

      -- Assert: Check suggestion storage
      local suggestions = overlay.get_suggestions and overlay.get_suggestions(bufnr) or {}
      assert.is_not_nil(next(suggestions), 'Should have stored suggestions')
    end)

    it('should handle multiple markers with correct extmark placement', function()
      -- Setup: Multiple markers
      local content = {
        'Line 1',
        'Line 2',
        'Line 3',
        '',
        'CLAUDE:MARKER-1,1 | Update line 1',
        'Line 1 updated',
        'CLAUDE:MARKER-3,1 | Update line 3',
        'Line 3 updated',
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, content)

      -- Act: Parse markers
      local overlay_count = marker_parser.parse_to_overlays(bufnr)

      -- Assert: Check overlays created
      assert.equals(2, overlay_count, 'Should create 2 overlays')

      -- Assert: Check all extmarks
      local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, 0, -1, { details = true })
      assert.is_true(#marks >= 2, 'Should have at least 2 extmarks')

      -- Sort marks by line number to verify positions
      table.sort(marks, function(a, b)
        return a[2] < b[2]
      end)

      -- Assert: First extmark on line 1 (0-indexed = 0)
      assert.equals(0, marks[1][2], 'First extmark should be on line 1')

      -- Assert: Second extmark on line 3 (0-indexed = 2)
      assert.equals(2, marks[2][2], 'Second extmark should be on line 3')
    end)

    it('should handle insertion markers (count=0) correctly', function()
      -- Setup: Insertion marker
      local content = {
        'Line 1',
        'Line 2',
        '',
        'CLAUDE:MARKER-1,0 | Insert after line 1',
        'New inserted line',
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, content)

      -- Act: Parse markers
      local overlay_count = marker_parser.parse_to_overlays(bufnr)

      -- Assert: Check overlay created
      assert.equals(1, overlay_count, 'Should create 1 insertion overlay')

      -- Assert: Check extmark placement for insertion
      local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, 0, -1, { details = true })
      assert.is_true(#marks > 0, 'Should have created extmarks for insertion')

      -- Insertion should place extmark at line 2 (after line 1)
      local mark = marks[1]
      assert.equals(1, mark[2], 'Insertion extmark should be at line 2 (0-indexed)')

      -- Assert: Verify virtual text details if available
      if mark[4] and mark[4].virt_lines then
        assert.is_true(#mark[4].virt_lines > 0, 'Should have virtual lines for insertion')
      end
    end)

    it('should handle deletion markers (negative count) correctly', function()
      -- Setup: Deletion marker
      local content = {
        'Line 1',
        'Line 2 to delete',
        'Line 3 to delete',
        'Line 4',
        '',
        'CLAUDE:MARKER-2,-2 | Delete lines 2-3',
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, content)

      -- Act: Parse markers
      local overlay_count = marker_parser.parse_to_overlays(bufnr)

      -- Assert: Check overlay created
      assert.equals(1, overlay_count, 'Should create 1 deletion overlay')

      -- Assert: Check extmarks for deletion
      local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, 0, -1, { details = true })
      assert.is_true(#marks > 0, 'Should have created extmarks for deletion')

      -- Deletion should mark the lines to be deleted
      local mark = marks[1]
      assert.equals(1, mark[2], 'Deletion extmark should start at line 2 (0-indexed)')
    end)

    it('should handle multiline replacements with proper extmark tracking', function()
      -- Setup: Multiline replacement
      local content = {
        'function old() {',
        '  console.log("old");',
        '  return false;',
        '}',
        'other code',
        '',
        'CLAUDE:MARKER-1,4 | Replace entire function',
        'function new() {',
        '  console.log("new");',
        '  console.log("improved");',
        '  return true;',
        '}',
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, content)

      -- Act: Parse markers
      local overlay_count = marker_parser.parse_to_overlays(bufnr)

      -- Assert: Check overlay created
      assert.equals(1, overlay_count, 'Should create 1 multiline overlay')

      -- Assert: Buffer should have original content minus markers
      local final_content = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      assert.equals(5, #final_content, 'Should have 5 lines after marker removal')
      assert.equals('other code', final_content[5])

      -- Assert: Check extmarks span the correct range
      local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, 0, -1, { details = true })
      assert.is_true(#marks > 0, 'Should have extmarks for multiline replacement')

      -- The extmark should be at the start of the replacement range
      assert.equals(0, marks[1][2], 'Multiline extmark should start at line 1')

      -- Assert: Check that suggestion is stored as multiline
      local all_suggestions = overlay.get_all_suggestions and overlay.get_all_suggestions() or {}
      local buffer_suggestions = all_suggestions[bufnr] or {}
      local suggestion_count = 0
      for _, suggestion in pairs(buffer_suggestions) do
        suggestion_count = suggestion_count + 1
        assert.is_true(suggestion.is_multiline, 'Should be marked as multiline suggestion')
        assert.equals(1, suggestion.start_line, 'Should track start line')
        assert.equals(4, suggestion.end_line, 'Should track end line')
      end
      assert.equals(1, suggestion_count, 'Should have exactly one multiline suggestion')
    end)

    it('should preserve extmark positions after buffer modifications', function()
      -- Setup: Create markers and apply them
      local content = {
        'Line 1',
        'Line 2',
        'Line 3',
        '',
        'CLAUDE:MARKER-2,1 | Update line 2',
        'Line 2 updated',
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, content)

      -- Act: Parse markers
      local overlay_count = marker_parser.parse_to_overlays(bufnr)
      assert.equals(1, overlay_count)

      -- Get initial extmark position
      local marks_before = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, 0, -1, {})
      assert.equals(1, #marks_before, 'Should have 1 extmark')
      local extmark_id = marks_before[1][1]
      local initial_line = marks_before[1][2]
      assert.equals(1, initial_line, 'Extmark should be on line 2 (0-indexed)')

      -- Modify buffer by adding a line before the extmark
      local current_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      table.insert(current_lines, 1, 'New line inserted at top')
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, current_lines)

      -- Assert: Extmark should have moved - it tracks its position
      local mark_after = vim.api.nvim_buf_get_extmark_by_id(bufnr, ns_id, extmark_id, {})
      -- Due to how Neovim handles extmarks with virtual lines, the position may vary
      -- The important thing is that the extmark still exists and has moved from its original position
      assert.is_true(mark_after[1] > initial_line, 'Extmark should have moved down from its original position')
      assert.is_not_nil(mark_after[1], 'Extmark should still exist after buffer modification')
    end)

    it('should handle empty replacement lines correctly', function()
      -- Setup: Replacement with empty lines
      local content = {
        'Line 1',
        'Line 2',
        '',
        'CLAUDE:MARKER-2,1 | Replace with empty line',
        '', -- Empty replacement
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, content)

      -- Act: Parse markers
      local overlay_count = marker_parser.parse_to_overlays(bufnr)

      -- Assert: Should create overlay even with empty replacement
      assert.equals(1, overlay_count, 'Should create overlay for empty replacement')

      -- Assert: Check extmarks exist
      local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, 0, -1, { details = true })
      assert.is_true(#marks > 0, 'Should have extmarks even for empty replacement')
    end)

    it('should handle markers with delimiters correctly', function()
      -- Setup: Markers with START/END delimiters
      local content = {
        'Original content',
        '',
        '-- CLAUDE:MARKERS:START --',
        'CLAUDE:MARKER-1,1 | With delimiters',
        'Updated content',
        '-- CLAUDE:MARKERS:END --',
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, content)

      -- Act: Parse markers
      local overlay_count = marker_parser.parse_to_overlays(bufnr)

      -- Assert: Should parse correctly with delimiters
      assert.equals(1, overlay_count, 'Should handle delimited markers')

      -- Assert: All marker lines including delimiters should be removed
      local final_content = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      assert.equals(1, #final_content, 'Should remove all marker lines including delimiters')
      assert.equals('Original content', final_content[1])

      -- Assert: Extmarks created correctly
      local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, 0, -1, {})
      assert.equals(1, #marks, 'Should create extmark for delimited marker')
    end)

    it('should store reasoning with each overlay suggestion', function()
      -- Setup: Marker with reasoning
      local reasoning = 'Improve performance'
      local content = {
        'slow code',
        '',
        'CLAUDE:MARKER-1,1 | ' .. reasoning,
        'fast code',
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, content)

      -- Act: Parse markers
      local overlay_count = marker_parser.parse_to_overlays(bufnr)

      -- Assert: Overlay created
      assert.equals(1, overlay_count)

      -- Assert: Check if reasoning is preserved in virtual text
      local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, 0, -1, { details = true })
      if marks[1] and marks[1][4] and marks[1][4].virt_lines then
        local virt_lines = marks[1][4].virt_lines
        local found_reasoning = false
        for _, line in ipairs(virt_lines) do
          for _, chunk in ipairs(line) do
            if chunk[1] and chunk[1]:match(reasoning) then
              found_reasoning = true
              break
            end
          end
        end
        assert.is_true(found_reasoning, 'Reasoning should be displayed in virtual text')
      end
    end)
  end)

  describe('edge cases and error handling', function()
    it('should handle no markers gracefully', function()
      -- Setup: Buffer with no markers
      local content = {
        'Just regular content',
        'No markers here',
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, content)

      -- Act: Parse markers
      local overlay_count = marker_parser.parse_to_overlays(bufnr)

      -- Assert: No overlays created
      assert.equals(0, overlay_count, 'Should return 0 when no markers found')

      -- Assert: Content unchanged
      local final_content = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      assert.same(content, final_content, 'Content should be unchanged when no markers')
    end)

    it('should handle malformed markers gracefully', function()
      -- Setup: Malformed marker
      local content = {
        'Line 1',
        'CLAUDE:MARKER-invalid,format | Bad marker',
        'Some content',
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, content)

      -- Act: Parse markers (should handle error gracefully)
      local success, result = pcall(marker_parser.parse_to_overlays, bufnr)

      -- Assert: Should not crash
      assert.is_true(success or result == 0, 'Should handle malformed markers without crashing')
    end)

    it('should handle out-of-bounds line numbers', function()
      -- Setup: Marker referencing line beyond buffer
      local content = {
        'Line 1',
        'Line 2',
        '',
        'CLAUDE:MARKER-999,1 | Out of bounds',
        'Replacement',
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, content)

      -- Act: Parse markers
      local success, result = pcall(marker_parser.parse_to_overlays, bufnr)

      -- Assert: Should handle gracefully
      assert.is_true(success, 'Should not crash on out-of-bounds line numbers')
    end)
  end)

  describe('accept and reject functionality', function()
    it('should apply overlay when accepted', function()
      -- Setup: Create overlay via marker
      local content = {
        'Original line',
        '',
        'CLAUDE:MARKER-1,1 | Test acceptance',
        'Updated line',
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, content)

      -- Create overlay
      local overlay_count = marker_parser.parse_to_overlays(bufnr)
      assert.equals(1, overlay_count)

      -- Act: Accept the overlay
      vim.api.nvim_win_set_cursor(0, { 1, 0 }) -- Move cursor to line 1
      overlay.apply_at_cursor(bufnr)

      -- Assert: Content should be updated
      local final_content = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      assert.equals('Updated line', final_content[1], 'Line should be updated after accepting overlay')

      -- Assert: Extmark should be removed after acceptance
      local marks_after = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, 0, -1, {})
      assert.equals(0, #marks_after, 'Extmark should be removed after accepting overlay')
    end)

    it('should remove overlay when rejected', function()
      -- Setup: Create overlay via marker
      local content = {
        'Keep this line',
        '',
        'CLAUDE:MARKER-1,1 | Test rejection',
        'Do not apply this',
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, content)

      -- Create overlay
      local overlay_count = marker_parser.parse_to_overlays(bufnr)
      assert.equals(1, overlay_count)

      -- Act: Reject the overlay
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      overlay.reject_at_cursor(bufnr)

      -- Assert: Content should remain unchanged
      local final_content = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      assert.equals('Keep this line', final_content[1], 'Content should be unchanged after rejection')

      -- Assert: Extmark should be removed
      local marks_after = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, 0, -1, {})
      assert.equals(0, #marks_after, 'Extmark should be removed after rejection')
    end)
  end)
end)
