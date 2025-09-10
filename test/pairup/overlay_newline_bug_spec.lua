describe('pairup overlay newline preservation bug', function()
  local overlay
  local overlay_api
  local test_bufnr

  before_each(function()
    overlay = require('pairup.overlay')
    overlay_api = require('pairup.overlay_api')
    overlay.setup()

    test_bufnr = vim.api.nvim_create_buf(false, true)

    -- Mock RPC state to use our test buffer
    local rpc = require('pairup.rpc')
    rpc.get_state = function()
      return { main_buffer = test_bufnr }
    end
  end)

  after_each(function()
    if test_bufnr and vim.api.nvim_buf_is_valid(test_bufnr) then
      overlay.clear_overlays(test_bufnr)
      vim.api.nvim_buf_delete(test_bufnr, { force = true })
    end
  end)

  describe('CRITICAL BUG: Missing newlines after sections', function()
    it('should preserve newlines between sections when accepting overlays', function()
      -- Setup: Create a README-like structure
      vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, {
        '# Title',
        '',
        'Some content here.',
        '',
        'Plus: Real-time streaming, RPC control, session persistence, and more.',
        '',
        '## Next Section',
        '',
        'Content of next section',
      })

      -- Create overlay that replaces line 5 with added section header
      -- This simulates the exact issue from the experience report
      local result = overlay_api.multiline(5, 5, {
        'Plus: Real-time streaming, RPC control, session persistence, and more.',
        '', -- THIS NEWLINE WAS GETTING LOST!
        '## How It Compares',
      }, 'Add comparison section header')

      local decoded = vim.json.decode(result)
      assert.is_true(decoded.success, 'Should create overlay successfully')

      -- Apply the overlay
      vim.api.nvim_set_current_buf(test_bufnr)
      vim.api.nvim_win_set_cursor(0, { 5, 0 })
      local applied = overlay.apply_at_cursor()
      assert.is_true(applied, 'Should apply overlay')

      -- Check the result
      local lines = vim.api.nvim_buf_get_lines(test_bufnr, 0, -1, false)

      -- The critical assertion: newline should be preserved!
      assert.equals('Plus: Real-time streaming, RPC control, session persistence, and more.', lines[5])
      assert.equals('', lines[6], 'CRITICAL: Empty line should exist here!')
      assert.equals('## How It Compares', lines[7])
      assert.equals('', lines[8], 'Original empty line should still be here')
      assert.equals('## Next Section', lines[9])
    end)

    it('should not interleave content when accepting multiple overlays', function()
      -- Setup: Create numbered list structure
      vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, {
        '## Getting Started',
        '',
        '1. Start AI with `:PairupStart`',
        '2. Make changes',
        '3. Stage completed work',
        '4. Continue working',
      })

      -- Add a Quick Start section before Getting Started
      local result1 = overlay_api.multiline(1, 1, {
        '## Quick Start (2 minutes)',
        '',
        '```bash',
        'nvim myfile.lua',
        ':PairupStart',
        'git add file.lua',
        '```',
        '',
        '## Getting Started',
      }, 'Add quick start section')

      assert.is_true(vim.json.decode(result1).success)

      -- Apply it
      vim.api.nvim_set_current_buf(test_bufnr)
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      overlay.apply_at_cursor()

      local lines = vim.api.nvim_buf_get_lines(test_bufnr, 0, -1, false)

      -- Content should NOT be interleaved
      assert.equals('## Quick Start (2 minutes)', lines[1])
      assert.equals('', lines[2])
      assert.equals('```bash', lines[3])
      assert.equals('nvim myfile.lua', lines[4])
      assert.equals(':PairupStart', lines[5])
      assert.equals('git add file.lua', lines[6])
      assert.equals('```', lines[7])
      assert.equals('', lines[8])
      assert.equals('## Getting Started', lines[9])
      assert.equals('', lines[10])
      assert.equals('1. Start AI with `:PairupStart`', lines[11])
      -- The numbered list should continue normally, not be interleaved!
    end)
  end)

  describe('Line tracking issues', function()
    it('should find overlays even after accepting others', function()
      vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, {
        'Line 1',
        'Line 2',
        'Line 3',
        'Line 4',
        'Line 5',
      })

      -- Create multiple overlays
      overlay_api.single(1, 'Modified Line 1', 'First change')
      overlay_api.single(3, 'Modified Line 3', 'Second change')
      overlay_api.single(5, 'Modified Line 5', 'Third change')

      -- Accept the first one
      vim.api.nvim_set_current_buf(test_bufnr)
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      assert.is_true(overlay.apply_at_cursor())

      -- Should still find the overlay at line 3
      vim.api.nvim_win_set_cursor(0, { 3, 0 })
      local found = overlay.apply_at_cursor()
      assert.is_true(found, 'Should find overlay at line 3 after accepting line 1')

      -- Should still find the overlay at line 5
      vim.api.nvim_win_set_cursor(0, { 5, 0 })
      found = overlay.apply_at_cursor()
      assert.is_true(found, 'Should find overlay at line 5 after accepting others')
    end)

    it('should handle EOF overlays correctly', function()
      vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, {
        'Line 1',
        'Line 2',
        'Line 3',
      })

      -- Add overlay at EOF
      local result = overlay_api.single(3, 'Line 3 with footer', 'Add footer')
      assert.is_true(vim.json.decode(result).success)

      -- Should be able to find and apply it
      vim.api.nvim_set_current_buf(test_bufnr)
      vim.api.nvim_win_set_cursor(0, { 3, 0 })
      local applied = overlay.apply_at_cursor()
      assert.is_true(applied, 'Should apply EOF overlay')

      local lines = vim.api.nvim_buf_get_lines(test_bufnr, 0, -1, false)
      assert.equals('Line 3 with footer', lines[3])
    end)
  end)
end)
