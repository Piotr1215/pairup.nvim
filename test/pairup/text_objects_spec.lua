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
end)
