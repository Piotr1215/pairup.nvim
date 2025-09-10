-- Tests for RPC variant overlay functions
local helpers = require('test.helpers')

describe('RPC variant functions', function()
  local rpc
  local overlay_api
  local bufnr

  before_each(function()
    -- Load the plugin with RPC enabled
    require('pairup').setup({
      rpc = { enabled = true, host = '127.0.0.1', port = 6666 },
    })

    rpc = require('pairup.rpc')
    overlay_api = require('pairup.overlay_api')

    -- Mock the main buffer
    bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(bufnr)

    -- Add test content
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      'function test() {',
      '  return true;',
      '}',
      '',
      'const data = getData();',
    })

    -- Mock get_main_buffer to return our test buffer
    rpc.get_main_buffer = function()
      return bufnr
    end

    -- Also mock get_state which overlay_api uses
    rpc.get_state = function()
      return { main_buffer = bufnr }
    end
  end)

  after_each(function()
    -- Clean up
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end)

  describe('overlay_single_variants_json', function()
    it('should create single line variants from JSON', function()
      local json = vim.json.encode({
        { new_text = 'async function test() {', reasoning = 'Make async' },
        { new_text = 'const test = () => {', reasoning = 'Arrow function' },
      })

      local result = rpc.overlay_single_variants_json(1, json)
      assert.is_true(result.success)

      -- Check overlay was created
      local overlay = require('pairup.overlay')
      local suggestions = overlay.get_suggestions(bufnr)
      assert.is_not_nil(suggestions[1])
      assert.is_not_nil(suggestions[1].variants)
      assert.equals(2, #suggestions[1].variants)
    end)

    it('should handle invalid JSON gracefully', function()
      local invalid_json = '{"broken": json'

      local result = rpc.overlay_single_variants_json(1, invalid_json)
      assert.is_false(result.success)
      assert.is_not_nil(result.error)
      assert.truthy(result.error:match('JSON decode failed'))
    end)

    it('should handle empty variants array', function()
      local json = vim.json.encode({})

      local result = rpc.overlay_single_variants_json(1, json)
      -- Should succeed but not create overlay
      assert.is_true(result.success)

      local overlay = require('pairup.overlay')
      local suggestions = overlay.get_suggestions(bufnr)
      assert.is_nil(suggestions[1])
    end)
  end)

  describe('overlay_multiline_variants_json', function()
    it('should create multiline variants from JSON', function()
      local json = vim.json.encode({
        {
          new_lines = {
            'async function test() {',
            '  return await Promise.resolve(true);',
            '}',
          },
          reasoning = 'Async version',
        },
        {
          new_lines = {
            'const test = () => true;',
          },
          reasoning = 'One-liner arrow',
        },
      })

      local result = rpc.overlay_multiline_variants_json(1, 3, json)
      assert.is_true(result.success)

      -- Check overlay was created
      local overlay = require('pairup.overlay')
      local suggestions = overlay.get_suggestions(bufnr)
      assert.is_not_nil(suggestions[1])
      assert.is_true(suggestions[1].is_multiline)
      assert.equals(2, #suggestions[1].variants)
    end)

    it('should handle deletion variants', function()
      local json = vim.json.encode({
        { new_lines = {}, reasoning = 'Delete function' },
        { new_lines = { '// Removed' }, reasoning = 'Comment placeholder' },
      })

      local result = rpc.overlay_multiline_variants_json(1, 3, json)
      assert.is_true(result.success)

      local overlay = require('pairup.overlay')
      local suggestions = overlay.get_suggestions(bufnr)
      assert.is_not_nil(suggestions[1])

      -- First variant should be deletion
      local first_variant = suggestions[1].variants[1]
      assert.is_not_nil(first_variant.new_lines)
      assert.equals(0, #first_variant.new_lines)
    end)
  end)

  describe('overlay_multiline_variants_b64', function()
    it('should decode base64 and create variants', function()
      -- Create JSON
      local variants = {
        {
          new_lines = { 'const test = `template`;' },
          reasoning = 'Template literal',
        },
      }
      local json = vim.json.encode(variants)

      -- Encode to base64
      local b64 = vim.fn.system('echo -n ' .. vim.fn.shellescape(json) .. ' | base64')
      b64 = b64:gsub('\n', '') -- Remove newline

      local result = rpc.overlay_multiline_variants_b64(1, 3, b64)
      assert.is_true(result.success)

      -- Check overlay was created
      local overlay = require('pairup.overlay')
      local suggestions = overlay.get_suggestions(bufnr)
      assert.is_not_nil(suggestions[1])
      assert.equals(1, #suggestions[1].variants)
    end)

    it('should handle invalid base64 gracefully', function()
      local invalid_b64 = 'not-valid-base64!@#$'

      local result = rpc.overlay_multiline_variants_b64(1, 3, invalid_b64)
      assert.is_false(result.success)
      assert.is_not_nil(result.error)
      assert.truthy(result.error:match('Failed to decode'))
    end)

    it('should handle complex content with special characters', function()
      -- JSON with quotes, backticks, newlines
      local variants = {
        {
          new_lines = {
            'const test = () => {',
            '  return `Hello "world" with \'quotes\'`;',
            '};',
          },
          reasoning = 'Complex string handling',
        },
      }
      local json = vim.json.encode(variants)

      -- Encode to base64
      local b64 = vim.fn.system('echo -n ' .. vim.fn.shellescape(json) .. ' | base64')
      b64 = b64:gsub('\n', '')

      local result = rpc.overlay_multiline_variants_b64(1, 3, b64)
      assert.is_true(result.success)

      -- Verify the complex content was preserved
      local overlay = require('pairup.overlay')
      local suggestions = overlay.get_suggestions(bufnr)
      assert.is_not_nil(suggestions[1])

      local variant = suggestions[1].variants[1]
      assert.equals('  return `Hello "world" with \'quotes\'`;', variant.new_lines[2])
    end)
  end)

  describe('JSON vs Base64 comparison', function()
    it('should produce identical results', function()
      local variants = {
        { new_text = 'Option 1', reasoning = 'First' },
        { new_text = 'Option 2', reasoning = 'Second' },
      }

      -- Test with JSON
      local json = vim.json.encode(variants)
      local json_result = rpc.overlay_single_variants_json(5, json)
      assert.is_true(json_result.success)

      -- Get the created overlay
      local overlay = require('pairup.overlay')
      local json_suggestions = overlay.get_suggestions(bufnr)

      -- Clear for next test
      overlay.clear_overlays()

      -- Test with Base64 (using multiline for b64 test)
      local b64_variants = {
        {
          new_lines = { 'Option 1' },
          reasoning = 'First',
        },
        {
          new_lines = { 'Option 2' },
          reasoning = 'Second',
        },
      }
      local b64_json = vim.json.encode(b64_variants)
      local b64 = vim.fn.system('echo -n ' .. vim.fn.shellescape(b64_json) .. ' | base64')
      b64 = b64:gsub('\n', '')

      local b64_result = rpc.overlay_multiline_variants_b64(5, 5, b64)
      assert.is_true(b64_result.success)

      -- Both should create overlays with 2 variants
      local b64_suggestions = overlay.get_suggestions(bufnr)
      assert.equals(2, #json_suggestions[5].variants)
      assert.equals(2, #b64_suggestions[5].variants)
    end)
  end)
end)
