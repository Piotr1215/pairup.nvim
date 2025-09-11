-- Tests for RPC variant overlay functions using new execute() method
local helpers = require('test.helpers')

describe('RPC variant functions', function()
  local rpc
  local overlay_api
  local bufnr

  before_each(function()
    -- Clear previous module loads
    package.loaded['pairup.rpc'] = nil
    package.loaded['pairup.overlay_api'] = nil
    package.loaded['pairup.overlay'] = nil

    -- Mock the main buffer first
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

    -- Load modules after buffer is created
    rpc = require('pairup.rpc')
    overlay_api = require('pairup.overlay_api')

    -- Mock RPC to be enabled
    rpc.check_rpc_available = function()
      return true
    end

    -- Mock update_layout to do nothing (avoid recursion)
    rpc.update_layout = function()
      -- No-op to avoid recursion
    end

    -- Setup RPC with mocked availability
    rpc.setup()

    -- Call original update_layout to initialize the state structure
    local original_update = rpc.update_layout
    original_update()

    -- Get and modify the actual internal state table
    local state = rpc.get_state()
    state.enabled = true
    state.main_buffer = bufnr
    state.main_window = 1

    -- Override update_layout to not change our setup
    rpc.update_layout = function()
      -- Keep our state as-is
    end
  end)

  after_each(function()
    -- Clean up
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end)

  describe('execute with single line', function()
    it('should handle single line changes', function()
      local result = rpc.execute({
        line = 1,
        new_text = 'const test = () => {}',
        reasoning = 'Convert to arrow',
      })
      if type(result) == 'string' then
        result = vim.json.decode(result)
      end
      assert.is_true(result.success)
    end)

    it('should handle single line with variants', function()
      local result = rpc.execute({
        line = 1,
        variants = {
          { new_text = 'async function test() {', reasoning = 'Make async' },
          { new_text = 'const test = () => {', reasoning = 'Arrow function' },
        },
      })
      if type(result) == 'string' then
        result = vim.json.decode(result)
      end
      assert.is_true(result.success)
    end)

    it('should handle invalid variants gracefully', function()
      local result = rpc.execute({
        line = 1,
        variants = 'invalid', -- Should be an array
      })
      if type(result) == 'string' then
        result = vim.json.decode(result)
      end
      assert.is_false(result.success)
      assert.is_not_nil(result.error)
    end)

    it('should handle empty variants array', function()
      local result = rpc.execute({
        line = 1,
        variants = {},
      })
      if type(result) == 'string' then
        result = vim.json.decode(result)
      end
      assert.is_false(result.success) -- Should fail with empty variants
      assert.truthy(result.error:match('must be a non%-empty array'))
    end)
  end)

  describe('execute with multiline', function()
    it('should handle multiline changes', function()
      local result = rpc.execute({
        start_line = 1,
        end_line = 3,
        new_lines = { 'line1', 'line2', 'line3' },
        reasoning = 'Replace block',
      })
      if type(result) == 'string' then
        result = vim.json.decode(result)
      end
      assert.is_true(result.success)
    end)

    it('should handle multiline with variants', function()
      local result = rpc.execute({
        start_line = 1,
        end_line = 3,
        variants = {
          {
            new_lines = {
              'async function test() {',
              '  return await fetch();',
              '}',
            },
            reasoning = 'Async version',
          },
          {
            new_lines = {
              'const test = () => {',
              '  return fetch().then(r => r.json());',
              '};',
            },
            reasoning = 'Arrow function with promise',
          },
        },
      })
      if type(result) == 'string' then
        result = vim.json.decode(result)
      end
      assert.is_true(result.success)
    end)

    it('should auto-convert string to array in new_lines', function()
      local result = rpc.execute({
        start_line = 1,
        end_line = 3,
        variants = {
          {
            new_lines = 'single line string', -- Will be converted to array
            reasoning = 'Single line',
          },
        },
      })
      if type(result) == 'string' then
        result = vim.json.decode(result)
      end
      assert.is_true(result.success)
    end)
  end)

  describe('execute with complex content', function()
    it('should handle complex strings with quotes and escapes', function()
      local result = rpc.execute({
        line = 5,
        new_text = [[const json = '{"key": "value", "nested": {"array": [1, 2, 3]}}']],
        reasoning = 'Complex JSON string',
      })
      if type(result) == 'string' then
        result = vim.json.decode(result)
      end
      assert.is_true(result.success)
    end)

    it('should handle multiline with special characters', function()
      local result = rpc.execute({
        start_line = 1,
        end_line = 3,
        new_lines = {
          [[local pattern = "\\w+@[a-zA-Z_]+?\\..[a-zA-Z]{2,3}"]],
          [[print("Hello \"world\"")]],
          [[-- No escaping needed!]],
        },
        reasoning = 'Complex patterns',
      })
      if type(result) == 'string' then
        result = vim.json.decode(result)
      end
      assert.is_true(result.success)
    end)
  end)

  describe('vim command execution', function()
    it('should execute vim commands via execute', function()
      local result = rpc.execute({ command = 'echo "test"' })
      if type(result) == 'string' then
        result = vim.json.decode(result)
      end
      assert.is_true(result.success)
    end)

    it('should handle command errors gracefully', function()
      local result = rpc.execute({ command = 'invalid_command_xyz' })
      if type(result) == 'string' then
        result = vim.json.decode(result)
      end
      assert.is_false(result.success)
      assert.is_not_nil(result.error)
    end)
  end)
end)
