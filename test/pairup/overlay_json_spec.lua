describe('overlay JSON handling', function()
  local rpc
  local overlay
  local test_bufnr

  before_each(function()
    rpc = require('pairup.rpc')
    overlay = require('pairup.overlay')

    rpc.setup()
    overlay.setup()

    test_bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, {
      'function example() {',
      '  console.log("hello");',
      '  return true;',
      '}',
      '',
      'const data = {',
      '  key: "value"',
      '};',
    })

    rpc.get_state().main_buffer = test_bufnr
  end)

  after_each(function()
    if test_bufnr and vim.api.nvim_buf_is_valid(test_bufnr) then
      vim.api.nvim_buf_delete(test_bufnr, { force = true })
    end
  end)

  describe('overlay_json_safe', function()
    it('should handle simple single-line overlay', function()
      local json = vim.json.encode({
        line = 2,
        old_text = '  console.log("hello");',
        new_text = '  console.log("Hello, World!");',
        reasoning = 'More descriptive message',
      })

      local result = rpc.overlay_json_safe(json)
      local response = vim.json.decode(result)

      assert.is_true(response.success)
      assert.equals(1, response.count)

      local suggestions = overlay.get_suggestions(test_bufnr)
      assert.equals('  console.log("Hello, World!");', suggestions[2].new_text)
    end)

    it('should handle multiline overlay', function()
      local json = vim.json.encode({
        type = 'multiline',
        start_line = 1,
        end_line = 4,
        old_lines = {
          'function example() {',
          '  console.log("hello");',
          '  return true;',
          '}',
        },
        new_lines = {
          'function example() {',
          '  try {',
          '    console.log("hello");',
          '    return true;',
          '  } catch (error) {',
          '    console.error(error);',
          '    return false;',
          '  }',
          '}',
        },
        reasoning = 'Added error handling',
      })

      local result = rpc.overlay_json_safe(json)
      local response = vim.json.decode(result)

      assert.is_true(response.success)
      assert.equals(1, response.count)
    end)

    it('should handle complex nested JSON in suggestions', function()
      local json = vim.json.encode({
        line = 7,
        old_text = '  key: "value"',
        new_text = '  key: "value",\n  nested: {\n    "deep": {\n      "data": ["a", "b", "c"]\n    }\n  }',
        reasoning = 'Added nested structure',
      })

      local result = rpc.overlay_json_safe(json)
      local response = vim.json.decode(result)

      assert.is_true(response.success)
    end)

    it('should handle JSON with all special characters', function()
      local json = vim.json.encode({
        line = 2,
        old_text = '  console.log("hello");',
        new_text = '  console.log("Test: \\"\\n\\t\\r\\\\\\b\\f\\/");',
        reasoning = 'Testing all JSON escape sequences',
      })

      local result = rpc.overlay_json_safe(json)
      local response = vim.json.decode(result)

      assert.is_true(response.success)
    end)

    it('should handle batch operations via JSON', function()
      local json = vim.json.encode({
        batch = true,
        overlays = {
          {
            type = 'single',
            line = 1,
            old_text = 'function example() {',
            new_text = 'async function example() {',
            reasoning = 'Made async',
          },
          {
            type = 'single',
            line = 2,
            old_text = '  console.log("hello");',
            new_text = '  await console.log("hello");',
            reasoning = 'Added await',
          },
          {
            type = 'single',
            line = 3,
            old_text = '  return true;',
            new_text = '  return Promise.resolve(true);',
            reasoning = 'Return promise',
          },
        },
      })

      local result = rpc.overlay_json_safe(json)
      local response = vim.json.decode(result)

      assert.is_true(response.success)
      assert.equals(3, response.count)
    end)

    it('should handle deletion overlays', function()
      local json = vim.json.encode({
        type = 'deletion',
        start_line = 5,
        end_line = 8,
        reasoning = 'Remove unnecessary code',
      })

      local result = rpc.overlay_json_safe(json)
      local response = vim.json.decode(result)

      assert.is_true(response.success)
    end)

    it('should reject invalid JSON gracefully', function()
      local invalid_json = '{"line": 1, "new_text": "test", invalid json here}'

      local result = rpc.overlay_json_safe(invalid_json)
      local response = vim.json.decode(result)

      assert.is_false(response.success or false)
      assert.is_not_nil(response.error)
      assert.match('Invalid JSON', response.error)
    end)

    it('should handle empty JSON object', function()
      local json = vim.json.encode({})

      local result = rpc.overlay_json_safe(json)
      local response = vim.json.decode(result)

      assert.is_false(response.success or false)
      assert.match('missing required', response.error)
    end)

    it('should handle very large JSON payloads', function()
      local large_array = {}
      for i = 1, 100 do
        table.insert(large_array, {
          type = 'single',
          line = 1,
          old_text = 'function example() {',
          new_text = 'function example' .. i .. '() {',
          reasoning = 'Test ' .. i,
        })
      end

      local json = vim.json.encode({
        batch = true,
        overlays = large_array,
      })

      local result = rpc.overlay_json_safe(json)
      local response = vim.json.decode(result)

      assert.is_true(response.success)
      assert.equals(100, response.count)
    end)
  end)

  describe('JSON edge cases', function()
    it('should handle Unicode control characters', function()
      local json = vim.json.encode({
        line = 1,
        old_text = 'function example() {',
        new_text = 'function 例え() { // control chars',
        reasoning = 'Unicode control chars',
      })

      local result = rpc.overlay_json_safe(json)
      local response = vim.json.decode(result)

      assert.is_true(response.success)
    end)

    it('should handle surrogate pairs', function()
      local json = vim.json.encode({
        line = 1,
        old_text = 'function example() {',
        new_text = 'function 𝓮𝔁𝓪𝓶𝓹𝓵𝓮() { // 😀🎉🚀',
        reasoning = 'Emoji and math symbols',
      })

      local result = rpc.overlay_json_safe(json)
      local response = vim.json.decode(result)

      assert.is_true(response.success)
    end)

    it('should handle mixed line endings', function()
      local json = vim.json.encode({
        type = 'multiline',
        start_line = 1,
        end_line = 4,
        old_lines = {
          'function example() {',
          '  console.log("hello");',
          '  return true;',
          '}',
        },
        new_lines = {
          'function example() {\r\n',
          '  console.log("hello");\n',
          '  return true;\r',
          '}',
        },
        reasoning = 'Mixed line endings',
      })

      local result = rpc.overlay_json_safe(json)
      local response = vim.json.decode(result)

      assert.is_true(response.success)
    end)
  end)
end)
