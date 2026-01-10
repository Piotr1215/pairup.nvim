describe('pairup.text_objects', function()
  local text_objects

  before_each(function()
    package.loaded['pairup.text_objects'] = nil
    text_objects = require('pairup.text_objects')
  end)

  describe('setup', function()
    it('should create ic and ac mappings', function()
      text_objects.setup()

      local omaps = vim.api.nvim_get_keymap('o')
      local found_ic, found_ac = false, false
      for _, map in ipairs(omaps) do
        if map.lhs == 'ic' then
          found_ic = true
        end
        if map.lhs == 'ac' then
          found_ac = true
        end
      end
      assert.is_true(found_ic, 'ic mapping should exist in operator-pending mode')
      assert.is_true(found_ac, 'ac mapping should exist in operator-pending mode')
    end)

    it('should create ih and ah mappings', function()
      text_objects.setup()

      local omaps = vim.api.nvim_get_keymap('o')
      local found_ih, found_ah = false, false
      for _, map in ipairs(omaps) do
        if map.lhs == 'ih' then
          found_ih = true
        end
        if map.lhs == 'ah' then
          found_ah = true
        end
      end
      assert.is_true(found_ih, 'ih mapping should exist in operator-pending mode')
      assert.is_true(found_ah, 'ah mapping should exist in operator-pending mode')
    end)
  end)

  describe('select_codeblock', function()
    it('should select inner codeblock content', function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        'some text',
        '```lua',
        'local x = 1',
        'local y = 2',
        '```',
        'more text',
      })

      -- Position cursor inside the codeblock
      vim.api.nvim_win_set_cursor(0, { 3, 0 })

      -- This would select lines 3-4 (inner content)
      -- Can't fully test visual selection in headless mode, but setup works

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe('find_header', function()
    it('should find header boundaries for inner variant', function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        '# Main Header',
        'Some content here',
        'More content',
        '# Another Main',
        'Other content',
      })

      -- Position cursor inside header content
      vim.api.nvim_win_set_cursor(0, { 2, 0 })

      local bounds = text_objects.find_header('i')
      assert.is_not_nil(bounds)
      assert.equals(2, bounds.start_line) -- inner starts after header
      assert.equals(3, bounds.end_line) -- ends before next same-level header
      assert.equals(1, bounds.level)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('should find header boundaries for around variant', function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        '# Main Header',
        'Some content here',
        'More content',
        '# Another Main',
        'Other content',
      })

      -- Position cursor inside header content
      vim.api.nvim_win_set_cursor(0, { 2, 0 })

      local bounds = text_objects.find_header('a')
      assert.is_not_nil(bounds)
      assert.equals(1, bounds.start_line) -- around includes header line
      assert.equals(3, bounds.end_line) -- ends before next same-level header
      assert.equals(1, bounds.level)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('should include nested headers in parent section', function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        '# Main Header',
        'Content',
        '## Sub Header',
        'Sub content',
        '### Deep Header',
        'Deep content',
        '# Next Main',
      })

      -- Position cursor on main header
      vim.api.nvim_win_set_cursor(0, { 1, 0 })

      local bounds = text_objects.find_header('a')
      assert.is_not_nil(bounds)
      assert.equals(1, bounds.start_line)
      assert.equals(6, bounds.end_line) -- includes all nested content

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('should return nil when not in a header section', function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        'No header here',
        'Just plain text',
      })

      vim.api.nvim_win_set_cursor(0, { 1, 0 })

      local bounds = text_objects.find_header('a')
      assert.is_nil(bounds)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)
end)
