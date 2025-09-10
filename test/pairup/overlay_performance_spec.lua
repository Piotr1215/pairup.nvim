describe('overlay performance tests', function()
  local rpc
  local overlay
  local batch
  local test_bufnr

  before_each(function()
    rpc = require('pairup.rpc')
    overlay = require('pairup.overlay')
    batch = require('pairup.overlay_batch')

    rpc.setup()
    overlay.setup()

    test_bufnr = vim.api.nvim_create_buf(false, true)
    local lines = {}
    for i = 1, 1000 do
      table.insert(lines, 'Line ' .. i .. ' with some content')
    end
    vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, lines)

    rpc.get_state().main_buffer = test_bufnr
  end)

  after_each(function()
    if test_bufnr and vim.api.nvim_buf_is_valid(test_bufnr) then
      vim.api.nvim_buf_delete(test_bufnr, { force = true })
    end
    batch.clear_batch()
    -- Don't call clear_overlays without a buffer
  end)

  describe('large buffer operations', function()
    it('should handle 100 overlays efficiently', function()
      local start_time = vim.loop.hrtime()

      for i = 1, 100 do
        rpc.simple_overlay(i, 'Modified line ' .. i, 'Performance test ' .. i)
      end

      local elapsed = (vim.loop.hrtime() - start_time) / 1e6
      assert.is_true(elapsed < 1000, 'Should complete within 1 second')

      local suggestions = overlay.get_suggestions(test_bufnr)
      assert.equals(100, vim.tbl_count(suggestions))
    end)

    it('should handle large batch operations', function()
      batch.clear_batch()
      local start_time = vim.loop.hrtime()

      for i = 1, 200 do
        batch.add_single(i, 'Line ' .. i .. ' with some content', 'New line ' .. i, 'Batch test')
      end

      local result = batch.apply_batch()
      local elapsed = (vim.loop.hrtime() - start_time) / 1e6

      assert.equals(200, result.applied)
      assert.is_true(elapsed < 2000, 'Should complete within 2 seconds')
    end)

    it('should handle large multiline overlays', function()
      local old_lines = {}
      local new_lines = {}

      for i = 1, 50 do
        table.insert(old_lines, 'Line ' .. i .. ' with some content')
        table.insert(new_lines, 'Modified line ' .. i .. ' with new content')
      end

      local start_time = vim.loop.hrtime()
      batch.clear_batch()
      batch.add_multiline(1, 50, old_lines, new_lines, 'Large multiline test')
      local result = batch.apply_batch()
      local elapsed = (vim.loop.hrtime() - start_time) / 1e6

      assert.equals(1, result.applied)
      assert.is_true(elapsed < 500, 'Should complete within 500ms')
    end)

    it('should efficiently clear many overlays', function()
      for i = 1, 500 do
        if i % 2 == 0 then
          rpc.simple_overlay(i, 'Modified ' .. i, 'Many overlays')
        end
      end

      local suggestions = overlay.get_suggestions(test_bufnr)
      assert.is_true(vim.tbl_count(suggestions) >= 250)

      local start_time = vim.loop.hrtime()
      overlay.clear_overlays(test_bufnr)
      local elapsed = (vim.loop.hrtime() - start_time) / 1e6

      assert.is_true(elapsed < 100, 'Should clear within 100ms')
      suggestions = overlay.get_suggestions(test_bufnr)
      assert.equals(0, vim.tbl_count(suggestions))
    end)

    it('should handle rapid navigation', function()
      for i = 10, 990, 10 do
        rpc.simple_overlay(i, 'Navigation test ' .. i, 'Nav test')
      end

      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      local start_time = vim.loop.hrtime()

      for _ = 1, 50 do
        overlay.next_overlay()
      end

      local elapsed = (vim.loop.hrtime() - start_time) / 1e6
      assert.is_true(elapsed < 500, 'Navigation should be fast')
    end)
  end)

  describe('memory efficiency', function()
    it('should handle JSON parsing of large payloads', function()
      local overlays = {}
      for i = 1, 500 do
        table.insert(overlays, {
          type = 'single',
          line = i,
          old_text = 'Line ' .. i .. ' with some content',
          new_text = 'Very long new content with lots of text that makes this overlay quite large indeed ' .. i,
          reasoning = 'Long reasoning text that explains why this change is being made in great detail ' .. i,
        })
      end

      local json = vim.json.encode({
        batch = true,
        overlays = overlays,
      })

      local start_time = vim.loop.hrtime()
      local result = rpc.overlay_json_safe(json)
      local elapsed = (vim.loop.hrtime() - start_time) / 1e6

      local response = vim.json.decode(result)
      assert.is_true(response.success)
      assert.equals(500, response.count)
      assert.is_true(elapsed < 3000, 'Should parse large JSON within 3 seconds')
    end)

    it('should handle base64 encoding of large data', function()
      local overlays = {}
      for i = 1, 100 do
        table.insert(overlays, {
          type = 'multiline',
          start_line = i * 5,
          end_line = i * 5 + 4,
          old_lines = {
            'Line A ' .. i,
            'Line B ' .. i,
            'Line C ' .. i,
            'Line D ' .. i,
            'Line E ' .. i,
          },
          new_lines = {
            'New A ' .. i,
            'New B ' .. i,
            'New C ' .. i,
            'New D ' .. i,
            'New E ' .. i,
            'New F ' .. i,
            'New G ' .. i,
          },
          reasoning = 'Multiline change ' .. i,
        })
      end

      local json = vim.json.encode({ overlays = overlays })
      local b64 = vim.base64.encode(json)

      local start_time = vim.loop.hrtime()
      local result = rpc.batch_b64(b64)
      local elapsed = (vim.loop.hrtime() - start_time) / 1e6

      local response = vim.json.decode(result)
      assert.is_true(response.success)
      assert.is_true(elapsed < 2000, 'Should handle base64 within 2 seconds')
    end)
  end)

  describe('stress tests', function()
    it('should handle mixed operations under load', function()
      local operations = {}

      local function random_operation()
        local op = math.random(1, 5)
        if op == 1 then
          local line = math.random(1, 1000)
          rpc.simple_overlay(line, 'Stress test ' .. line, 'Random op')
        elseif op == 2 then
          overlay.next_overlay()
        elseif op == 3 then
          overlay.prev_overlay()
        elseif op == 4 then
          local line = math.random(1, 1000)
          overlay.apply_at_line(test_bufnr, line)
        else
          local line = math.random(1, 1000)
          overlay.reject_at_line(test_bufnr, line)
        end
      end

      local start_time = vim.loop.hrtime()

      for _ = 1, 1000 do
        random_operation()
      end

      local elapsed = (vim.loop.hrtime() - start_time) / 1e6
      assert.is_true(elapsed < 5000, 'Should handle 1000 operations within 5 seconds')
    end)

    it('should handle rapid batch create/apply cycles', function()
      local start_time = vim.loop.hrtime()

      for cycle = 1, 20 do
        batch.clear_batch()

        for i = 1, 50 do
          local line = (cycle - 1) * 50 + i
          if line <= 1000 then
            batch.add_single(
              line,
              'Line ' .. line .. ' with some content',
              'Cycle ' .. cycle .. ' line ' .. i,
              'Rapid test'
            )
          end
        end

        batch.apply_batch()
      end

      local elapsed = (vim.loop.hrtime() - start_time) / 1e6
      assert.is_true(elapsed < 10000, 'Should complete 20 cycles within 10 seconds')
    end)
  end)
end)
