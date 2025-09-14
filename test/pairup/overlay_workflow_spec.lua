describe('overlay accept-edit-accept workflow', function()
  local overlay = require('pairup.overlay')

  before_each(function()
    -- Clear any existing overlays and state
    overlay.clear_overlays()
    vim.cmd('enew')
    -- Create a simple JavaScript file
    vim.api.nvim_buf_set_lines(0, 0, -1, false, {
      'function calculate(x, y) {',
      '  return x + y;',
      '}',
      '',
      'function display(result) {',
      '  console.log(result);',
      '}',
      '',
      'function main() {',
      '  const a = 5;',
      '  const b = 10;',
      '  const sum = calculate(a, b);',
      '  display(sum);',
      '}',
    })
  end)

  after_each(function()
    overlay.clear_overlays()
    vim.cmd('bwipeout!')
  end)

  it('should handle accept-edit-accept workflow correctly', function()
    local bufnr = vim.api.nvim_get_current_buf()

    -- Create three suggestions
    -- 1. Add TypeScript types to calculate (single line)
    overlay.show_suggestion(
      bufnr,
      1,
      'function calculate(x, y) {',
      'function calculate(x: number, y: number): number {',
      'Add TypeScript types'
    )

    -- 2. Improve display function (multiline)
    overlay.show_multiline_suggestion(
      bufnr,
      5,
      7,
      { 'function display(result) {', '  console.log(result);', '}' },
      { 'function display(result: number): void {', '  console.log(`The result is: ${result}`);', '}' },
      'Enhance display with template literal'
    )

    -- 3. Add error handling to main (multiline)
    overlay.show_multiline_suggestion(
      bufnr,
      9,
      14,
      {
        'function main() {',
        '  const a = 5;',
        '  const b = 10;',
        '  const sum = calculate(a, b);',
        '  display(sum);',
        '}',
      },
      {
        'function main() {',
        '  try {',
        '    const a = 5;',
        '    const b = 10;',
        '    const sum = calculate(a, b);',
        '    display(sum);',
        '  } catch (error) {',
        "    console.error('Error:', error);",
        '  }',
        '}',
      },
      'Add error handling'
    )

    -- Verify we have 3 overlays
    local overlays = overlay.get_all_suggestions()[bufnr] or {}
    assert.equals(3, vim.tbl_count(overlays))

    -- Step 1: Accept first overlay
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    overlay.apply_at_cursor()

    -- Verify first change was applied
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)
    assert.equals('function calculate(x: number, y: number): number {', lines[1])

    -- Verify we have 2 overlays left
    overlays = overlay.get_all_suggestions()[bufnr] or {}
    assert.equals(2, vim.tbl_count(overlays))

    -- Step 2: Manually edit where the second overlay would be
    -- Instead of accepting the suggestion, we make our own changes
    vim.api.nvim_buf_set_lines(bufnr, 4, 7, false, {
      'function display(result: number): void {',
      '  // Custom logging implementation',
      '  console.log(`[${new Date().toISOString()}] Result: ${result}`);',
      '}',
    })

    -- The overlay has moved due to our edit - find and clear it
    -- After replacing 3 lines with 4, the overlay moved down
    local cleared = false
    for line = 1, vim.api.nvim_buf_line_count(bufnr) do
      if overlay.clear_overlay_at_line(bufnr, line) then
        cleared = true
        break
      end
    end
    assert.is_true(cleared, 'Should have found and cleared the moved overlay')

    -- Verify we have 1 overlay left
    overlays = overlay.get_all_suggestions()[bufnr] or {}
    assert.equals(1, vim.tbl_count(overlays))

    -- Step 3: Accept the third overlay
    -- Note: Line numbers have shifted due to our edit
    -- Original line 9 is now at a different position
    vim.api.nvim_win_set_cursor(0, { 9, 0 })
    overlay.apply_at_cursor()

    -- Verify final state
    lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

    -- Check all three changes were applied correctly
    assert.equals('function calculate(x: number, y: number): number {', lines[1])
    assert.equals('function display(result: number): void {', lines[5])
    assert.equals('  // Custom logging implementation', lines[6])
    assert.equals('  console.log(`[${new Date().toISOString()}] Result: ${result}`);', lines[7])
    assert.equals('function main() {', lines[10])
    assert.equals('  try {', lines[11])
    assert.equals('    const a = 5;', lines[12])
    assert.equals('    const b = 10;', lines[13])
    assert.equals('    const sum = calculate(a, b);', lines[14])
    assert.equals('    display(sum);', lines[15])
    assert.equals('  } catch (error) {', lines[16])
    assert.equals("    console.error('Error:', error);", lines[17])
    assert.equals('  }', lines[18])
    assert.equals('}', lines[19])

    -- Verify no overlays remain
    overlays = overlay.get_all_suggestions()[bufnr] or {}
    assert.equals(0, vim.tbl_count(overlays))
  end)

  it('should track line numbers correctly when overlays change buffer', function()
    local bufnr = vim.api.nvim_get_current_buf()

    -- Create overlays at different positions
    overlay.show_suggestion(bufnr, 2, '  return x + y;', '  return x + y; // addition', 'Add comment')
    overlay.show_suggestion(bufnr, 6, '  console.log(result);', "  console.log('Result:', result);", 'Better logging')
    overlay.show_suggestion(bufnr, 11, '  const b = 10;', '  const b = 10; // second number', 'Add comment')

    -- Accept first overlay (line 2)
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    overlay.apply_at_cursor()

    -- The overlays at lines 6 and 11 should still be valid
    local overlays = overlay.get_all_suggestions()[bufnr] or {}
    assert.equals(2, vim.tbl_count(overlays))

    -- Add two new lines manually after line 3
    vim.api.nvim_win_set_cursor(0, { 3, 0 })
    vim.cmd('normal! o  // Additional calculation logic')
    vim.cmd('normal! o  // More processing here')

    -- Now the overlay that was at line 6 should be at line 8
    -- And the overlay that was at line 11 should be at line 13

    -- Accept the overlay that's now at line 8 (was line 6)
    vim.api.nvim_win_set_cursor(0, { 8, 0 })
    overlay.apply_at_cursor()

    local lines = vim.api.nvim_buf_get_lines(bufnr, 7, 8, false)
    assert.equals("  console.log('Result:', result);", lines[1])

    -- Accept the last overlay (now at line 13, was line 11)
    vim.api.nvim_win_set_cursor(0, { 13, 0 })
    overlay.apply_at_cursor()

    lines = vim.api.nvim_buf_get_lines(bufnr, 12, 13, false)
    assert.equals('  const b = 10; // second number', lines[1])

    -- Verify no overlays remain
    overlays = overlay.get_all_suggestions()[bufnr] or {}
    assert.equals(0, vim.tbl_count(overlays))
  end)

  it('should handle accept-edit(add 3 lines)-accept workflow', function()
    local bufnr = vim.api.nvim_get_current_buf()

    -- Create three overlays
    overlay.show_suggestion(bufnr, 2, '  return x + y;', '  return x + y; // Calculate sum', 'Add comment to return')

    overlay.show_suggestion(
      bufnr,
      6,
      '  console.log(result);',
      '  console.log(`Displaying: ${result}`);',
      'Use template literal'
    )

    overlay.show_suggestion(
      bufnr,
      12,
      '  const sum = calculate(a, b);',
      '  const sum = calculate(a, b); // Perform calculation',
      'Add explanatory comment'
    )

    -- Verify we have 3 overlays
    local overlays = overlay.get_all_suggestions()[bufnr] or {}
    assert.equals(3, vim.tbl_count(overlays))

    -- Step 1: Accept first overlay at line 2
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    overlay.apply_at_cursor()

    -- Verify first suggestion was applied
    local lines = vim.api.nvim_buf_get_lines(bufnr, 1, 2, false)
    assert.equals('  return x + y; // Calculate sum', lines[1])

    -- Step 2: Manually edit the area where second overlay is
    -- Add 3 new lines instead of accepting the suggestion
    vim.api.nvim_buf_set_lines(bufnr, 5, 6, false, {
      '  // Log with timestamp',
      '  const timestamp = new Date().toISOString();',
      '  console.log(`[${timestamp}] Result: ${result}`);',
      '  console.log(`Type: ${typeof result}`);',
    })

    -- Find and clear the moved overlay
    local cleared = false
    for line = 1, vim.api.nvim_buf_line_count(bufnr) do
      if overlay.clear_overlay_at_line(bufnr, line) then
        cleared = true
        break
      end
    end
    assert.is_true(cleared, 'Should have found and cleared the moved overlay')

    -- Verify we have 1 overlay left
    overlays = overlay.get_all_suggestions()[bufnr] or {}
    assert.equals(1, vim.tbl_count(overlays))

    -- Step 3: Accept third overlay
    -- Note: It was at line 12, but after our edits (added 3 lines), it should be at line 15
    vim.api.nvim_win_set_cursor(0, { 15, 0 })
    overlay.apply_at_cursor()

    -- Verify final state
    lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

    -- Check first overlay was accepted
    assert.equals('  return x + y; // Calculate sum', lines[2])

    -- Check manual edit (3 new lines added)
    assert.equals('  // Log with timestamp', lines[6])
    assert.equals('  const timestamp = new Date().toISOString();', lines[7])
    assert.equals('  console.log(`[${timestamp}] Result: ${result}`);', lines[8])
    assert.equals('  console.log(`Type: ${typeof result}`);', lines[9])

    -- Check third overlay was accepted
    assert.equals('  const sum = calculate(a, b); // Perform calculation', lines[15])

    -- Verify no overlays remain
    overlays = overlay.get_all_suggestions()[bufnr] or {}
    assert.equals(0, vim.tbl_count(overlays))
  end)

  it('should handle rejection of overlays during workflow', function()
    local bufnr = vim.api.nvim_get_current_buf()

    -- Create three overlays - replace lines with comment + original line
    overlay.show_multiline_suggestion(
      bufnr,
      1,
      1,
      { 'function calculate(x, y) {' },
      { '// TypeScript version', 'function calculate(x, y) {' },
      'Add comment'
    )
    overlay.show_multiline_suggestion(
      bufnr,
      5,
      5,
      { 'function display(result) {' },
      { '// Display function', 'function display(result) {' },
      'Add comment'
    )
    overlay.show_multiline_suggestion(
      bufnr,
      9,
      9,
      { 'function main() {' },
      { '// Main entry point', 'function main() {' },
      'Add comment'
    )

    -- Accept first
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    overlay.apply_at_cursor()

    -- Reject second (now at line 6 after first insertion added a line)
    vim.api.nvim_win_set_cursor(0, { 6, 0 })
    overlay.reject_at_cursor()

    -- Accept third (now at line 10 due to first insertion)
    vim.api.nvim_win_set_cursor(0, { 10, 0 })
    overlay.apply_at_cursor()

    -- Verify final state
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    assert.equals('// TypeScript version', lines[1])
    assert.equals('function calculate(x, y) {', lines[2])
    assert.equals('function display(result) {', lines[6]) -- Not modified (shifted by 1 due to first insertion)
    assert.equals('// Main entry point', lines[10])
    assert.equals('function main() {', lines[11])

    -- Verify no overlays remain
    local overlays = overlay.get_all_suggestions()[bufnr] or {}
    assert.equals(0, vim.tbl_count(overlays))
  end)
end)
