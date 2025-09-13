-- Integration test for marker to overlay conversion
-- Tests the complete flow: markers → overlays → accept all → verify result

local eq = function(expected, actual, msg)
  if vim.deep_equal(expected, actual) then
    return true
  end
  error(msg or string.format('Expected %s, got %s', vim.inspect(expected), vim.inspect(actual)))
end

describe('Marker to Overlay Integration', function()
  local test_dir = 'test/integration/marker_overlay/'
  local bufnr
  local overlay
  local marker_parser

  before_each(function()
    -- Clear any existing test state
    vim.cmd('silent! %bdelete!')

    -- Load modules
    overlay = require('pairup.overlay')
    marker_parser = require('pairup.marker_parser')

    -- Initialize overlay system
    overlay.setup()
    marker_parser.setup()

    -- Mock vim.cmd('write') to avoid errors in tests
    local original_cmd = vim.cmd
    vim.cmd = function(cmd)
      if cmd == 'write' then
        -- Skip write in tests
        return
      end
      return original_cmd(cmd)
    end
  end)

  after_each(function()
    -- Clean up
    if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end)

  it('should convert markers to overlays and produce expected output', function()
    -- Step 1: Load the README with markers
    local readme_with_markers = vim.fn.readfile(test_dir .. 'README_with_markers.md')
    bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, readme_with_markers)
    vim.api.nvim_set_current_buf(bufnr)

    -- Make buffer modifiable
    vim.bo[bufnr].modifiable = true

    -- Step 2: Convert markers to overlays
    local overlays_created = marker_parser.parse_and_convert(bufnr)

    -- Wait for vim.schedule to complete (overlays are created async)
    vim.wait(100)

    -- Verify overlays were created (check after async completion)
    -- Note: overlays_created just tracks the count queued, not actual creation

    -- Get all suggestions and accept them
    local suggestions = overlay.get_all_suggestions(bufnr)
    assert(#suggestions > 0, 'No suggestions found after marker conversion')

    -- Accept all overlays
    overlay.accept_all_overlays(bufnr)

    -- Step 4: Get the resulting content
    local result_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

    -- Step 5: Load expected content
    local expected_lines = vim.fn.readfile(test_dir .. 'README_expected.md')

    -- Step 6: Compare results
    eq(
      #expected_lines,
      #result_lines,
      string.format('Line count mismatch. Expected %d lines, got %d lines', #expected_lines, #result_lines)
    )

    -- Compare line by line for better error reporting
    for i = 1, #expected_lines do
      if expected_lines[i] ~= result_lines[i] then
        error(string.format('Line %d mismatch:\nExpected: %s\nActual:   %s', i, expected_lines[i], result_lines[i]))
      end
    end

    -- If we get here, the test passed!
    print('🍾 Integration test passed! Opening champagne!')
  end)

  it('should handle multi-line replacements correctly', function()
    -- Create a test buffer with multi-line content
    local content = {
      'Line 1',
      'Line 2',
      'Line 3',
      '',
      '-- CLAUDE:MARKERS:START --',
      'CLAUDE:MARKER-1,3 | Replace multiple lines',
      'New line 1',
      'New line 2',
      '-- CLAUDE:MARKERS:END --',
    }

    bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, content)
    vim.api.nvim_set_current_buf(bufnr)
    vim.bo[bufnr].modifiable = true

    -- Convert markers
    marker_parser.parse_and_convert(bufnr)
    vim.wait(100)

    -- Accept all
    overlay.accept_all_overlays(bufnr)

    -- Verify result
    local result = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local expected = { 'New line 1', 'New line 2' }

    eq(expected, result)
  end)

  it('should handle insertions correctly', function()
    -- Create a test buffer for insertion
    local content = {
      'Line 1',
      'Line 2',
      '',
      '-- CLAUDE:MARKERS:START --',
      'CLAUDE:MARKER-2,1 | Replace line 2 with insertion',
      'Line 1.5 (inserted)',
      'Line 2',
      '-- CLAUDE:MARKERS:END --',
    }

    bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, content)
    vim.api.nvim_set_current_buf(bufnr)
    vim.bo[bufnr].modifiable = true

    -- Convert markers
    marker_parser.parse_and_convert(bufnr)
    vim.wait(100)

    -- Accept all
    overlay.accept_all_overlays(bufnr)

    -- Verify result
    local result = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local expected = { 'Line 1', 'Line 1.5 (inserted)', 'Line 2' }

    eq(expected, result)
  end)

  it('should remove trailing empty lines after marker section', function()
    -- Create content with trailing empty lines before markers
    local content = {
      'Content line 1',
      'Content line 2',
      '',
      '', -- Extra empty lines that should be removed
      '',
      '-- CLAUDE:MARKERS:START --',
      'CLAUDE:MARKER-1,1 | Update first line',
      'Updated content line 1',
      '-- CLAUDE:MARKERS:END --',
    }

    bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, content)
    vim.api.nvim_set_current_buf(bufnr)
    vim.bo[bufnr].modifiable = true

    -- Convert markers
    marker_parser.parse_and_convert(bufnr)
    vim.wait(100)

    -- Accept all
    overlay.accept_all_overlays(bufnr)

    -- Verify no trailing empty lines
    local result = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local expected = { 'Updated content line 1', 'Content line 2' }

    eq(expected, result)
  end)
end)
