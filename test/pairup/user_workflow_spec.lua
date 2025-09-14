-- Comprehensive user workflow integration tests
describe('User Workflow Integration', function()
  local marker_parser
  local overlay
  local bufnr
  local ns_id
  local fixtures_dir = 'test/fixtures/user_workflow/'

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
  end)

  after_each(function()
    if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
      overlay.clear_overlays(bufnr)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end)

  describe('Simple workflow: accept all suggestions', function()
    it('should transform initial file to desired state by accepting all overlays', function()
      -- Step 1: Load file with markers
      local content_with_markers = vim.fn.readfile(fixtures_dir .. 'simple_with_markers.md')
      bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, content_with_markers)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].modifiable = true

      -- Step 2: Convert markers to overlays
      local overlay_count = marker_parser.parse_to_overlays(bufnr)
      assert.equals(5, overlay_count, 'Should create 5 overlays from markers')

      -- Verify markers are removed
      local lines_after_parsing = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      assert.equals(16, #lines_after_parsing, 'Should have 16 lines after removing markers (same as initial)')

      -- Step 3: Mark all overlays as accepted using staging workflow
      local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, 0, -1, {})
      for _, mark in ipairs(marks) do
        local line = mark[2] + 1 -- Convert to 1-indexed
        vim.api.nvim_win_set_cursor(0, { line, 0 })
        overlay.accept_staged()
      end

      -- Step 4: Process all staged overlays at once
      overlay.process_overlays(bufnr)

      -- Step 4: Compare with desired state
      local final_content = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local desired_content = vim.fn.readfile(fixtures_dir .. 'simple_desired.md')

      assert.equals(
        #desired_content,
        #final_content,
        string.format('Line count mismatch. Expected %d, got %d', #desired_content, #final_content)
      )

      for i = 1, #desired_content do
        assert.equals(
          desired_content[i],
          final_content[i],
          string.format('Line %d mismatch.\nExpected: %s\nActual:   %s', i, desired_content[i], final_content[i])
        )
      end
    end)
  end)

  describe('Mixed workflow: accept, reject, and edit', function()
    it('should handle mixed overlay operations', function()
      -- Create test content with multiple overlays
      local content = {
        '# Title',
        'Description here.',
        '## Section',
        'Content.',
        '',
        'CLAUDE:MARKER-1,1 | Improve title',
        '# Better Title',
        'CLAUDE:MARKER-2,1 | Enhance description',
        'Much better description with details.',
        'CLAUDE:MARKER-3,1 | Update section',
        '## Updated Section',
        'CLAUDE:MARKER-4,0 | Add new line after content',
        'Additional content line.',
      }

      bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, content)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].modifiable = true

      -- Convert markers to overlays
      local overlay_count = marker_parser.parse_to_overlays(bufnr)
      assert.equals(4, overlay_count, 'Should create 4 overlays')

      -- Get all overlays
      local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, 0, -1, {})
      table.sort(marks, function(a, b)
        return a[2] < b[2]
      end)

      -- Mark overlays with different states
      -- Operation 1: Accept first overlay (title change)
      vim.api.nvim_win_set_cursor(0, { marks[1][2] + 1, 0 })
      overlay.accept_staged()

      -- Operation 2: Reject second overlay (description change)
      vim.api.nvim_win_set_cursor(0, { marks[2][2] + 1, 0 })
      overlay.reject_staged()

      -- Operation 3: Accept third overlay (section change)
      vim.api.nvim_win_set_cursor(0, { marks[3][2] + 1, 0 })
      overlay.accept_staged()

      -- Operation 4: Accept last overlay if it exists
      if #marks > 3 then
        vim.api.nvim_win_set_cursor(0, { marks[4][2] + 1, 0 })
        overlay.accept_staged()
      end

      -- Process all staged overlays at once
      overlay.process_overlays(bufnr)

      -- Verify final state
      local final_content = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

      -- Expected: Title changed, description unchanged, section updated, new line added
      assert.equals('# Better Title', final_content[1], 'Title should be updated')
      assert.equals('Description here.', final_content[2], 'Description should remain unchanged')
      assert.equals('## Updated Section', final_content[3], 'Section should be updated')
      assert.equals('Additional content line.', final_content[5], 'New line should be added')
    end)
  end)

  describe('Complex workflow: multiline replacements', function()
    it('should handle multiline overlay operations correctly', function()
      -- Create content with multiline markers
      local content = {
        'function old() {',
        '  console.log("old");',
        '  return false;',
        '}',
        '',
        'other code here',
        '',
        'CLAUDE:MARKER-1,4 | Replace entire function',
        'function new() {',
        '  console.log("new");',
        '  console.log("improved");',
        '  return true;',
        '}',
      }

      bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, content)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].modifiable = true

      -- Convert markers to overlays
      local overlay_count = marker_parser.parse_to_overlays(bufnr)
      assert.equals(1, overlay_count, 'Should create 1 multiline overlay')

      -- Accept the multiline overlay using staging
      local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, 0, -1, {})
      assert.equals(1, #marks, 'Should have 1 extmark')

      vim.api.nvim_win_set_cursor(0, { marks[1][2] + 1, 0 })
      overlay.accept_staged()
      overlay.process_overlays(bufnr)

      -- Verify the replacement
      local final_content = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      assert.equals('function new() {', final_content[1])
      assert.equals('  console.log("new");', final_content[2])
      assert.equals('  console.log("improved");', final_content[3])
      assert.equals('  return true;', final_content[4])
      assert.equals('}', final_content[5])
      assert.equals('other code here', final_content[7])
    end)
  end)

  describe('Insertion workflow', function()
    it('should handle insertions at various positions', function()
      local content = {
        'Line 1',
        'Line 2',
        'Line 3',
        '',
        'CLAUDE:MARKER-1,0 | Insert after line 1',
        'Inserted after line 1',
        'CLAUDE:MARKER-3,0 | Insert after line 3',
        'Inserted after line 3',
      }

      bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, content)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].modifiable = true

      -- Convert markers to overlays
      local overlay_count = marker_parser.parse_to_overlays(bufnr)
      assert.equals(2, overlay_count, 'Should create 2 insertion overlays')

      -- Mark all insertions as accepted
      local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, 0, -1, {})

      for _, mark in ipairs(marks) do
        vim.api.nvim_win_set_cursor(0, { mark[2] + 1, 0 })
        overlay.accept_staged()
      end

      -- Process all at once (handles bottom-to-top automatically)
      overlay.process_overlays(bufnr)

      -- Verify insertions
      local final_content = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      assert.equals('Line 1', final_content[1])
      assert.equals('Inserted after line 1', final_content[2])
      assert.equals('Line 2', final_content[3])
      assert.equals('Line 3', final_content[4])
      assert.equals('Inserted after line 3', final_content[5])
    end)
  end)

  describe('Deletion workflow', function()
    it('should handle deletion overlays', function()
      local content = {
        'Keep this',
        'Delete line 1',
        'Delete line 2',
        'Keep this too',
        '',
        'CLAUDE:MARKER-2,-2 | Remove unnecessary lines',
      }

      bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, content)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].modifiable = true

      -- Convert markers to overlays
      local overlay_count = marker_parser.parse_to_overlays(bufnr)
      assert.equals(1, overlay_count, 'Should create 1 deletion overlay')

      -- Accept the deletion using staging
      local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, 0, -1, {})
      vim.api.nvim_win_set_cursor(0, { marks[1][2] + 1, 0 })
      overlay.accept_staged()
      overlay.process_overlays(bufnr)

      -- Verify deletion
      local final_content = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      assert.equals(2, #final_content, 'Should have 2 lines after deletion')
      assert.equals('Keep this', final_content[1])
      assert.equals('Keep this too', final_content[2])
    end)
  end)

  describe('Real-world workflow: complete document transformation', function()
    it('should handle a realistic editing session', function()
      -- Simulate a real editing session with multiple types of changes
      local content = {
        '# README',
        '',
        'Basic project.',
        '',
        '## Install',
        'npm i',
        '',
        '## Use',
        'Run it.',
        '',
        'CLAUDE:MARKER-1,1 | Professional title',
        '# Project Documentation',
        'CLAUDE:MARKER-3,1 | Detailed description',
        'This is a comprehensive project that provides powerful functionality for developers.',
        'CLAUDE:MARKER-5,2 | Proper installation section',
        '## Installation',
        '',
        '```bash',
        'npm install project-name',
        '```',
        'CLAUDE:MARKER-8,2 | Enhanced usage section',
        '## Usage',
        '',
        'Import and use the library:',
        '```javascript',
        'const lib = require("project-name");',
        'lib.run();',
        '```',
        'CLAUDE:MARKER-10,0 | Add license section',
        '',
        '## License',
        '',
        'MIT License',
      }

      bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, content)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].modifiable = true

      -- Parse markers
      local overlay_count = marker_parser.parse_to_overlays(bufnr)
      assert.equals(5, overlay_count, 'Should create 5 overlays for document transformation')

      -- Simulate user review process
      local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, 0, -1, {})

      -- Sort marks by line number (top to bottom)
      table.sort(marks, function(a, b)
        return a[2] < b[2]
      end)

      -- User decides to:
      -- 1. Accept title change
      -- 2. Accept description change
      -- 3. Accept installation section
      -- 4. Reject usage section (keeps simple version)
      -- 5. Accept license section

      local decisions = { true, true, true, false, true }

      -- Mark overlays based on decisions
      for i = 1, #marks do
        vim.api.nvim_win_set_cursor(0, { marks[i][2] + 1, 0 })
        if decisions[i] then
          overlay.accept_staged()
        else
          overlay.reject_staged()
        end
      end

      -- Process all at once
      overlay.process_overlays(bufnr)

      -- Verify the final document
      local final = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

      -- Check accepted changes
      assert.equals('# Project Documentation', final[1], 'Title should be updated')
      assert.equals(
        'This is a comprehensive project that provides powerful functionality for developers.',
        final[3],
        'Description should be updated'
      )

      -- Find installation section
      local install_idx = 0
      for i, line in ipairs(final) do
        if line == '## Installation' then
          install_idx = i
          break
        end
      end
      assert.is_true(install_idx > 0, 'Installation section should exist')
      assert.equals('```bash', final[install_idx + 2], 'Should have bash code block')

      -- Check that usage section remains simple (rejected change)
      local usage_idx = 0
      for i, line in ipairs(final) do
        if line == '## Use' then
          usage_idx = i
          break
        end
      end
      assert.is_true(usage_idx > 0, 'Original usage section should remain')
      assert.equals('Run it.', final[usage_idx + 1], 'Usage content should be unchanged')

      -- Check license section was added
      local license_idx = 0
      for i, line in ipairs(final) do
        if line == '## License' then
          license_idx = i
          break
        end
      end
      assert.is_true(license_idx > 0, 'License section should be added')
      assert.equals('MIT License', final[license_idx + 2], 'License content should be present')
    end)
  end)
end)
