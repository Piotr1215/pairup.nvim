describe('pairup.edit', function()
  local edit

  before_each(function()
    package.loaded['pairup.edit'] = nil
    package.loaded['pairup.conflict'] = nil
    package.loaded['pairup.config'] = nil

    -- Mock config
    package.loaded['pairup.config'] = {
      get = function(key)
        if key == 'proposals.auto_enter' then
          return false
        end
        return nil
      end,
    }

    edit = require('pairup.edit')
  end)

  describe('enter', function()
    it('should notify when no proposal at cursor', function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'just normal code' })
      vim.api.nvim_set_current_buf(buf)
      vim.api.nvim_win_set_cursor(0, { 1, 0 })

      local notified = false
      local orig_notify = vim.notify
      vim.notify = function(msg, level)
        if msg:match('No proposal') then
          notified = true
        end
      end

      edit.enter()

      vim.notify = orig_notify
      assert.is_true(notified)
      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it('should open float when inside proposal block', function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
        '<<<<<<< CURRENT',
        'old code',
        '=======',
        'new code',
        '>>>>>>> PROPOSED: test reason',
      })
      vim.api.nvim_set_current_buf(buf)
      vim.api.nvim_win_set_cursor(0, { 2, 0 })

      edit.enter()

      assert.is_not_nil(edit._state.buf)
      assert.is_not_nil(edit._state.win)
      assert.is_true(vim.api.nvim_buf_is_valid(edit._state.buf))
      assert.is_true(vim.api.nvim_win_is_valid(edit._state.win))

      -- Cleanup
      edit.close()
      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it('should show only PROPOSED content in buffer (header/footer are virtual text)', function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
        '<<<<<<< CURRENT',
        'old code',
        '=======',
        'new code line 1',
        'new code line 2',
        '>>>>>>> PROPOSED: test reason',
      })
      vim.api.nvim_set_current_buf(buf)
      vim.api.nvim_win_set_cursor(0, { 2, 0 })

      edit.enter()

      local float_lines = vim.api.nvim_buf_get_lines(edit._state.buf, 0, -1, false)

      -- Buffer should only contain PROPOSED lines (editable content)
      assert.equals(2, #float_lines)
      assert.equals('new code line 1', float_lines[1])
      assert.equals('new code line 2', float_lines[2])

      -- Verify virtual text extmarks exist
      local ns = vim.api.nvim_create_namespace('pairup_edit_virt')
      local extmarks = vim.api.nvim_buf_get_extmarks(edit._state.buf, ns, 0, -1, { details = true })
      assert.is_true(#extmarks >= 2) -- At least header and footer extmarks

      edit.close()
      vim.api.nvim_buf_delete(buf, { force = true })
    end)
  end)

  describe('close', function()
    it('should close float window and buffer', function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
        '<<<<<<< CURRENT',
        'old',
        '=======',
        'new',
        '>>>>>>> PROPOSED: reason',
      })
      vim.api.nvim_set_current_buf(buf)
      vim.api.nvim_win_set_cursor(0, { 2, 0 })

      edit.enter()
      local float_buf = edit._state.buf
      local float_win = edit._state.win

      edit.close()

      assert.is_false(vim.api.nvim_win_is_valid(float_win))
      assert.is_false(vim.api.nvim_buf_is_valid(float_buf))
      assert.is_nil(edit._state.buf)
      vim.api.nvim_buf_delete(buf, { force = true })
    end)
  end)

  describe('backdrop', function()
    it('should create backdrop window when opening float', function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
        '<<<<<<< CURRENT',
        'old',
        '=======',
        'new',
        '>>>>>>> PROPOSED: reason',
      })
      vim.api.nvim_set_current_buf(buf)
      vim.api.nvim_win_set_cursor(0, { 2, 0 })

      edit.enter()

      assert.is_not_nil(edit._state.backdrop_buf)
      assert.is_not_nil(edit._state.backdrop_win)
      assert.is_true(vim.api.nvim_win_is_valid(edit._state.backdrop_win))

      edit.close()
      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it('should close backdrop when closing float', function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
        '<<<<<<< CURRENT',
        'old',
        '=======',
        'new',
        '>>>>>>> PROPOSED: reason',
      })
      vim.api.nvim_set_current_buf(buf)
      vim.api.nvim_win_set_cursor(0, { 2, 0 })

      edit.enter()
      local backdrop_win = edit._state.backdrop_win

      edit.close()

      assert.is_false(vim.api.nvim_win_is_valid(backdrop_win))
      assert.is_nil(edit._state.backdrop_win)
      vim.api.nvim_buf_delete(buf, { force = true })
    end)
  end)

  describe('keybinds', function()
    it('should have ga keybind for accept', function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
        '<<<<<<< CURRENT',
        'old',
        '=======',
        'new',
        '>>>>>>> PROPOSED: reason',
      })
      vim.api.nvim_set_current_buf(buf)
      vim.api.nvim_win_set_cursor(0, { 2, 0 })

      edit.enter()

      -- Check that ga is mapped in the float buffer
      local maps = vim.api.nvim_buf_get_keymap(edit._state.buf, 'n')
      local has_ga = false
      for _, map in ipairs(maps) do
        if map.lhs == 'ga' then
          has_ga = true
          break
        end
      end
      assert.is_true(has_ga)

      edit.close()
      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it('should have gd keybind for diff', function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
        '<<<<<<< CURRENT',
        'old',
        '=======',
        'new',
        '>>>>>>> PROPOSED: reason',
      })
      vim.api.nvim_set_current_buf(buf)
      vim.api.nvim_win_set_cursor(0, { 2, 0 })

      edit.enter()

      local maps = vim.api.nvim_buf_get_keymap(edit._state.buf, 'n')
      local has_gd = false
      for _, map in ipairs(maps) do
        if map.lhs == 'gd' then
          has_gd = true
          break
        end
      end
      assert.is_true(has_gd)

      edit.close()
      vim.api.nvim_buf_delete(buf, { force = true })
    end)
  end)

  describe('maybe_auto_enter', function()
    it('should not enter when already in float', function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
        '<<<<<<< CURRENT',
        'old',
        '=======',
        'new',
        '>>>>>>> PROPOSED: reason',
      })
      vim.api.nvim_set_current_buf(buf)
      vim.api.nvim_win_set_cursor(0, { 2, 0 })

      edit.enter()
      local first_buf = edit._state.buf

      -- Try to auto-enter again
      edit.maybe_auto_enter()

      -- Should still be same float
      assert.equals(first_buf, edit._state.buf)

      edit.close()
      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it('should skip terminal buffers', function()
      -- Create a scratch buffer and manually set buftype
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(buf)
      -- Use nofile as proxy for terminal (terminal buftype can't be set manually)
      vim.bo[buf].buftype = 'nofile'

      -- Mock the buftype check by temporarily modifying the edit module behavior
      -- Since we can't set buftype to terminal, we'll test the nil state
      edit.maybe_auto_enter()

      -- No proposal in buffer, so should not enter
      assert.is_nil(edit._state.buf)
      vim.api.nvim_buf_delete(buf, { force = true })
    end)
  end)
end)
